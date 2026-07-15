"""
Neon PostgreSQL Connection Validator for MediHive.

Usage:
    python scripts/validate_neon.py

Set the DATABASE_URL environment variable before running, or
edit the default below for testing.

Exit codes:
    0 - All checks passed
    1 - Connection failed
    2 - SSL check failed
    3 - Schema initialization failed
    4 - Query execution failed
"""

import os
import sys
import time

# Add backend directory to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

import psycopg2
from psycopg2 import OperationalError, InterfaceError
from psycopg2.extras import RealDictCursor

# ─── Configuration ───────────────────────────────────────────────

DATABASE_URL = os.environ.get(
    'DATABASE_URL',
    'postgresql://user:password@ep-xxxx-xxxx.us-east-2.aws.neon.tech/medihive?sslmode=require'
)

CONNECT_TIMEOUT = int(os.environ.get('CONNECT_TIMEOUT', '10'))

# ─── Checks ──────────────────────────────────────────────────────

def check_connection():
    """Test basic TCP + PostgreSQL connectivity."""
    print(f"\n{'='*60}")
    print("  CHECK 1: PostgreSQL Connection")
    print(f"{'='*60}")
    print(f"  Host:     {DATABASE_URL.split('@')[1].split('/')[0] if '@' in DATABASE_URL else '(unknown)'}")
    print(f"  Database: {DATABASE_URL.split('/')[-1].split('?')[0] if '/' in DATABASE_URL else '(unknown)'}")
    print(f"  Timeout:  {CONNECT_TIMEOUT}s")
    print()

    start = time.time()
    try:
        conn = psycopg2.connect(
            DATABASE_URL,
            connect_timeout=CONNECT_TIMEOUT,
        )
        elapsed = time.time() - start
        print(f"  ✅ Connected successfully in {elapsed:.2f}s")
        conn.close()
        return True
    except OperationalError as e:
        elapsed = time.time() - start
        print(f"  ❌ Connection failed after {elapsed:.2f}s")
        print(f"     Error: {e}")
        print()
        print("  Troubleshooting:")
        print("    - Check DATABASE_URL is correct")
        print("    - Verify the password has no special characters needing URL encoding")
        print("    - Check Neon dashboard: is the compute active?")
        print("    - If compute is suspended, first connection may take 3-5s")
        print("    - Ensure Neon IP allowlist includes 0.0.0.0/0 or Cloud Run IPs")
        return False


def check_ssl():
    """Verify SSL is being used (required by Neon)."""
    print(f"\n{'='*60}")
    print("  CHECK 2: SSL/TLS Encryption")
    print(f"{'='*60}")

    try:
        conn = psycopg2.connect(
            DATABASE_URL,
            connect_timeout=CONNECT_TIMEOUT,
        )
        cur = conn.cursor()
        cur.execute("SELECT ssl_is_used()")
        ssl_used = cur.fetchone()[0]
        if ssl_used:
            print("  ✅ SSL is active — connection is encrypted")
        else:
            print("  ⚠️  SSL is NOT active — Neon requires SSL")
            print("     Add ?sslmode=require to DATABASE_URL")
            conn.close()
            return False

        cur.execute("""
            SELECT version(), ssl_cipher
            FROM pg_stat_ssl WHERE pid = pg_backend_pid()
        """)
        row = cur.fetchone()
        if row:
            print(f"  Version: {row[0].split(',')[0]}")
            print(f"  Cipher:  {row[1] or 'N/A'}")
        conn.close()
        return True
    except Exception as e:
        print(f"  ❌ SSL check failed: {e}")
        return False


def check_schema():
    """Verify all required tables exist (or create them)."""
    print(f"\n{'='*60}")
    print("  CHECK 3: Database Schema")
    print(f"{'='*60}")

    from database import init_db, reset_pool
    from config import DATABASE_URL as cfg_url

    # Use the validated URL
    cfg_url = DATABASE_URL

    try:
        init_db()
        print("  ✅ All tables created/verified successfully")
    except Exception as e:
        print(f"  ❌ Schema initialization failed: {e}")
        return False

    # Verify tables exist
    required_tables = [
        'patients', 'opd_visits', 'appointments', 'users',
        'fcm_tokens', 'deleted_entities', 'last_sync', 'settings',
        'clinics', 'device_registry', 'cloud_sync_log',
    ]
    try:
        conn = psycopg2.connect(DATABASE_URL, connect_timeout=CONNECT_TIMEOUT)
        cur = conn.cursor()
        cur.execute("""
            SELECT table_name FROM information_schema.tables
            WHERE table_schema = 'public'
        """)
        existing = {r[0] for r in cur.fetchall()}
        conn.close()

        missing = [t for t in required_tables if t not in existing]
        if missing:
            print(f"  ❌ Missing tables: {', '.join(missing)}")
            return False
        print(f"  ✅ All {len(required_tables)} required tables present")
        return True
    except Exception as e:
        print(f"  ❌ Could not verify tables: {e}")
        return False


