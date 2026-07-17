"""
Test all PostgreSQL query patterns used across MediHive backend models and routes.

These tests require a running PostgreSQL instance.
Set TEST_DATABASE_URL env var to point to a test database, e.g.:
  TEST_DATABASE_URL=postgresql://test:test@localhost:5432/test_medihive

Run with: python -m pytest backend/tests/ -v
"""

import os
import sys
import unittest
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from datetime import datetime
from tests.conftest import requires_pg, PG_AVAILABLE, PG_TEST_URL


# ─────────────────────────────────────────────────
# Helper: init a test schema
# ─────────────────────────────────────────────────

def _init_test_schema():
    """Create the test schema using database.init_db() with the test URL."""
    import psycopg2
    from psycopg2.extras import RealDictCursor

    conn = psycopg2.connect(PG_TEST_URL)
    cur = conn.cursor()
    cur.execute("DROP TABLE IF EXISTS patient_images, users, "
                "opd_visits, patients, calendar_notes, clinic_settings, medicines, symptoms_master, sync_queue CASCADE")
    conn.commit()
    cur.close()
    conn.close()

    # Monkey-patch DATABASE_URL so init_db() uses our test database
    import database as db_module
    import config
    original_url = config.DATABASE_URL
    config.DATABASE_URL = PG_TEST_URL

    # Reset the pool so init_db creates a new one with test URL
    if db_module._pool is not None:
        db_module._pool.closeall()
        db_module._pool = None

    db_module.init_db()

    config.DATABASE_URL = original_url


# ─────────────────────────────────────────────────
# Tests
# ─────────────────────────────────────────────────

