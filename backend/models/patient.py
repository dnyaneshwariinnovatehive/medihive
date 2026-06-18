from database import get_db
from datetime import datetime


class Patient:
    TABLE = 'patients'

    @staticmethod
    def dict_from_row(row):
        if row is None:
            return None
        return dict(row)

    @staticmethod
    def all():
        db = get_db()
        rows = db.execute("SELECT * FROM patients ORDER BY updated_at DESC").fetchall()
        db.close()
        return [Patient.dict_from_row(r) for r in rows]

    @staticmethod
    def get(patient_id):
        db = get_db()
        row = db.execute("SELECT * FROM patients WHERE id = ?", (patient_id,)).fetchone()
        db.close()
        return Patient.dict_from_row(row)

    @staticmethod
    def create(data):
        now = datetime.utcnow().isoformat()
        db = get_db()
        db.execute("""
            INSERT INTO patients (id, name, dob, age, gender, blood_group, mobile, address,
                                  last_diagnosis, last_visit_date, created_at, updated_at, is_synced)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)
        """, (
            data['id'], data['name'], data.get('dob', ''),
            data.get('age', 0), data.get('gender', 'Not Specified'),
            data.get('blood_group', 'Not Specified'),
            data.get('mobile', ''), data.get('address', ''),
            data.get('last_diagnosis', ''), data.get('last_visit_date', ''),
            now, now
        ))
        db.commit()
        db.close()
        return Patient.get(data['id'])

    @staticmethod
    def update(patient_id, data):
        now = datetime.utcnow().isoformat()
        allowed = ('name', 'dob', 'age', 'gender', 'blood_group', 'mobile',
                   'address', 'last_diagnosis', 'last_visit_date')
        fields = []
        values = []
        for k in allowed:
            if k in data:
                fields.append(f"{k} = ?")
                values.append(data[k])
        if not fields:
            return Patient.get(patient_id)
        fields.append("updated_at = ?")
        values.append(now)
        values.append(patient_id)
        db = get_db()
        db.execute(f"UPDATE patients SET {', '.join(fields)} WHERE id = ?", values)
        db.commit()
        db.close()
        return Patient.get(patient_id)

    @staticmethod
    def delete(patient_id):
        db = get_db()
        db.execute("DELETE FROM opd_records WHERE patient_id = ?", (patient_id,))
        db.execute("DELETE FROM patients WHERE id = ?", (patient_id,))
        db.commit()
        db.close()

    @staticmethod
    def upsert(data):
        existing = Patient.get(data['id'])
        if existing:
            return Patient.update(data['id'], data)
        return Patient.create(data)

    @staticmethod
    def updated_since(timestamp):
        db = get_db()
        rows = db.execute(
            "SELECT * FROM patients WHERE updated_at > ? ORDER BY updated_at",
            (timestamp,)
        ).fetchall()
        db.close()
        return [Patient.dict_from_row(r) for r in rows]
