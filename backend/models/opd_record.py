from database import get_db
from datetime import datetime


class OPDRecord:
    TABLE = 'opd_visits'

    @staticmethod
    def dict_from_row(row):
        if row is None:
            return None
        return dict(row)

    @staticmethod
    def all(patient_id=None):
        db = get_db()
        if patient_id:
            rows = db.execute(
                "SELECT * FROM opd_visits WHERE patient_id = %s ORDER BY visit_datetime DESC",
                (patient_id,)
            ).fetchall()
        else:
            rows = db.execute("SELECT * FROM opd_visits ORDER BY visit_datetime DESC").fetchall()
        db.close()
        return [OPDRecord.dict_from_row(r) for r in rows]

    @staticmethod
    def get(record_id):
        db = get_db()
        row = db.execute("SELECT * FROM opd_visits WHERE id = %s", (record_id,)).fetchone()
        db.close()
        return OPDRecord.dict_from_row(row)

    @staticmethod
    def create(data):
        now = datetime.utcnow().isoformat()
        db = get_db()
        db.execute("""
            INSERT INTO opd_visits (id, patient_id, opd_type, symptoms, diagnosis, medicines,
                visit_datetime, clinical_notes, consultation_fee, medicine_fee, panchakarma_fee,
                total_fee, discount_value, discount_type, payment_mode, charge_type,
                followup_status, next_visit_date, panchakarma_notes, created_at)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
        """, (
            data['id'], data['patient_id'], data.get('opd_type', 'consultation'),
            data.get('symptoms', ''), data.get('diagnosis', ''),
            data.get('medicines', ''), data.get('visit_datetime', now),
            data.get('clinical_notes', ''), data.get('consultation_fee', '0'),
            data.get('medicine_fee', '0'), data.get('panchakarma_fee', '0'),
            data.get('total_fee', '0'), data.get('discount_value', '0'),
            data.get('discount_type', 'None'),
            data.get('payment_mode', ''), data.get('charge_type', ''),
            data.get('followup_status', ''),
            data.get('next_visit_date', ''),
            data.get('panchakarma_notes', ''),
            now
        ))
        db.commit()
        db.close()
        return OPDRecord.get(data['id'])

    @staticmethod
    def update(record_id, data):
        allowed = ('opd_type', 'symptoms', 'diagnosis', 'medicines', 'visit_datetime',
                   'clinical_notes', 'consultation_fee', 'medicine_fee',
                   'panchakarma_fee', 'total_fee', 'discount_value', 'discount_type',
                   'payment_mode', 'charge_type',
                   'followup_status', 'next_visit_date',
                   'panchakarma_notes')
        fields = []
        values = []
        for k in allowed:
            if k in data:
                fields.append(f"{k} = %s")
                values.append(data[k])
        if not fields:
            return OPDRecord.get(record_id)
        now = datetime.utcnow().isoformat()
        fields.append("updated_at = %s")
        values.append(now)
        values.append(record_id)
        db = get_db()
        db.execute(f"UPDATE opd_visits SET {', '.join(fields)} WHERE id = %s", values)
        db.commit()
        db.close()
        return OPDRecord.get(record_id)

    @staticmethod
    def delete(record_id):
        db = get_db()
        db.execute("DELETE FROM opd_visits WHERE id = %s", (record_id,))
        db.commit()
        db.close()

    @staticmethod
    def upsert(data):
        existing = OPDRecord.get(data['id'])
        if existing:
            return OPDRecord.update(data['id'], data)
        return OPDRecord.create(data)

    @staticmethod
    def updated_since(timestamp):
        db = get_db()
        rows = db.execute(
            "SELECT * FROM opd_visits WHERE COALESCE(updated_at, created_at) > %s ORDER BY COALESCE(updated_at, created_at)",
            (timestamp,)
        ).fetchall()
        db.close()
        return [OPDRecord.dict_from_row(r) for r in rows]