@unittest.skipUnless(PG_AVAILABLE, "PostgreSQL not available (set TEST_DATABASE_URL)")
class TestPostgreSQLQueryPatterns(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        _init_test_schema()
        # Connect directly for schema inspection
        import psycopg2
        cls.pg_conn = psycopg2.connect(PG_TEST_URL)
        cls.pg_conn.autocommit = True
        cls.pg_cur = cls.pg_conn.cursor()

    @classmethod
    def tearDownClass(cls):
        if hasattr(cls, 'pg_cur'):
            cls.pg_cur.close()
        if hasattr(cls, 'pg_conn'):
            cls.pg_conn.close()

    # ── Schema Verification ─────────────────────

    def test_01_all_tables_exist(self):
        self.pg_cur.execute("""
            SELECT table_name FROM information_schema.tables
            WHERE table_schema = 'public'
        """)
        tables = {r[0] for r in self.pg_cur.fetchall()}
        expected = {'patients', 'opd_visits', 'users', 'patient_images',
                    'calendar_notes', 'clinic_settings', 'medicines', 'symptoms_master', 'sync_queue'}
        missing = expected - tables
        assert not missing, f"Missing tables: {missing}"

    def test_02_auto_increment_columns_are_serial(self):
        self.pg_cur.execute("""
            SELECT column_name, column_default, data_type
            FROM information_schema.columns
            WHERE table_name = 'users' AND column_name = 'id'
        """)
        row = self.pg_cur.fetchone()
        assert row is not None
        # SERIAL columns have a default from a sequence
        assert 'nextval' in (row[1] or ''), f"Expected serial default, got: {row}"

    # ── Patient Model Queries ───────────────────

    def test_03_patient_insert_and_select(self):
        from database import get_db
        now = datetime.utcnow().isoformat()
        db = get_db()
        db.execute("""
            INSERT INTO patients (id, full_name, dob, age, gender, blood_group, mobile_number, alternate_mobile,
                                  address, created_at)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
        """, ('P001', 'Test Patient', '1990-01-01', 34, 'Male', 'O+', '1234567890', '',
              'Test Address', now))
        db.commit()
        db.close()

        db = get_db()
        row = db.execute("SELECT * FROM patients WHERE id = %s", ('P001',)).fetchone()
        db.close()
        assert row is not None
        assert row['full_name'] == 'Test Patient'

    def test_04_patient_update_dynamic_fields(self):
        from database import get_db
        db = get_db()
        # Simulate the dynamic UPDATE pattern used in patient.py
        fields = ["full_name = %s", "age = %s"]
        values = ['Updated Name', 35]
        values.append('P001')
        db.execute(
            f"UPDATE patients SET {', '.join(fields)} WHERE id = %s",
            values
        )
        db.commit()
        db.close()

        db = get_db()
        row = db.execute("SELECT full_name, age FROM patients WHERE id = %s", ('P001',)).fetchone()
        db.close()
        assert row['full_name'] == 'Updated Name'
        assert row['age'] == 35

    def test_05_patient_assign_next_id(self):
        """Test the SUBSTR + CAST + COALESCE pattern for ID generation."""
        from database import get_db
        db = get_db()
        result = db.execute(
            "SELECT COALESCE(MAX(CAST(SUBSTR(TRIM(id), 2) AS INTEGER)), 0) + 1 AS nid "
            "FROM patients WHERE id LIKE 'P%%'"
        ).fetchone()
        db.close()
        assert result is not None
        next_id = int(result['nid'])
        assert next_id > 0, f"Expected positive next_id, got {next_id}"

    def test_06_patient_delete(self):
        from database import get_db
        now = datetime.utcnow().isoformat()
        db = get_db()
        db.execute("""
            INSERT INTO patients (id, full_name, created_at)
            VALUES (%s, %s, %s) ON CONFLICT DO NOTHING
        """, ('P_DEL', 'Delete Test', now))
        db.commit()
        db.close()

        db = get_db()
        db.execute("DELETE FROM patients WHERE id = %s", ('P_DEL',))
        db.commit()
        db.close()

    # ── OPD Record Model ────────────────────────

    def test_07_opd_insert_and_select(self):
        from database import get_db
        now = datetime.utcnow().isoformat()
        # Re-insert patient for FK
        db = get_db()
        db.execute("""
            INSERT INTO patients (id, full_name, created_at)
            VALUES (%s, %s, %s) ON CONFLICT DO NOTHING
        """, ('P002', 'OPD Patient', now))
        db.commit()
        db.close()

        db = get_db()
        db.execute("""
            INSERT INTO opd_visits
                (id, patient_id, opd_type, symptoms, diagnosis, medicines,
                 visit_datetime, clinical_notes, consultation_fee, medicine_fee,
                 discount_value, payment_mode, charge_type,
                 followup_status, next_visit_date,
                 created_at)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s,
                    %s, %s, %s, %s, %s,
                    %s)
        """, ('OPD001', 'P002', 'consultation', 'cough', 'cold', 'medicine',
              now, '', '100', '50', '0', 'cash', 'general',
              '', '',
              now))
        db.commit()
        db.close()

        db = get_db()
        row = db.execute(
            "SELECT * FROM opd_visits WHERE id = %s", ('OPD001',)
        ).fetchone()
        db.close()
        assert row is not None
        assert row['patient_id'] == 'P002'

    # ── ON CONFLICT Patterns (sync) ─────────────

    def test_10_on_conflict_do_nothing(self):
        from database import get_db
        now = datetime.utcnow().isoformat()
        db = get_db()
        db.execute("""
            INSERT INTO patients (id, full_name, created_at)
            VALUES (%s, %s, %s) ON CONFLICT DO NOTHING
        """, ('P002', 'Existing Patient', now))
        db.commit()
        db.close()
        # Verify no duplicate error, same row
        db = get_db()
        row = db.execute("SELECT full_name FROM patients WHERE id = %s", ('P002',)).fetchone()
        db.close()
        assert row['full_name'] == 'OPD Patient'

    # ── RETURNING Pattern (auth registration) ───

    def test_12_insert_returning_id(self):
        from database import get_db
        import hashlib
        now = datetime.utcnow().isoformat()
        username = f'test_user_{datetime.utcnow().timestamp()}'
        hashed = hashlib.sha256('test123'.encode()).hexdigest()
        db = get_db()
        row = db.execute(
            "INSERT INTO users (username, password_hash, email, created_at) "
            "VALUES (%s, %s, %s, %s) RETURNING id",
            (username, hashed, 'test@example.com', now)
        ).fetchone()
        db.commit()
        db.close()
        assert row is not None
        assert 'id' in row
        assert int(row['id']) > 0

    # ── LIKE Pattern ────────────────────────────

    def test_19_like_pattern(self):
        from database import get_db
        db = get_db()
        rows = db.execute(
            "SELECT id FROM patients WHERE id LIKE 'P%%'"
        ).fetchall()
        db.close()
        assert len(rows) >= 0  # query never errors

    # ── Subquery Pattern (Patient.delete cascade) ─

    def test_20_select_opd_by_patient(self):
        from database import get_db
        db = get_db()
        rows = db.execute(
            "SELECT id FROM opd_visits WHERE patient_id = %s", ('P002',)
        ).fetchall()
        db.close()
        assert len(rows) >= 1


@unittest.skipUnless(PG_AVAILABLE, "PostgreSQL not available (set TEST_DATABASE_URL)")
class TestDatabaseConnectionWrapper(unittest.TestCase):

    def test_get_db_returns_db_connection(self):
        from database import get_db
        db = get_db()
        assert hasattr(db, 'execute')
        assert hasattr(db, 'commit')
        assert hasattr(db, 'close')
        db.close()

    def test_execute_returns_cursor(self):
        from database import get_db
        db = get_db()
        cursor = db.execute("SELECT 1 AS val")
        assert cursor is not None
        row = cursor.fetchone()
        assert row['val'] == 1
        db.close()

    def test_dict_access_on_row(self):
        from database import get_db
        db = get_db()
        cursor = db.execute("SELECT 1 AS val")
        row = cursor.fetchone()
        assert dict(row) == {'val': 1}
        db.close()

    def test_multiple_statements_in_transaction(self):
        from database import get_db
        db = get_db()
        db.execute("DELETE FROM sync_queue WHERE entity_id LIKE 'multi_test_%%'")
        db.execute("INSERT INTO sync_queue (entity_type, entity_id, status) VALUES (%s, %s, %s)",
                   ('patient', 'multi_test_key', 'PENDING'))
        db.execute("INSERT INTO sync_queue (entity_type, entity_id, status) VALUES (%s, %s, %s)",
                   ('patient', 'multi_test_key2', 'PENDING'))
        db.commit()

        rows = db.execute("SELECT COUNT(*) AS cnt FROM sync_queue WHERE entity_id LIKE 'multi_test_%%'").fetchall()
        assert rows[0]['cnt'] >= 2
        db.close()
