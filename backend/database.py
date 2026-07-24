import os
import time
import logging
import hashlib
import traceback
from datetime import datetime
import psycopg2
from psycopg2 import pool
from psycopg2.extras import RealDictCursor
from config import DATABASE_URL, DB_POOL_MIN, DB_POOL_MAX, CONNECT_TIMEOUT

logger = logging.getLogger(__name__)

_pool = None
_pool_lock = False
_db_initialized = False

DEFAULT_ADMIN_USERNAME = 'admin_medihive'
DEFAULT_ADMIN_PASSWORD = '1234567890'
DEFAULT_ADMIN_NAME = 'Admin'


def _build_connection_kwargs():
    """Build connection keyword arguments with Neon-optimized settings."""
    return {
        'dsn': DATABASE_URL,
        'connect_timeout': CONNECT_TIMEOUT,
        'keepalives': 1,
        'keepalives_idle': 30,
        'keepalives_interval': 10,
        'keepalives_count': 5,
    }


def get_pool():
    global _pool, _pool_lock
    if _pool is None and not _pool_lock:
        _pool_lock = True
        try:
            _pool = pool.ThreadedConnectionPool(
                minconn=0,
                maxconn=DB_POOL_MAX,
                **_build_connection_kwargs(),
            )
        except Exception as e:
            logger.error("Failed to create connection pool: %s", e)
            _pool_lock = False
            raise
        _pool_lock = False
    return _pool


def reset_pool():
    """Close and reset the pool. Used after Neon auto-suspend recovery."""
    global _pool, _pool_lock
    old_pool = _pool
    _pool = None
    _pool_lock = False
    if old_pool is not None:
        try:
            old_pool.closeall()
        except Exception:
            pass


class DBConnection:
    """Wrapper around psycopg2 connection + RealDictCursor
    that mimics sqlite3's connection.execute() interface
    so model code requires minimal changes."""

    def __init__(self, conn, request_scoped=False):
        self._conn = conn
        self._cursor = conn.cursor(cursor_factory=RealDictCursor)
        self.request_scoped = request_scoped

    def execute(self, sql, params=None):
        try:
            self._cursor.execute(sql, params)
        except (psycopg2.OperationalError, psycopg2.InterfaceError) as e:
            logger.warning("Database connection error, attempting recovery: %s", e)
            reset_pool()
            raise
        return self._cursor

    def commit(self):
        try:
            self._conn.commit()
        except (psycopg2.OperationalError, psycopg2.InterfaceError) as e:
            logger.warning("Commit failed, connection may be stale: %s", e)
            reset_pool()
            raise

    def rollback(self):
        try:
            self._conn.rollback()
        except Exception:
            pass

    def savepoint(self, name):
        self._conn.cursor().execute(f"SAVEPOINT {name}")

    def rollback_to_savepoint(self, name):
        self._conn.cursor().execute(f"ROLLBACK TO SAVEPOINT {name}")

    def close(self):
        if self.request_scoped:
            # Leave open for request reuse
            return
        self._real_close()

    def _real_close(self):
        try:
            self._cursor.close()
        except Exception:
            pass
        try:
            get_pool().putconn(self._conn)
        except Exception:
            pass


def _checkout_conn():
    for attempt in range(2):
        try:
            pool_obj = get_pool()
            if pool_obj is None:
                if attempt == 0:
                    reset_pool()
                    time.sleep(1)
                    continue
                raise RuntimeError("Connection pool not available")
            conn = pool_obj.getconn()
            return conn
        except (psycopg2.OperationalError, psycopg2.InterfaceError) as e:
            logger.warning("_checkout_conn attempt %d failed: %s", attempt + 1, e)
            if attempt == 0:
                reset_pool()
                time.sleep(1)
                continue
            raise


def get_db():
    """Get a database connection from the pool.
    Lazily initializes the database schema on first call.
    Retries once if the pool needs re-creation (e.g., after Neon auto-suspend)."""
    _init_db()
    try:
        from flask import has_app_context, g
        if has_app_context():
            if 'db_conn' not in g:
                conn = _checkout_conn()
                g.db_conn = DBConnection(conn, request_scoped=True)
            return g.db_conn
    except ImportError:
        pass

    conn = _checkout_conn()
    return DBConnection(conn, request_scoped=False)


