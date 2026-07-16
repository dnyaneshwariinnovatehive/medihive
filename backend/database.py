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

    def __init__(self, conn):
        self._conn = conn
        self._cursor = conn.cursor(cursor_factory=RealDictCursor)

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

    def close(self):
        try:
            self._cursor.close()
        except Exception:
            pass
        try:
            get_pool().putconn(self._conn)
        except Exception:
            pass


def get_db():
    """Get a database connection from the pool.
    Lazily initializes the database schema on first call.
    Retries once if the pool needs re-creation (e.g., after Neon auto-suspend)."""
    _init_db()
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
            return DBConnection(conn)
        except (psycopg2.OperationalError, psycopg2.InterfaceError) as e:
            logger.warning("get_db attempt %d failed: %s", attempt + 1, e)
            if attempt == 0:
                reset_pool()
                time.sleep(1)
                continue
            raise


def _init_db():
    """Lazy initialization: called on first get_db() call.
    Creates all database tables if they don't exist and seeds the default admin user.
    Idempotent — safe to call multiple times.
    Only marks initialization complete AFTER successful commit."""
    global _db_initialized
    if _db_initialized:
        return

    logger.critical("MIGRATION_TEST: init_db executed with panchakarma migration")
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
                id              TEXT PRIMARY KEY,
                full_name       TEXT NOT NULL,
                mobile_number   TEXT NOT NULL,
                alternate_mobile TEXT DEFAULT '',
                gender          TEXT NOT NULL DEFAULT 'Not Specified',
                dob             TEXT DEFAULT '',
                age             INTEGER DEFAULT 0,
                blood_group     TEXT DEFAULT 'Not Specified',
                address         TEXT DEFAULT '',
                created_at      TEXT NOT NULL
            );
        """)
        # Migrations for patients schema renaming
        _last_sql = "ALTER TABLE patients RENAME COLUMN name TO full_name (migration)"
        logger.debug("INIT_DB SQL [02]: %s", _last_sql)
        try:
            db.execute("ALTER TABLE patients RENAME COLUMN name TO full_name")
        except Exception as e:
            logger.debug("INIT_DB SQL [02]: skipped — %s", e)
            db.rollback()
        _last_sql = "ALTER TABLE patients RENAME COLUMN mobile TO mobile_number (migration)"
        logger.debug("INIT_DB SQL [03]: %s", _last_sql)
        try:
            db.execute("ALTER TABLE patients RENAME COLUMN mobile TO mobile_number")
        except Exception as e:
            logger.debug("INIT_DB SQL [03]: skipped — %s", e)
            db.rollback()
        _last_sql = "ALTER TABLE patients ADD COLUMN alternate_mobile (migration)"
        logger.debug("INIT_DB SQL [04]: %s", _last_sql)
        try:
            db.execute("ALTER TABLE patients ADD COLUMN alternate_mobile TEXT DEFAULT ''")
        except Exception as e:
            logger.debug("INIT_DB SQL [04]: skipped — %s", e)
            db.rollback()

        # --- [05] CREATE opd_visits ---
        _last_sql = "CREATE TABLE IF NOT EXISTS opd_visits"
        logger.debug("INIT_DB SQL [05]: %s", _last_sql)
        db.execute("""
            CREATE TABLE IF NOT EXISTS opd_visits (
                id                  TEXT PRIMARY KEY,
                patient_id          TEXT NOT NULL,
                opd_id              TEXT,
                opd_type            TEXT DEFAULT 'consultation',
                symptoms            TEXT DEFAULT '',
                diagnosis           TEXT DEFAULT '',
                medicines           TEXT DEFAULT '',
                visit_datetime      TEXT NOT NULL,
                clinical_notes      TEXT DEFAULT '',
                consultation_fee    TEXT DEFAULT '0',
                medicine_fee        TEXT DEFAULT '0',
                panchakarma_fee     TEXT DEFAULT '0',
                total_fee           TEXT DEFAULT '0',
                discount_value      TEXT DEFAULT '0',
                discount_type       TEXT DEFAULT 'None',
                payment_mode        TEXT DEFAULT '',
                charge_type         TEXT DEFAULT '',
                followup_status     TEXT DEFAULT '',
                next_visit_date     TEXT DEFAULT '',
                panchakarma_notes   TEXT DEFAULT '',
                created_at          TEXT NOT NULL
            );
        """)
        
        # Rename opd_records → opd_visits for existing databases
        _last_sql = "ALTER TABLE opd_records RENAME TO opd_visits (migration)"
        logger.debug("INIT_DB SQL [06]: %s", _last_sql)
        try:
            db.execute("ALTER TABLE opd_records RENAME TO opd_visits")
        except Exception as e:
            logger.debug("INIT_DB SQL [06]: skipped — %s", e)
            db.rollback()
        # Rename columns for existing databases
        _last_sql = "ALTER TABLE opd_visits RENAME COLUMN visit_date TO visit_datetime (migration)"
        logger.debug("INIT_DB SQL [07]: %s", _last_sql)
        try:
            db.execute("ALTER TABLE opd_visits RENAME COLUMN visit_date TO visit_datetime")
        except Exception as e:
            logger.debug("INIT_DB SQL [07]: skipped — %s", e)
            db.rollback()
        _last_sql = "ALTER TABLE opd_visits RENAME COLUMN type TO opd_type (migration)"
        logger.debug("INIT_DB SQL [08]: %s", _last_sql)
        try:
            db.execute("ALTER TABLE opd_visits RENAME COLUMN type TO opd_type")
        except Exception as e:
            logger.debug("INIT_DB SQL [08]: skipped — %s", e)
            db.rollback()
        _last_sql = "ALTER TABLE opd_visits RENAME COLUMN next_visit TO next_visit_date (migration)"
        logger.debug("INIT_DB SQL [09]: %s", _last_sql)
        try:
            db.execute("ALTER TABLE opd_visits RENAME COLUMN next_visit TO next_visit_date")
        except Exception as e:
            logger.debug("INIT_DB SQL [09]: skipped — %s", e)
            db.rollback()
        _last_sql = "ALTER TABLE opd_visits RENAME COLUMN follow_up_reason TO followup_status (migration)"
        logger.debug("INIT_DB SQL [10]: %s", _last_sql)
        try:
            db.execute("ALTER TABLE opd_visits RENAME COLUMN follow_up_reason TO followup_status")
        except Exception as e:
            logger.debug("INIT_DB SQL [10]: skipped — %s", e)
            db.rollback()
        _last_sql = "ALTER TABLE opd_visits RENAME COLUMN discount TO discount_value (migration)"
        logger.debug("INIT_DB SQL [11]: %s", _last_sql)
        try:
            db.execute("ALTER TABLE opd_visits RENAME COLUMN discount TO discount_value")
        except Exception as e:
            logger.debug("INIT_DB SQL [11]: skipped — %s", e)
            db.rollback()
        # Add columns for existing databases.
        _last_sql = "ALTER TABLE opd_visits ADD COLUMN opd_id (migration)"
        logger.debug("INIT_DB SQL [12]: %s", _last_sql)
        try:
            db.execute("ALTER TABLE opd_visits ADD COLUMN opd_id TEXT")
        except Exception as e:
            logger.debug("INIT_DB SQL [12]: skipped — %s", e)
            db.rollback()
        _last_sql = "ALTER TABLE opd_visits ADD COLUMN panchakarma_notes (migration)"
        logger.debug("INIT_DB SQL [13]: %s", _last_sql)
        try:
            db.execute("ALTER TABLE opd_visits ADD COLUMN panchakarma_notes TEXT DEFAULT ''")
        except Exception as e:
            logger.debug("INIT_DB SQL [13]: skipped — %s", e)
            db.rollback()
        _last_sql = "ALTER TABLE opd_visits ADD COLUMN panchakarma_fee (migration)"
        logger.debug("INIT_DB SQL [14]: %s", _last_sql)
        try:
            db.execute("ALTER TABLE opd_visits ADD COLUMN panchakarma_fee TEXT DEFAULT '0'")
        except Exception as e:
            logger.debug("INIT_DB SQL [14]: skipped — %s", e)
            db.rollback()
        _last_sql = "ALTER TABLE opd_visits ADD COLUMN total_fee (migration)"
        logger.debug("INIT_DB SQL [15]: %s", _last_sql)
        try:
            db.execute("ALTER TABLE opd_visits ADD COLUMN total_fee TEXT DEFAULT '0'")
        except Exception as e:
            logger.debug("INIT_DB SQL [15]: skipped — %s", e)
            db.rollback()
        _last_sql = "ALTER TABLE opd_visits ADD COLUMN discount_type (migration)"
        logger.debug("INIT_DB SQL [16]: %s", _last_sql)
        try:
            db.execute("ALTER TABLE opd_visits ADD COLUMN discount_type TEXT DEFAULT 'None'")
        except Exception as e:
            logger.debug("INIT_DB SQL [16]: skipped — %s", e)
            db.rollback()

        # --- [17] CREATE INDEX ix_opd_visits_opd_id ---
        _last_sql = "CREATE UNIQUE INDEX IF NOT EXISTS ix_opd_visits_opd_id"
        logger.debug("INIT_DB SQL [17]: %s", _last_sql)
        db.execute("""
            CREATE UNIQUE INDEX IF NOT EXISTS ix_opd_visits_opd_id ON opd_visits (opd_id)
            WHERE opd_id IS NOT NULL
        """)

        # --- [18] CREATE appointments ---
        _last_sql = "CREATE TABLE IF NOT EXISTS appointments"
        logger.debug("INIT_DB SQL [18]: %s", _last_sql)
        db.execute("""
            CREATE TABLE IF NOT EXISTS appointments (
                id          TEXT PRIMARY KEY,
                patient_id  TEXT DEFAULT '',
                patient_name TEXT DEFAULT '',
                date_time   TEXT NOT NULL,
                notes       TEXT DEFAULT '',
                created_at  TEXT NOT NULL,
                updated_at  TEXT NOT NULL,
                is_synced   INTEGER DEFAULT 0,
                user_id     TEXT DEFAULT '',
                clinic_id   TEXT DEFAULT ''
            );
        """)

        # --- [19] CREATE users ---
        _last_sql = "CREATE TABLE IF NOT EXISTS users"
        logger.debug("INIT_DB SQL [19]: %s", _last_sql)
        db.execute("""
            CREATE TABLE IF NOT EXISTS users (
                id              SERIAL PRIMARY KEY,
                username        VARCHAR(50) UNIQUE NOT NULL,
                password_hash   VARCHAR(255) NOT NULL,
                email           VARCHAR(255) NOT NULL,
                created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                reset_otp       VARCHAR(10),
                otp_expiry      TIMESTAMP
            );
        """)
        # Migrations for users schema update
        _last_sql = "ALTER TABLE users RENAME COLUMN password TO password_hash (migration)"
        logger.debug("INIT_DB SQL [20]: %s", _last_sql)
        try:
            db.execute("ALTER TABLE users RENAME COLUMN password TO password_hash")
        except Exception as e:
            logger.debug("INIT_DB SQL [20]: skipped — %s", e)
            db.rollback()
        _last_sql = "ALTER TABLE users ADD COLUMN email (migration)"
        logger.debug("INIT_DB SQL [21]: %s", _last_sql)
        try:
            db.execute("ALTER TABLE users ADD COLUMN email VARCHAR(255) DEFAULT ''")
        except Exception as e:
            logger.debug("INIT_DB SQL [21]: skipped — %s", e)
            db.rollback()
        _last_sql = "ALTER TABLE users ADD COLUMN reset_otp (migration)"
        logger.debug("INIT_DB SQL [22]: %s", _last_sql)
        try:
            db.execute("ALTER TABLE users ADD COLUMN reset_otp VARCHAR(10)")
        except Exception as e:
            logger.debug("INIT_DB SQL [22]: skipped — %s", e)
            db.rollback()
        _last_sql = "ALTER TABLE users ADD COLUMN otp_expiry (migration)"
        logger.debug("INIT_DB SQL [23]: %s", _last_sql)
        try:
            db.execute("ALTER TABLE users ADD COLUMN otp_expiry TIMESTAMP")
        except Exception as e:
            logger.debug("INIT_DB SQL [23]: skipped — %s", e)
            db.rollback()

        # Create missing master/support tables
        # --- [24] CREATE calendar_notes ---
        _last_sql = "CREATE TABLE IF NOT EXISTS calendar_notes"
        logger.debug("INIT_DB SQL [24]: %s", _last_sql)
        db.execute("""
            CREATE TABLE IF NOT EXISTS calendar_notes (
                id              SERIAL PRIMARY KEY,
                note_date       DATE NOT NULL,
                note_text       TEXT,
                created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at      TIMESTAMP,
                UNIQUE (note_date)
            );
        """)

        # --- [25] CREATE clinic_settings ---
        _last_sql = "CREATE TABLE IF NOT EXISTS clinic_settings"
        logger.debug("INIT_DB SQL [25]: %s", _last_sql)
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
                created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at      TIMESTAMP
            );
        """)

        # --- [26] CREATE medicines ---
        _last_sql = "CREATE TABLE IF NOT EXISTS medicines"
        logger.debug("INIT_DB SQL [26]: %s", _last_sql)
        db.execute("""
            CREATE TABLE IF NOT EXISTS medicines (
                id              SERIAL PRIMARY KEY,
                name            VARCHAR(255) NOT NULL,
                UNIQUE (name)
            );
        """)

        # --- [27] CREATE symptoms_master ---
        _last_sql = "CREATE TABLE IF NOT EXISTS symptoms_master"
        logger.debug("INIT_DB SQL [27]: %s", _last_sql)
        db.execute("""
            CREATE TABLE IF NOT EXISTS symptoms_master (
                id              SERIAL PRIMARY KEY,
                name            TEXT NOT NULL,
                UNIQUE (name)
            );
        """)

        # --- [28] CREATE sync_queue ---
        _last_sql = "CREATE TABLE IF NOT EXISTS sync_queue"
        logger.debug("INIT_DB SQL [28]: %s", _last_sql)
        db.execute("""
            CREATE TABLE IF NOT EXISTS sync_queue (
                id              SERIAL PRIMARY KEY,
                entity_type     VARCHAR(20) NOT NULL,
                entity_id       VARCHAR(100) NOT NULL,
                status          VARCHAR(20) DEFAULT 'PENDING',
                retry_count     INTEGER DEFAULT 0,
                last_error      TEXT,
                created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                last_attempt    TIMESTAMP
            );
        """)

        # --- [29] CREATE clinics ---
        _last_sql = "CREATE TABLE IF NOT EXISTS clinics"
        logger.debug("INIT_DB SQL [29]: %s", _last_sql)
        db.execute("""
            CREATE TABLE IF NOT EXISTS clinics (
                id          TEXT PRIMARY KEY,
                name        TEXT NOT NULL,
                email       TEXT DEFAULT '',
                phone       TEXT DEFAULT '',
                address     TEXT DEFAULT '',
                created_at  TEXT NOT NULL,
                updated_at  TEXT NOT NULL
            );
        """)

        # --- [30] INSERT INTO clinics (seed default) ---
        _last_sql = "INSERT INTO clinics (seed default clinic)"
        logger.debug("INIT_DB SQL [30]: %s", _last_sql)
        db.execute(
            """
            INSERT INTO clinics (id, name, created_at, updated_at)
            VALUES (%s, %s, %s, %s)
            ON CONFLICT (id) DO NOTHING
            """,
            ('CLI001', 'Default Clinic', datetime.utcnow().isoformat(), datetime.utcnow().isoformat())
        )

        # --- [31] INSERT INTO users (seed admin) ---
        default_admin_password_hash = hashlib.sha256(
            DEFAULT_ADMIN_PASSWORD.encode()
        ).hexdigest()
        _last_sql = "INSERT INTO users (seed default admin)"
        logger.debug("INIT_DB SQL [31]: %s", _last_sql)
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

        # --- [32] CREATE fcm_tokens ---
        _last_sql = "CREATE TABLE IF NOT EXISTS fcm_tokens"
        logger.debug("INIT_DB SQL [32]: %s", _last_sql)
        db.execute("""
            CREATE TABLE IF NOT EXISTS fcm_tokens (
                id          SERIAL PRIMARY KEY,
                fcm_token   TEXT NOT NULL,
                user_id     TEXT DEFAULT '',
                created_at  TEXT NOT NULL,
                updated_at  TEXT NOT NULL
            );
        """)

        # --- [33] CREATE INDEX idx_fcm_token ---
        _last_sql = "CREATE UNIQUE INDEX IF NOT EXISTS idx_fcm_token"
        logger.debug("INIT_DB SQL [33]: %s", _last_sql)
        db.execute("""
            CREATE UNIQUE INDEX IF NOT EXISTS idx_fcm_token ON fcm_tokens(fcm_token);
        """)

        # --- [34] CREATE INDEX idx_opd_patient ---
        _last_sql = "CREATE INDEX IF NOT EXISTS idx_opd_patient"
        logger.debug("INIT_DB SQL [34]: %s", _last_sql)
        db.execute("""
            CREATE INDEX IF NOT EXISTS idx_opd_patient ON opd_visits(patient_id);
        """)

        # --- [35] CREATE INDEX idx_opd_visit ---
        _last_sql = "CREATE INDEX IF NOT EXISTS idx_opd_visit"
        logger.debug("INIT_DB SQL [35]: %s", _last_sql)
        db.execute("""
            CREATE INDEX IF NOT EXISTS idx_opd_visit ON opd_visits(visit_datetime);
        """)

        # --- [36] CREATE INDEX idx_appt_date ---
        _last_sql = "CREATE INDEX IF NOT EXISTS idx_appt_date"
        logger.debug("INIT_DB SQL [36]: %s", _last_sql)
        db.execute("""
            CREATE INDEX IF NOT EXISTS idx_appt_date ON appointments(date_time);
        """)

        # --- [37] CREATE deleted_entities ---
        _last_sql = "CREATE TABLE IF NOT EXISTS deleted_entities"
        logger.debug("INIT_DB SQL [37]: %s", _last_sql)
        db.execute("""
            CREATE TABLE IF NOT EXISTS deleted_entities (
                id          SERIAL PRIMARY KEY,
                entity_type TEXT NOT NULL,
                entity_id   TEXT NOT NULL,
                deleted_at  TEXT NOT NULL,
                user_id     TEXT DEFAULT '',
                clinic_id   TEXT DEFAULT ''
            );
        """)

        # --- [38] CREATE INDEX idx_deleted_at ---
        _last_sql = "CREATE INDEX IF NOT EXISTS idx_deleted_at"
        logger.debug("INIT_DB SQL [38]: %s", _last_sql)
        db.execute("""
            CREATE INDEX IF NOT EXISTS idx_deleted_at ON deleted_entities(deleted_at);
        """)

        # --- [39] CREATE INDEX idx_deleted_type_id ---
        _last_sql = "CREATE INDEX IF NOT EXISTS idx_deleted_type_id"
        logger.debug("INIT_DB SQL [39]: %s", _last_sql)
        db.execute("""
            CREATE INDEX IF NOT EXISTS idx_deleted_type_id ON deleted_entities(entity_type, entity_id);
        """)

        # --- [40] CREATE last_sync ---
        _last_sql = "CREATE TABLE IF NOT EXISTS last_sync"
        logger.debug("INIT_DB SQL [40]: %s", _last_sql)
        db.execute("""
            CREATE TABLE IF NOT EXISTS last_sync (
                id          SERIAL PRIMARY KEY,
                user_id     TEXT NOT NULL UNIQUE,
                last_sync   TEXT NOT NULL,
                created_at  TEXT NOT NULL,
                updated_at  TEXT NOT NULL
            );
        """)

        # --- [41] CREATE settings ---
        _last_sql = "CREATE TABLE IF NOT EXISTS settings"
        logger.debug("INIT_DB SQL [41]: %s", _last_sql)
        db.execute("""
            CREATE TABLE IF NOT EXISTS settings (
                key         TEXT PRIMARY KEY,
                value       TEXT NOT NULL
            );
        """)

        # --- [42] CREATE device_registry ---
        _last_sql = "CREATE TABLE IF NOT EXISTS device_registry"
        logger.debug("INIT_DB SQL [42]: %s", _last_sql)
        db.execute("""
            CREATE TABLE IF NOT EXISTS device_registry (
                id          SERIAL PRIMARY KEY,
                device_id   TEXT NOT NULL UNIQUE,
                device_name TEXT DEFAULT '',
                clinic_id   TEXT NOT NULL,
                fcm_token   TEXT DEFAULT '',
                app_version TEXT DEFAULT '',
                last_seen   TEXT DEFAULT '',
                created_at  TEXT NOT NULL,
                updated_at  TEXT NOT NULL
            );
        """)

        # --- [43] CREATE INDEX idx_device_registry_clinic ---
        _last_sql = "CREATE INDEX IF NOT EXISTS idx_device_registry_clinic"
        logger.debug("INIT_DB SQL [43]: %s", _last_sql)
        db.execute("""
            CREATE INDEX IF NOT EXISTS idx_device_registry_clinic ON device_registry(clinic_id);
        """)

        # --- [44] CREATE cloud_sync_log ---
        _last_sql = "CREATE TABLE IF NOT EXISTS cloud_sync_log"
        logger.debug("INIT_DB SQL [44]: %s", _last_sql)
        db.execute("""
            CREATE TABLE IF NOT EXISTS cloud_sync_log (
                id              SERIAL PRIMARY KEY,
                clinic_id       TEXT NOT NULL,
                device_id       TEXT DEFAULT '',
                direction       TEXT NOT NULL,
                patients_count  INTEGER DEFAULT 0,
                opd_count       INTEGER DEFAULT 0,
                appointments_count INTEGER DEFAULT 0,
                deleted_count   INTEGER DEFAULT 0,
                status          TEXT DEFAULT 'success',
                error_message   TEXT DEFAULT '',
                created_at      TEXT NOT NULL
            );
        """)

        # --- [45] CREATE patient_images ---
        _last_sql = "CREATE TABLE IF NOT EXISTS patient_images"
        logger.debug("INIT_DB SQL [45]: %s", _last_sql)
        db.execute("""
            CREATE TABLE IF NOT EXISTS patient_images (
                id              SERIAL PRIMARY KEY,
                patient_id      TEXT NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
                opd_visit_id    TEXT REFERENCES opd_visits(id) ON DELETE SET NULL,
                file_path       VARCHAR(500) NOT NULL,
                image_type      VARCHAR(50) DEFAULT NULL,
                sync_status     VARCHAR(30) DEFAULT 'Pending',
                uploaded_at     TIMESTAMP DEFAULT NULL,
                created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                drive_url       TEXT DEFAULT NULL
            );
        """)

        # --- [46] CREATE INDEX idx_patient_images_patient ---
        _last_sql = "CREATE INDEX IF NOT EXISTS idx_patient_images_patient"
        logger.debug("INIT_DB SQL [46]: %s", _last_sql)
        db.execute("""
            CREATE INDEX IF NOT EXISTS idx_patient_images_patient ON patient_images(patient_id);
        """)

        # --- [47] CREATE INDEX idx_patient_images_opd ---
        _last_sql = "CREATE INDEX IF NOT EXISTS idx_patient_images_opd"
        logger.debug("INIT_DB SQL [47]: %s", _last_sql)
        db.execute("""
            CREATE INDEX IF NOT EXISTS idx_patient_images_opd ON patient_images(opd_visit_id);
        """)

        db.commit()
        logger.debug("INIT_DB: all 47 statements succeeded, commit OK")
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
