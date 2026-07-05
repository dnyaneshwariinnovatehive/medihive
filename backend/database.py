import os
import time
import logging
import hashlib
from datetime import datetime
import psycopg2
from psycopg2 import pool
from psycopg2.extras import RealDictCursor
from config import DATABASE_URL, DB_POOL_MIN, DB_POOL_MAX, CONNECT_TIMEOUT

logger = logging.getLogger(__name__)

_pool = None
_pool_lock = False

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
    Retries once if the pool needs re-creation (e.g., after Neon auto-suspend)."""
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


def init_db():
    logger.critical("MIGRATION_TEST: init_db executed with panchakarma migration")
    """Create all database tables if they don't exist.
    Uses get_db() which includes Neon auto-suspend retry logic."""
    db = get_db()
    # Clear any stale aborted transaction from a previous connection use
    db.rollback()
    try:
        db.execute("""
            CREATE TABLE IF NOT EXISTS patients (
                id              TEXT PRIMARY KEY,
                name            TEXT NOT NULL,
                dob             TEXT DEFAULT '',
                age             INTEGER DEFAULT 0,
                gender          TEXT DEFAULT 'Not Specified',
                blood_group     TEXT DEFAULT 'Not Specified',
                mobile          TEXT DEFAULT '',
                address         TEXT DEFAULT '',
                last_diagnosis   TEXT DEFAULT '',
                last_visit_date  TEXT DEFAULT '',
                created_at      TEXT NOT NULL,
                updated_at      TEXT NOT NULL,
                is_synced       INTEGER DEFAULT 0,
                user_id         TEXT DEFAULT '',
                clinic_id       TEXT DEFAULT ''
            );
        """)
        db.execute("""
            CREATE TABLE IF NOT EXISTS opd_records (
                id                  TEXT PRIMARY KEY,
                patient_id          TEXT NOT NULL,
                type                TEXT DEFAULT 'consultation',
                symptoms            TEXT DEFAULT '',
                diagnosis           TEXT DEFAULT '',
                medicines           TEXT DEFAULT '',
                visit_date          TEXT NOT NULL,
                clinical_notes      TEXT DEFAULT '',
                consultation_fee    TEXT DEFAULT '0',
                medicine_fee        TEXT DEFAULT '0',
                panchakarma_fee     TEXT DEFAULT '0',
                total_fee           TEXT DEFAULT '0',
                discount            TEXT DEFAULT '0',
                discount_type       TEXT DEFAULT 'None',
                payment_mode        TEXT DEFAULT '',
                charge_type         TEXT DEFAULT '',
                previous_visit_date TEXT DEFAULT '',
                follow_up_reason    TEXT DEFAULT '',
                next_visit          TEXT DEFAULT '',
                blood_group         TEXT DEFAULT '',
                image_links         TEXT DEFAULT '',
                panchakarma_notes   TEXT DEFAULT '',
                created_at          TEXT NOT NULL,
                updated_at          TEXT NOT NULL,
                is_synced           INTEGER DEFAULT 0,
                user_id             TEXT DEFAULT '',
                clinic_id           TEXT DEFAULT ''
            );
        """)
        # Add columns for existing databases.
        # Each ALTER TABLE is followed by a rollback on failure because PostgreSQL
        # aborts the entire transaction when any statement fails, even if the
        # error is caught in Python.
        try:
            db.execute("ALTER TABLE opd_records ADD COLUMN panchakarma_notes TEXT DEFAULT ''")
        except Exception:
            db.rollback()
        try:
            db.execute("ALTER TABLE opd_records ADD COLUMN panchakarma_fee TEXT DEFAULT '0'")
        except Exception:
            db.rollback()
        try:
            db.execute("ALTER TABLE opd_records ADD COLUMN total_fee TEXT DEFAULT '0'")
        except Exception:
            db.rollback()
        try:
            db.execute("ALTER TABLE opd_records ADD COLUMN discount_type TEXT DEFAULT 'None'")
        except Exception:
            db.rollback()
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
        db.execute("""
            CREATE TABLE IF NOT EXISTS users (
                id          SERIAL PRIMARY KEY,
                username    TEXT UNIQUE NOT NULL,
                password    TEXT NOT NULL,
                name        TEXT DEFAULT 'Doctor',
                created_at  TEXT NOT NULL,
                clinic_id   TEXT DEFAULT ''
            );
        """)
        default_admin_password_hash = hashlib.sha256(
            DEFAULT_ADMIN_PASSWORD.encode()
        ).hexdigest()
        db.execute(
            """
            INSERT INTO users (username, password, name, created_at)
            VALUES (%s, %s, %s, %s)
            ON CONFLICT (username) DO UPDATE SET
                password = EXCLUDED.password,
                name = EXCLUDED.name
            """,
            (
                DEFAULT_ADMIN_USERNAME,
                default_admin_password_hash,
                DEFAULT_ADMIN_NAME,
                datetime.utcnow().isoformat(),
            ),
        )
        db.execute("""
            CREATE TABLE IF NOT EXISTS fcm_tokens (
                id          SERIAL PRIMARY KEY,
                fcm_token   TEXT NOT NULL,
                user_id     TEXT DEFAULT '',
                created_at  TEXT NOT NULL,
                updated_at  TEXT NOT NULL
            );
        """)
        db.execute("""
            CREATE UNIQUE INDEX IF NOT EXISTS idx_fcm_token ON fcm_tokens(fcm_token);
        """)
        db.execute("""
            CREATE INDEX IF NOT EXISTS idx_opd_patient ON opd_records(patient_id);
        """)
        db.execute("""
            CREATE INDEX IF NOT EXISTS idx_opd_visit ON opd_records(visit_date);
        """)
        db.execute("""
            CREATE INDEX IF NOT EXISTS idx_appt_date ON appointments(date_time);
        """)
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
        db.execute("""
            CREATE INDEX IF NOT EXISTS idx_deleted_at ON deleted_entities(deleted_at);
        """)
        db.execute("""
            CREATE INDEX IF NOT EXISTS idx_deleted_type_id ON deleted_entities(entity_type, entity_id);
        """)
        db.execute("""
            CREATE TABLE IF NOT EXISTS last_sync (
                id          SERIAL PRIMARY KEY,
                user_id     TEXT NOT NULL UNIQUE,
                last_sync   TEXT NOT NULL,
                created_at  TEXT NOT NULL,
                updated_at  TEXT NOT NULL
            );
        """)
        db.execute("""
            CREATE TABLE IF NOT EXISTS settings (
                key         TEXT PRIMARY KEY,
                value       TEXT NOT NULL
            );
        """)
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
        db.execute("""
            CREATE INDEX IF NOT EXISTS idx_device_registry_clinic ON device_registry(clinic_id);
        """)
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
        db.commit()
    finally:
        db.close()
