import sqlite3
from config import DATABASE_PATH


def get_db():
    conn = sqlite3.connect(DATABASE_PATH)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA foreign_keys=ON")
    return conn


def init_db():
    conn = get_db()
    cursor = conn.cursor()

    cursor.executescript("""
        CREATE TABLE IF NOT EXISTS patients (
            id          TEXT PRIMARY KEY,
            name        TEXT NOT NULL,
            dob         TEXT DEFAULT '',
            age         INTEGER DEFAULT 0,
            gender      TEXT DEFAULT 'Not Specified',
            blood_group TEXT DEFAULT 'Not Specified',
            mobile      TEXT DEFAULT '',
            address     TEXT DEFAULT '',
            last_diagnosis   TEXT DEFAULT '',
            last_visit_date  TEXT DEFAULT '',
            created_at  TEXT NOT NULL,
            updated_at  TEXT NOT NULL,
            is_synced   INTEGER DEFAULT 0
        );

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
            discount            TEXT DEFAULT '0',
            payment_mode        TEXT DEFAULT '',
            charge_type         TEXT DEFAULT '',
            previous_visit_date TEXT DEFAULT '',
            follow_up_reason    TEXT DEFAULT '',
            next_visit          TEXT DEFAULT '',
            blood_group         TEXT DEFAULT '',
            image_links         TEXT DEFAULT '',
            created_at          TEXT NOT NULL,
            updated_at          TEXT NOT NULL,
            is_synced           INTEGER DEFAULT 0,
            FOREIGN KEY (patient_id) REFERENCES patients(id) ON DELETE CASCADE
        );

        CREATE TABLE IF NOT EXISTS appointments (
            id          TEXT PRIMARY KEY,
            patient_id  TEXT DEFAULT '',
            patient_name TEXT DEFAULT '',
            date_time   TEXT NOT NULL,
            notes       TEXT DEFAULT '',
            created_at  TEXT NOT NULL,
            updated_at  TEXT NOT NULL,
            is_synced   INTEGER DEFAULT 0
        );

        CREATE TABLE IF NOT EXISTS users (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            username    TEXT UNIQUE NOT NULL,
            password    TEXT NOT NULL,
            name        TEXT DEFAULT 'Doctor',
            created_at  TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS fcm_tokens (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            fcm_token   TEXT NOT NULL,
            user_id     TEXT DEFAULT '',
            created_at  TEXT NOT NULL,
            updated_at  TEXT NOT NULL
        );

        CREATE UNIQUE INDEX IF NOT EXISTS idx_fcm_token ON fcm_tokens(fcm_token);

        CREATE INDEX IF NOT EXISTS idx_opd_patient ON opd_records(patient_id);
        CREATE INDEX IF NOT EXISTS idx_opd_visit   ON opd_records(visit_date);
        CREATE INDEX IF NOT EXISTS idx_appt_date   ON appointments(date_time);
    """)

    # Migration: add image_links column for existing databases
    try:
        cursor.execute("ALTER TABLE opd_records ADD COLUMN image_links TEXT DEFAULT ''")
    except sqlite3.OperationalError:
        pass  # column already exists

    conn.commit()
    conn.close()
