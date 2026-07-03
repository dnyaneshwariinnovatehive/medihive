"""
Cloud Sync Cleanup Script
=========================
Deletes all cloud sync data from the backend SQLite database.

SAFE items (NOT deleted):
  - users table (admin accounts)
  - clinics table (clinic configuration)
  - settings table (app settings)
  - fcm_tokens table (push notification tokens)
  - sqlite_sequence (auto-increment counters)
  - Google Sheet ID, Drive folder ID config
  - Google API credentials (credentials.json, drive_token.json)
  - Local Flutter SQLite database
  - Sync logic code

DELETED items:
  - patients table (all rows)
  - opd_records table (all rows)
  - appointments table (all rows)
  - deleted_entities table (all rows)
  - device_registry table (all registered devices)
  - cloud_sync_log table (all sync history)
  - last_sync table (sync timestamps)
"""

import sqlite3
import sys
import os

DB_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'backend', 'medihive.db')

TABLES_TO_CLEAR = [
    'patients',
    'opd_records',
    'appointments',
    'deleted_entities',
    'device_registry',
    'cloud_sync_log',
    'last_sync',
]

TABLES_TO_PRESERVE = [
    'users',
    'clinics',
    'settings',
    'fcm_tokens',
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
    print("\nNext steps:")
    print("  1. Clear Google Sheet data rows (keep header)")
    print("  2. Delete test images from Google Drive folder")
    print("  3. Clear local Flutter cloud_sync_queue + device_registration tables")
    print("  4. Delete last_cloud_sync from SharedPreferences on each device")
    print("  5. Restart both devices to re-register")


if __name__ == '__main__':
    confirm()
    run()
