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
        row = db.execute("SELECT * FROM patients WHERE id = %s", (patient_id,)).fetchone()
        db.close()
        return Patient.dict_from_row(row)

    @staticmethod
    def create(data):
        now = datetime.utcnow().isoformat()
        db = get_db()
        db.execute("""
            INSERT INTO patients (id, full_name, dob, age, gender, blood_group, mobile_number, alternate_mobile, address,
                                  last_diagnosis, last_visit_date, created_at, updated_at,
                                  is_synced, user_id, clinic_id)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, 0, %s, %s)
        """, (
            data['id'], data['full_name'], data.get('dob', ''),
            data.get('age', 0), data.get('gender', 'Not Specified'),
            data.get('blood_group', 'Not Specified'),
            data.get('mobile_number', ''), data.get('alternate_mobile', ''),
            data.get('address', ''),
            data.get('last_diagnosis', ''), data.get('last_visit_date', ''),
            now, now,
            data.get('user_id', ''),
            data.get('clinic_id', '')
        ))
        db.commit()
        db.close()
        return Patient.get(data['id'])

    @staticmethod
    def update(patient_id, data):
        now = datetime.utcnow().isoformat()
        allowed = ('full_name', 'dob', 'age', 'gender', 'blood_group', 'mobile_number',
                   'alternate_mobile', 'address', 'last_diagnosis', 'last_visit_date',
                   'user_id', 'clinic_id')
        fields = []
        values = []
        for k in allowed:
            if k in data:
                fields.append(f"{k} = %s")
                values.append(data[k])
        if not fields:
            return Patient.get(patient_id)
        fields.append("updated_at = %s")
        values.append(now)
        values.append(patient_id)
        db = get_db()
        db.execute(f"UPDATE patients SET {', '.join(fields)} WHERE id = %s", values)
        db.commit()
        db.close()
        return Patient.get(patient_id)

    @staticmethod
    def assign_next_id():
        """Generate the next sequential patient ID (e.g., P001, P002, ...)."""
        db = get_db()
        try:
            result = db.execute(
                "SELECT COALESCE(MAX(CAST(SUBSTR(TRIM(id), 2) AS INTEGER)), 0) + 1 AS nid "
                "FROM patients WHERE id LIKE 'P%'"
            ).fetchone()
            next_num = result['nid']
            return f'P{next_num:03d}'
        finally:
            db.close()

    @staticmethod
    def delete(patient_id):
        from models.deleted_entity import DeletedEntity
        from models.opd_record import OPDRecord
        db = get_db()
        opd_rows = db.execute(
            "SELECT id FROM opd_visits WHERE patient_id = %s", (patient_id,)
        ).fetchall()
        db.close()
        for row in opd_rows:
            OPDRecord.delete(row['id'])
        DeletedEntity.record('patient', patient_id)
        db = get_db()
        db.execute("DELETE FROM patients WHERE id = %s", (patient_id,))
        db.commit()
        db.close()

    @staticmethod
    def upsert(data):
        existing = Patient.get(data['id'])
        if existing:
            return Patient.update(data['id'], data)
        return Patient.create(data)

    @staticmethod
    def by_clinic(clinic_id):
        db = get_db()
        rows = db.execute(
            "SELECT * FROM patients WHERE clinic_id = %s ORDER BY updated_at DESC",
            (clinic_id,)
        ).fetchall()
        db.close()
        return [Patient.dict_from_row(r) for r in rows]

    @staticmethod
    def updated_since(timestamp, user_id=None, clinic_id=None):
        db = get_db()
        if clinic_id:
            rows = db.execute(
                "SELECT * FROM patients WHERE updated_at > %s AND clinic_id = %s ORDER BY updated_at",
                (timestamp, clinic_id)
            ).fetchall()
        elif user_id:
            rows = db.execute(
                "SELECT * FROM patients WHERE updated_at > %s AND (user_id = %s OR user_id = '') ORDER BY updated_at",
                (timestamp, user_id)
            ).fetchall()
        else:
            rows = db.execute(
                "SELECT * FROM patients WHERE updated_at > %s ORDER BY updated_at",
                (timestamp,)
            ).fetchall()
        db.close()
        return [Patient.dict_from_row(r) for r in rows]
