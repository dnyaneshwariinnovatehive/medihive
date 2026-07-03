import sqlite3
import sys

db_path = sys.argv[1] if len(sys.argv) > 1 else 'backend/medihive.db'
conn = sqlite3.connect(db_path)
cursor = conn.cursor()

# Get all tables
cursor.execute("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
tables = cursor.fetchall()

print(f"Database: {db_path}")
print(f"Tables found: {len(tables)}\n")

for t in tables:
    name = t[0]
    cursor.execute(f'PRAGMA table_info("{name}")')
    cols = cursor.fetchall()
    cursor.execute(f'SELECT COUNT(*) FROM "{name}"')
    count = cursor.fetchone()[0]
    print(f"=== {name} (rows: {count}) ===")
    for c in cols:
        nullable = "YES" if c[3] == 0 else "NO"
        print(f"  {c[1]:30} {c[2]:15} nullable={nullable}  default={c[4]}")
    print()

conn.close()
