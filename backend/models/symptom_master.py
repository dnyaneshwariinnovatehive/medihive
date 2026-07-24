from database import get_db
from datetime import datetime


class SymptomMaster:
    TABLE = 'symptoms_master'

    @staticmethod
    def dict_from_row(row):
        if row is None:
            return None
        return dict(row)

    @staticmethod
    def all():
        db = get_db()
        rows = db.execute("SELECT * FROM symptoms_master ORDER BY name ASC").fetchall()
        db.close()
        return [SymptomMaster.dict_from_row(r) for r in rows]

    @staticmethod
    def get(symptom_id):
        db = get_db()
        row = db.execute("SELECT * FROM symptoms_master WHERE id = %s", (symptom_id,)).fetchone()
        db.close()
        return SymptomMaster.dict_from_row(row)

    @staticmethod
    def get_by_name(name):
        db = get_db()
        row = db.execute("SELECT * FROM symptoms_master WHERE name = %s", (name,)).fetchone()
        db.close()
        return SymptomMaster.dict_from_row(row)

    @staticmethod
    def create(data):
        db = get_db()
        db.execute("""
            INSERT INTO symptoms_master (name)
            VALUES (%s)
            ON CONFLICT (name) DO NOTHING
        """, (data['name'],))
        db.commit()
        db.close()
        return SymptomMaster.get_by_name(data['name'])

    @staticmethod
    def upsert(data):
        existing = SymptomMaster.get_by_name(data.get('name', ''))
        if existing:
            return existing
        return SymptomMaster.create(data)

    @staticmethod
    def delete(symptom_id):
        db = get_db()
        db.execute("DELETE FROM symptoms_master WHERE id = %s", (symptom_id,))
        db.commit()
        db.close()

    @staticmethod
    def updated_since(timestamp):
        db = get_db()
        rows = db.execute(
            "SELECT * FROM symptoms_master ORDER BY id",
            ()
        ).fetchall()
        db.close()
        return [SymptomMaster.dict_from_row(r) for r in rows]
