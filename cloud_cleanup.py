"""
Cloud Sync Cleanup Script
=========================
Deletes all cloud sync data from the backend SQLite database.

SAFE items (NOT deleted):
  - users table (admin accounts)
  - clinic_settings table (clinic configuration)
  - medicines, symptoms_master (master data)
  - calendar_notes, sync_queue, patient_images
  - sqlite_sequence (auto-increment counters)

DELETED items:
  - patients table (all rows)
  - opd_visits table (all rows)
"""

import sqlite3
import sys
import os

DB_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'backend', 'medihive.db')

TABLES_TO_CLEAR = [
    'patients',
    'opd_visits',
]

TABLES_TO_PRESERVE = [
    'users',
    'clinic_settings',
    'medicines',
    'symptoms_master',
    'calendar_notes',
    'sync_queue',
    'patient_images',
]


def confirm():
    if '--yes' in sys.argv:
        return
    print("=" * 70)
    print("  CLOUD SYNC DATA CLEANUP")
    print("=" * 70)
    print(f"\nDatabase: {DB_PATH}")
    print(f"\nTables to CLEAR ({len(TABLES_TO_CLEAR)}):")
    for t in TABLES_TO_CLEAR:
        print(f"  - {t}")
    print(f"\nTables to PRESERVE ({len(TABLES_TO_PRESERVE)}):")
    for t in TABLES_TO_PRESERVE:
        print(f"  - {t}")
    print()
    response = input("Type 'yes' to proceed with cleanup: ")
    if response.lower() != 'yes':
        print("Cleanup cancelled.")
        sys.exit(0)


def run():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    print(f"\nConnected to: {DB_PATH}\n")

    # Show counts before cleanup
    print("BEFORE CLEANUP:")
    print("-" * 40)
    for table in TABLES_TO_CLEAR:
        cursor.execute(f'SELECT COUNT(*) FROM "{table}"')
        count = cursor.fetchone()[0]
        print(f"  {table:25} {count} rows")

    # Execute DELETE
    print(f"\nExecuting DELETE on {len(TABLES_TO_CLEAR)} tables...")
    for table in TABLES_TO_CLEAR:
        cursor.execute(f'DELETE FROM "{table}"')
        deleted = cursor.rowcount
        print(f"  Deleted {deleted} rows from {table}")
    conn.commit()

    # Show counts after cleanup
    print("\n\nAFTER CLEANUP:")
    print("-" * 40)
    for table in TABLES_TO_CLEAR:
        cursor.execute(f'SELECT COUNT(*) FROM "{table}"')
        count = cursor.fetchone()[0]
        status = "OK (empty)" if count == 0 else f"WARNING: {count} rows remain"
        print(f"  {table:25} {count} rows  [{status}]")

    # Verify preserved tables are intact
    print("\nPreserved tables (should be unchanged):")
    print("-" * 40)
    for table in TABLES_TO_PRESERVE:
        cursor.execute(f'SELECT COUNT(*) FROM "{table}"')
        count = cursor.fetchone()[0]
        print(f"  {table:25} {count} rows")

    conn.close()

    print("\n" + "=" * 70)
    print("  CLEANUP COMPLETE")
    print("=" * 70)


if __name__ == '__main__':
    confirm()
    run()
