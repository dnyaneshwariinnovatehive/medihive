from database import get_db
from datetime import datetime


class Medicine:
    TABLE = 'medicines'

    @staticmethod
    def dict_from_row(row):
        if row is None:
            return None
        return dict(row)

    @staticmethod
    def all():
        db = get_db()
        rows = db.execute("SELECT * FROM medicines ORDER BY name ASC").fetchall()
        db.close()
        return [Medicine.dict_from_row(r) for r in rows]

    @staticmethod
    def get(medicine_id):
        db = get_db()
        row = db.execute("SELECT * FROM medicines WHERE id = %s", (medicine_id,)).fetchone()
        db.close()
        return Medicine.dict_from_row(row)

    @staticmethod
    def get_by_name(name):
        db = get_db()
        row = db.execute("SELECT * FROM medicines WHERE name = %s", (name,)).fetchone()
        db.close()
        return Medicine.dict_from_row(row)

    @staticmethod
    def create(data):
        db = get_db()
        db.execute("""
            INSERT INTO medicines (name)
            VALUES (%s)
            ON CONFLICT (name) DO NOTHING
        """, (data['name'],))
        db.commit()
        db.close()
        return Medicine.get_by_name(data['name'])

    @staticmethod
    def upsert(data):
        existing = Medicine.get_by_name(data.get('name', ''))
        if existing:
            return existing
        return Medicine.create(data)

    @staticmethod
    def delete(medicine_id):
        db = get_db()
        db.execute("DELETE FROM medicines WHERE id = %s", (medicine_id,))
        db.commit()
        db.close()

    @staticmethod
    def updated_since(timestamp):
        db = get_db()
        rows = db.execute(
            "SELECT * FROM medicines ORDER BY id",
            ()
        ).fetchall()
        db.close()
        return [Medicine.dict_from_row(r) for r in rows]