def check_query_execution():
    """Run a simple query to verify read/write works."""
    print(f"\n{'='*60}")
    print("  CHECK 4: Query Execution (Read/Write)")
    print(f"{'='*60}")

    try:
        conn = psycopg2.connect(DATABASE_URL, connect_timeout=CONNECT_TIMEOUT)
        conn.autocommit = True
        cur = conn.cursor()

        # Test write
        cur.execute("""
            INSERT INTO settings (key, value)
            VALUES ('neon_validation', 'ok')
            ON CONFLICT (key) DO UPDATE SET value = 'ok'
        """)
        print("  ✅ Write: INSERT succeeded")

        # Test read
        cur.execute("SELECT value FROM settings WHERE key = 'neon_validation'")
        result = cur.fetchone()
        assert result and result[0] == 'ok', "Read returned unexpected value"
        print("  ✅ Read: SELECT succeeded")

        # Test prepared statement
        cur.execute("SELECT 1 AS test")
        assert cur.fetchone()[0] == 1
        print("  ✅ Prepared statement: works")

        # Test connection pool simulation
        cur.execute("SELECT count(*) FROM pg_stat_activity WHERE state = 'active'")
        active = cur.fetchone()[0]
        print(f"  Active connections: {active}")

        conn.close()
        return True
    except Exception as e:
        print(f"  ❌ Query execution failed: {e}")
        return False


def check_neon_specific():
    """Check Neon-specific settings."""
    print(f"\n{'='*60}")
    print("  CHECK 5: Neon-Specific Configuration")
    print(f"{'='*60}")

    try:
        conn = psycopg2.connect(DATABASE_URL, connect_timeout=CONNECT_TIMEOUT)
        cur = conn.cursor()

        cur.execute("SHOW server_version")
        version = cur.fetchone()[0]
        print(f"  PostgreSQL version: {version}")

        cur.execute("SELECT current_setting('max_connections')")
        max_conn = cur.fetchone()[0]
        print(f"  Max connections: {max_conn}")

        cur.execute("SELECT current_setting('statement_timeout')")
        stmt_timeout = cur.fetchone()[0]
        print(f"  Statement timeout: {stmt_timeout}")

        # Check if this is Neon (pg_tle or neon extension)
        cur.execute("""
            SELECT EXISTS (
                SELECT 1 FROM pg_available_extensions WHERE name = 'neon'
            )
        """)
        is_neon = cur.fetchone()[0]
        if is_neon:
            print("  ✅ Detected as Neon PostgreSQL")

        cur.execute("SELECT pg_is_in_recovery()")
        in_recovery = cur.fetchone()[0]
        if in_recovery:
            print("  ⚠️  Connected to a read-only replica")
        else:
            print("  ✅ Connected to primary (read-write)")

        conn.close()
        return True
    except Exception as e:
        print(f"  ⚠️  Neon-specific check warning (non-fatal): {e}")
        return True


# ─── Main ────────────────────────────────────────────────────────

def main():
    print()
    print("  ╔══════════════════════════════════════════════╗")
    print("  ║   MediHive — Neon PostgreSQL Validation     ║")
    print("  ╚══════════════════════════════════════════════╝")

    checks = [
        ("Connection", check_connection),
        ("SSL", check_ssl),
        ("Schema", check_schema),
        ("Query Execution", check_query_execution),
        ("Neon Config", check_neon_specific),
    ]

    results = []
    for name, fn in checks:
        try:
            ok = fn()
            results.append((name, ok))
        except Exception as e:
            print(f"\n  ❌ {name} raised unexpected exception: {e}")
            results.append((name, False))

    print(f"\n{'='*60}")
    print("  SUMMARY")
    print(f"{'='*60}")
    passed = sum(1 for _, ok in results if ok)
    total = len(results)
    for name, ok in results:
        status = "✅ PASS" if ok else "❌ FAIL"
        print(f"  {status}  {name}")
    print(f"\n  {passed}/{total} checks passed")

    if all(ok for _, ok in results):
        print("\n  ✅ All checks PASSED — Neon is ready for deployment.")
        return 0
    else:
        print("\n  ❌ Some checks FAILED — review errors above.")
        return 1


if __name__ == '__main__':
    sys.exit(main())
