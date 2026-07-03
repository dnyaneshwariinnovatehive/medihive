from database import get_db
from datetime import datetime


class Clinic:
    TABLE = 'clinics'

    @staticmethod
    def dict_from_row(row):
        if row is None:
            return None
        return dict(row)

    @staticmethod
    def get(clinic_id):
        db = get_db()
        row = db.execute(
            "SELECT * FROM clinics WHERE id = %s", (clinic_id,)
        ).fetchone()
        db.close()
        return Clinic.dict_from_row(row)

    @staticmethod
    def get_by_email(email):
        db = get_db()
        row = db.execute(
            "SELECT * FROM clinics WHERE email = %s", (email,)
        ).fetchone()
        db.close()
        return Clinic.dict_from_row(row)

    @staticmethod
    def create(data):
        now = datetime.utcnow().isoformat()
        db = get_db()
        db.execute("""
            INSERT INTO clinics (id, name, email, phone, address, created_at, updated_at)
            VALUES (%s, %s, %s, %s, %s, %s, %s)
        """, (
            data['id'], data['name'],
            data.get('email', ''), data.get('phone', ''),
            data.get('address', ''), now, now
        ))
        db.commit()
        db.close()
        return Clinic.get(data['id'])

    @staticmethod
    def update(clinic_id, data):
        now = datetime.utcnow().isoformat()
        allowed = ('name', 'email', 'phone', 'address')
        fields = []
        values = []
        for k in allowed:
            if k in data:
                fields.append(f"{k} = %s")
                values.append(data[k])
        if not fields:
            return Clinic.get(clinic_id)
        fields.append("updated_at = %s")
        values.append(now)
        values.append(clinic_id)
        db = get_db()
        db.execute(f"UPDATE clinics SET {', '.join(fields)} WHERE id = %s", values)
        db.commit()
        db.close()
        return Clinic.get(clinic_id)

    @staticmethod
    def assign_next_id():
        db = get_db()
        result = db.execute(
            "SELECT id FROM clinics WHERE id LIKE 'CLI%' ORDER BY id DESC LIMIT 1"
        ).fetchone()
        db.close()
        if result is None:
            return 'CLI001'
        last_id = result['id']
        num = int(last_id[3:]) + 1
        return f'CLI{num:03d}'
