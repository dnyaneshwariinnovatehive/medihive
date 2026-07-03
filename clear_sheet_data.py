"""
clear_sheet_data.py
===================
Standalone script to clear ALL OPD data from the Google Sheet and
backend SQLite database. Run this when you want a fresh start.

Usage:
  python clear_sheet_data.py

Requires the backend config and credentials to be properly set up.
"""
import sys
import os

# Ensure we can import from the backend package
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'backend'))

try:
    from desktop_google.sheets_service import clear_opd_sheet_data
except ImportError as e:
    print(f"ERROR: Could not import backend modules: {e}")
    print("Make sure you're running this from the project root directory.")
    sys.exit(1)


def main():
    print("=" * 60)
    print("  MediHive — Clear All OPD Sheet Data")
    print("=" * 60)
    print()
    print("WARNING: This will DELETE ALL data from:")
    print("  1. The 'opd_visits' tab in the Google Sheet")
    print("  2. The backend SQLite database (opd_records, patients)")
    print()
    confirm = input("Type 'YES' to confirm: ")
    if confirm != "YES":
        print("Cancelled.")
        return

    print()
    print("Clearing data...")
    try:
        rows = clear_opd_sheet_data()
        print(f"SUCCESS: Cleared {rows} data rows from the sheet.")
        print("The sheet now has only headers. Backend DB is also reset.")
    except RuntimeError as e:
        print(f"ERROR: {e}")
        print()
        print("TROUBLESHOOTING:")
        print("  1. Check that credentials/credentials.json exists")
        print("  2. Verify the service account has Editor access to the sheet")
        print("  3. Check that config.py has the correct GOOGLE_SHEET_ID")
        sys.exit(1)
    except Exception as e:
        print(f"ERROR: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