def teardown_db(exception):
    """Release request-scoped database connection back to pool."""
    try:
        from flask import g
        db_conn = g.pop('db_conn', None)
        if db_conn is not None:
            if exception:
                db_conn.rollback()
            db_conn._real_close()
    except Exception as e:
        logger.error("Error in teardown_db: %s", e)


_column_cache = {}


def has_column(table_name, column_name):
    """Check if a column exists in a PostgreSQL table."""
    cache_key = (table_name, column_name)
    if cache_key in _column_cache:
        return _column_cache[cache_key]

    db = get_db()
    try:
        row = db.execute("""
            SELECT EXISTS (
                SELECT 1
                FROM information_schema.columns
                WHERE table_name = %s AND column_name = %s
            ) AS has_col
        """, (table_name, column_name)).fetchone()
        exists = row['has_col'] if row else False
        _column_cache[cache_key] = exists
        return exists
    except Exception as e:
        logger.warning("Error checking column %s in table %s: %s", column_name, table_name, e)
        return False
    finally:
        db.close()


def _init_db():
    """Lazy initialization: called on first get_db() call.
    Creates all database tables if they don't exist and seeds the default admin user.
    Idempotent — safe to call multiple times.
    Only marks initialization complete AFTER successful commit.
    Schema matches SQLite clinic.db / medihive.db — 9 tables."""
    global _db_initialized
    if _db_initialized:
        return

    logger.info("Initializing database schema matching medihive.db source of truth")
    pool_obj = get_pool()
    conn = pool_obj.getconn()
    db = DBConnection(conn)
    db.rollback()
    _last_sql = None
    try:
        # --- [01] CREATE patients ---
        _last_sql = "CREATE TABLE IF NOT EXISTS patients"
        logger.debug("INIT_DB SQL [01]: %s", _last_sql)
        db.execute("""
            CREATE TABLE IF NOT EXISTS patients (
                id              SERIAL PRIMARY KEY,
                full_name       VARCHAR(255) NOT NULL,
                mobile_number   VARCHAR(50) NOT NULL,
                alternate_mobile VARCHAR(50),
                gender          VARCHAR(50) NOT NULL,
                dob             DATE,
                age             INTEGER,
                blood_group     VARCHAR(20),
                address         TEXT,
                created_at      TIMESTAMP
            );
        """)
        # Migrations for patients schema renaming
        _last_sql = "ALTER TABLE patients RENAME COLUMN name TO full_name (migration)"
        logger.debug("INIT_DB SQL [02]: %s", _last_sql)
        db.savepoint("sp_mig_02")
        try:
            db.execute("ALTER TABLE patients RENAME COLUMN name TO full_name")
        except Exception as e:
            logger.debug("INIT_DB SQL [02]: skipped — %s", e)
            db.rollback_to_savepoint("sp_mig_02")
        _last_sql = "ALTER TABLE patients RENAME COLUMN mobile TO mobile_number (migration)"
        logger.debug("INIT_DB SQL [03]: %s", _last_sql)
        db.savepoint("sp_mig_03")
        try:
            db.execute("ALTER TABLE patients RENAME COLUMN mobile TO mobile_number")
        except Exception as e:
            logger.debug("INIT_DB SQL [03]: skipped — %s", e)
            db.rollback_to_savepoint("sp_mig_03")
        _last_sql = "ALTER TABLE patients ADD COLUMN alternate_mobile (migration)"
        logger.debug("INIT_DB SQL [04]: %s", _last_sql)
        db.savepoint("sp_mig_04")
        try:
            db.execute("ALTER TABLE patients ADD COLUMN alternate_mobile VARCHAR(50)")
        except Exception as e:
            logger.debug("INIT_DB SQL [04]: skipped — %s", e)
            db.rollback_to_savepoint("sp_mig_04")

        # --- [05] CREATE opd_visits ---
        _last_sql = "CREATE TABLE IF NOT EXISTS opd_visits"
        logger.debug("INIT_DB SQL [05]: %s", _last_sql)
        db.execute("""
            CREATE TABLE IF NOT EXISTS opd_visits (
                id                  SERIAL PRIMARY KEY,
                opd_id              VARCHAR(255) NOT NULL,
                patient_id          INTEGER NOT NULL REFERENCES patients(id),
                visit_datetime      TIMESTAMP NOT NULL,
                opd_type            VARCHAR(100),
                charge_type         VARCHAR(100),
                diagnosis           TEXT,
                symptoms            TEXT,
                clinical_notes      TEXT,
                consultation_fee    DOUBLE PRECISION,
                medicine_fee        DOUBLE PRECISION,
                panchakarma_fee     DOUBLE PRECISION,
                total_fee           DOUBLE PRECISION,
                discount_type       VARCHAR(100),
                discount_value      DOUBLE PRECISION,
                payment_mode        VARCHAR(100),
                next_visit_date     DATE,
                followup_status     VARCHAR(100),
                created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                medicines           TEXT,
                panchakarma_notes   TEXT
            );
        """)

        # Rename opd_records → opd_visits for existing databases
        _last_sql = "ALTER TABLE opd_records RENAME TO opd_visits (migration)"
        logger.debug("INIT_DB SQL [06]: %s", _last_sql)
        db.savepoint("sp_mig_06")
        try:
            db.execute("ALTER TABLE opd_records RENAME TO opd_visits")
        except Exception as e:
            logger.debug("INIT_DB SQL [06]: skipped — %s", e)
            db.rollback_to_savepoint("sp_mig_06")
        # Rename columns for existing databases
        _last_sql = "ALTER TABLE opd_visits RENAME COLUMN visit_date TO visit_datetime (migration)"
        logger.debug("INIT_DB SQL [07]: %s", _last_sql)
        db.savepoint("sp_mig_07")
        try:
            db.execute("ALTER TABLE opd_visits RENAME COLUMN visit_date TO visit_datetime")
        except Exception as e:
            logger.debug("INIT_DB SQL [07]: skipped — %s", e)
            db.rollback_to_savepoint("sp_mig_07")
        _last_sql = "ALTER TABLE opd_visits RENAME COLUMN type TO opd_type (migration)"
        logger.debug("INIT_DB SQL [08]: %s", _last_sql)
        db.savepoint("sp_mig_08")
        try:
            db.execute("ALTER TABLE opd_visits RENAME COLUMN type TO opd_type")
        except Exception as e:
            logger.debug("INIT_DB SQL [08]: skipped — %s", e)
            db.rollback_to_savepoint("sp_mig_08")
        _last_sql = "ALTER TABLE opd_visits RENAME COLUMN next_visit TO next_visit_date (migration)"
        logger.debug("INIT_DB SQL [09]: %s", _last_sql)
        db.savepoint("sp_mig_09")
        try:
            db.execute("ALTER TABLE opd_visits RENAME COLUMN next_visit TO next_visit_date")
        except Exception as e:
            logger.debug("INIT_DB SQL [09]: skipped — %s", e)
            db.rollback_to_savepoint("sp_mig_09")
        _last_sql = "ALTER TABLE opd_visits RENAME COLUMN follow_up_reason TO followup_status (migration)"
        logger.debug("INIT_DB SQL [10]: %s", _last_sql)
        db.savepoint("sp_mig_10")
        try:
            db.execute("ALTER TABLE opd_visits RENAME COLUMN follow_up_reason TO followup_status")
        except Exception as e:
            logger.debug("INIT_DB SQL [10]: skipped — %s", e)
            db.rollback_to_savepoint("sp_mig_10")
        _last_sql = "ALTER TABLE opd_visits RENAME COLUMN discount TO discount_value (migration)"
        logger.debug("INIT_DB SQL [11]: %s", _last_sql)
        db.savepoint("sp_mig_11")
        try:
            db.execute("ALTER TABLE opd_visits RENAME COLUMN discount TO discount_value")
        except Exception as e:
            logger.debug("INIT_DB SQL [11]: skipped — %s", e)
            db.rollback_to_savepoint("sp_mig_11")
        # Add columns for existing databases.
        _last_sql = "ALTER TABLE opd_visits ADD COLUMN opd_id (migration)"
        logger.debug("INIT_DB SQL [12]: %s", _last_sql)
        db.savepoint("sp_mig_12")
        try:
            db.execute("ALTER TABLE opd_visits ADD COLUMN opd_id VARCHAR(255)")
        except Exception as e:
            logger.debug("INIT_DB SQL [12]: skipped — %s", e)
            db.rollback_to_savepoint("sp_mig_12")
        _last_sql = "ALTER TABLE opd_visits ADD COLUMN panchakarma_notes (migration)"
        logger.debug("INIT_DB SQL [13]: %s", _last_sql)
        db.savepoint("sp_mig_13")
        try:
            db.execute("ALTER TABLE opd_visits ADD COLUMN panchakarma_notes TEXT")
        except Exception as e:
            logger.debug("INIT_DB SQL [13]: skipped — %s", e)
            db.rollback_to_savepoint("sp_mig_13")
        _last_sql = "ALTER TABLE opd_visits ADD COLUMN panchakarma_fee (migration)"
        logger.debug("INIT_DB SQL [14]: %s", _last_sql)
        db.savepoint("sp_mig_14")
        try:
            db.execute("ALTER TABLE opd_visits ADD COLUMN panchakarma_fee DOUBLE PRECISION")
        except Exception as e:
            logger.debug("INIT_DB SQL [14]: skipped — %s", e)
            db.rollback_to_savepoint("sp_mig_14")
        _last_sql = "ALTER TABLE opd_visits ADD COLUMN total_fee (migration)"
        logger.debug("INIT_DB SQL [15]: %s", _last_sql)
        db.savepoint("sp_mig_15")
        try:
            db.execute("ALTER TABLE opd_visits ADD COLUMN total_fee DOUBLE PRECISION")
        except Exception as e:
            logger.debug("INIT_DB SQL [15]: skipped — %s", e)
            db.rollback_to_savepoint("sp_mig_15")
        _last_sql = "ALTER TABLE opd_visits ADD COLUMN discount_type (migration)"
        logger.debug("INIT_DB SQL [16]: %s", _last_sql)
        db.savepoint("sp_mig_16")
        try:
            db.execute("ALTER TABLE opd_visits ADD COLUMN discount_type VARCHAR(100)")
        except Exception as e:
            logger.debug("INIT_DB SQL [16]: skipped — %s", e)
            db.rollback_to_savepoint("sp_mig_16")

        # --- [17] CREATE INDEX ix_opd_visits_opd_id ---
        _last_sql = "CREATE UNIQUE INDEX IF NOT EXISTS ix_opd_visits_opd_id"
        logger.debug("INIT_DB SQL [17]: %s", _last_sql)
        db.execute("""
            CREATE UNIQUE INDEX IF NOT EXISTS ix_opd_visits_opd_id ON opd_visits (opd_id)
        """)

        _last_sql = "CREATE INDEX IF NOT EXISTS ix_opd_visits_id"
        logger.debug("INIT_DB SQL [17b]: %s", _last_sql)
        db.execute("""
            CREATE INDEX IF NOT EXISTS ix_opd_visits_id ON opd_visits (id)
        """)

        # --- [18] CREATE users ---
        _last_sql = "CREATE TABLE IF NOT EXISTS users"
        logger.debug("INIT_DB SQL [18]: %s", _last_sql)
        db.execute("""
            CREATE TABLE IF NOT EXISTS users (
                id              SERIAL PRIMARY KEY,
                username        VARCHAR(50) UNIQUE NOT NULL,
                password_hash   VARCHAR(255) NOT NULL,
                email           VARCHAR(255) NOT NULL,
                created_at      TIMESTAMP,
                reset_otp       VARCHAR(10),
                otp_expiry      TIMESTAMP
            );
        """)
        # Migrations for users schema update
        _last_sql = "ALTER TABLE users RENAME COLUMN password TO password_hash (migration)"
        logger.debug("INIT_DB SQL [19]: %s", _last_sql)
        db.savepoint("sp_mig_19")
        try:
            db.execute("ALTER TABLE users RENAME COLUMN password TO password_hash")
        except Exception as e:
            logger.debug("INIT_DB SQL [19]: skipped — %s", e)
            db.rollback_to_savepoint("sp_mig_19")
        _last_sql = "ALTER TABLE users ADD COLUMN email (migration)"
        logger.debug("INIT_DB SQL [20]: %s", _last_sql)
        db.savepoint("sp_mig_20")
        try:
            db.execute("ALTER TABLE users ADD COLUMN email VARCHAR(255) DEFAULT ''")
        except Exception as e:
            logger.debug("INIT_DB SQL [20]: skipped — %s", e)
            db.rollback_to_savepoint("sp_mig_20")
        _last_sql = "ALTER TABLE users ADD COLUMN reset_otp (migration)"
        logger.debug("INIT_DB SQL [21]: %s", _last_sql)
        db.savepoint("sp_mig_21")
        try:
            db.execute("ALTER TABLE users ADD COLUMN reset_otp VARCHAR(10)")
        except Exception as e:
            logger.debug("INIT_DB SQL [21]: skipped — %s", e)
            db.rollback_to_savepoint("sp_mig_21")
        _last_sql = "ALTER TABLE users ADD COLUMN otp_expiry (migration)"
        logger.debug("INIT_DB SQL [22]: %s", _last_sql)
        db.savepoint("sp_mig_22")
        try:
            db.execute("ALTER TABLE users ADD COLUMN otp_expiry TIMESTAMP")
        except Exception as e:
            logger.debug("INIT_DB SQL [22]: skipped — %s", e)
            db.rollback_to_savepoint("sp_mig_22")

        _last_sql = "CREATE INDEX IF NOT EXISTS ix_users_id"
        logger.debug("INIT_DB SQL [22b]: %s", _last_sql)
        db.execute("""
            CREATE INDEX IF NOT EXISTS ix_users_id ON users (id);
        """)

        # --- [23] CREATE calendar_notes ---
        _last_sql = "CREATE TABLE IF NOT EXISTS calendar_notes"
        logger.debug("INIT_DB SQL [23]: %s", _last_sql)
        db.execute("""
            CREATE TABLE IF NOT EXISTS calendar_notes (
                id              SERIAL PRIMARY KEY,
                note_date       DATE NOT NULL UNIQUE,
                note_text       TEXT,
                created_at      TIMESTAMP,
                updated_at      TIMESTAMP
            );
        """)

        # --- [24] CREATE clinic_settings ---
        _last_sql = "CREATE TABLE IF NOT EXISTS clinic_settings"
        logger.debug("INIT_DB SQL [24]: %s", _last_sql)
        db.execute("""
            CREATE TABLE IF NOT EXISTS clinic_settings (
                id              SERIAL PRIMARY KEY,
                doctor_name     VARCHAR(255),
                doctor_email    VARCHAR(255),
                doctor_contact  VARCHAR(50),
                doctor_license_no VARCHAR(100),
                doctor_photo_path VARCHAR(500),
                clinic_name     VARCHAR(255),
                clinic_logo_path VARCHAR(500),
                clinic_address  TEXT,
                clinic_phone    VARCHAR(50),
                website         VARCHAR(255),
                operating_hours VARCHAR(255),
                smtp_email      VARCHAR(255),
                smtp_password   VARCHAR(255),
                smtp_server     VARCHAR(255),
                smtp_port       VARCHAR(10),
                created_at      TIMESTAMP,
                updated_at      TIMESTAMP
            );
        """)

        _last_sql = "CREATE INDEX IF NOT EXISTS ix_clinic_settings_id"
        logger.debug("INIT_DB SQL [24b]: %s", _last_sql)
        db.execute("""
            CREATE INDEX IF NOT EXISTS ix_clinic_settings_id ON clinic_settings (id);
        """)

        # --- [25] CREATE medicines ---
        _last_sql = "CREATE TABLE IF NOT EXISTS medicines"
        logger.debug("INIT_DB SQL [25]: %s", _last_sql)
        db.execute("""
            CREATE TABLE IF NOT EXISTS medicines (
                id              SERIAL PRIMARY KEY,
                name            VARCHAR(255) UNIQUE NOT NULL
            );
        """)

        # --- [26] CREATE symptoms_master ---
        _last_sql = "CREATE TABLE IF NOT EXISTS symptoms_master"
        logger.debug("INIT_DB SQL [26]: %s", _last_sql)
        db.execute("""
            CREATE TABLE IF NOT EXISTS symptoms_master (
                id              SERIAL PRIMARY KEY,
                name            TEXT UNIQUE NOT NULL
            );
        """)

        # --- [27] CREATE sync_queue ---
        _last_sql = "CREATE TABLE IF NOT EXISTS sync_queue"
        logger.debug("INIT_DB SQL [27]: %s", _last_sql)
        db.execute("""
            CREATE TABLE IF NOT EXISTS sync_queue (
                id              SERIAL PRIMARY KEY,
                entity_type     VARCHAR(20) NOT NULL,
                entity_id       VARCHAR(100) NOT NULL,
                status          VARCHAR(20),
                retry_count     INTEGER,
                last_error      TEXT,
                created_at      TIMESTAMP,
                last_attempt    TIMESTAMP
            );
        """)

        _last_sql = "CREATE INDEX IF NOT EXISTS ix_sync_queue_id"
        logger.debug("INIT_DB SQL [27b]: %s", _last_sql)
        db.execute("""
            CREATE INDEX IF NOT EXISTS ix_sync_queue_id ON sync_queue (id);
        """)

        # --- [28] INSERT INTO users (seed admin) ---
        default_admin_password_hash = hashlib.sha256(
            DEFAULT_ADMIN_PASSWORD.encode()
        ).hexdigest()
        _last_sql = "INSERT INTO users (seed default admin)"
        logger.debug("INIT_DB SQL [28]: %s", _last_sql)
        db.execute(
            """
            INSERT INTO users (username, password_hash, email, created_at)
            VALUES (%s, %s, %s, %s)
            ON CONFLICT (username) DO UPDATE SET
                password_hash = EXCLUDED.password_hash
            """,
            (
                DEFAULT_ADMIN_USERNAME,
                default_admin_password_hash,
                'admin@medihive.local',
                datetime.utcnow().isoformat(),
            ),
        )

        # --- [29] CREATE INDEX ix_patients_id ---
        _last_sql = "CREATE INDEX IF NOT EXISTS ix_patients_id"
        logger.debug("INIT_DB SQL [29]: %s", _last_sql)
        db.execute("""
            CREATE INDEX IF NOT EXISTS ix_patients_id ON patients (id);
        """)

        # --- [31] CREATE patient_images ---
        _last_sql = "CREATE TABLE IF NOT EXISTS patient_images"
        logger.debug("INIT_DB SQL [31]: %s", _last_sql)
        db.execute("""
            CREATE TABLE IF NOT EXISTS patient_images (
                id              SERIAL PRIMARY KEY,
                patient_id      INTEGER NOT NULL REFERENCES patients(id),
                opd_visit_id    INTEGER NOT NULL REFERENCES opd_visits(id),
                file_path       VARCHAR(500) NOT NULL,
                image_type      VARCHAR(50),
                sync_status     VARCHAR(50),
                uploaded_at     TIMESTAMP,
                created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                drive_url       TEXT
            );
        """)

        # --- [32] CREATE INDEX ix_patient_images_id ---
        _last_sql = "CREATE INDEX IF NOT EXISTS ix_patient_images_id"
        logger.debug("INIT_DB SQL [32]: %s", _last_sql)
        db.execute("""
            CREATE INDEX IF NOT EXISTS ix_patient_images_id ON patient_images (id);
        """)

        db.commit()
        logger.debug("INIT_DB: all statements succeeded, commit OK")
        _db_initialized = True
    except Exception as e:
        logger.critical("INIT_DB FAILED at statement: %s", _last_sql)
        logger.critical("INIT_DB POSTGRESQL EXCEPTION: %s", str(e))
        logger.critical("INIT_DB TRACEBACK:\n%s", traceback.format_exc())
        raise
    finally:
        db.close()


def init_db():
    """Public wrapper for explicit initialization (used by tests and scripts).
    Idempotent — safe to call multiple times."""
    _init_db()
