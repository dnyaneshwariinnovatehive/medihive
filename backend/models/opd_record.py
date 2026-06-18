from database import get_db
from datetime import datetime


class OPDRecord:
    TABLE = 'opd_records'

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
                "SELECT * FROM opd_records WHERE patient_id = ? ORDER BY visit_date DESC",
                (patient_id,)
            ).fetchall()
        else:
            rows = db.execute("SELECT * FROM opd_records ORDER BY visit_date DESC").fetchall()
        db.close()
        return [OPDRecord.dict_from_row(r) for r in rows]

    @staticmethod
    def get(record_id):
        db = get_db()
        row = db.execute("SELECT * FROM opd_records WHERE id = ?", (record_id,)).fetchone()
        db.close()
        return OPDRecord.dict_from_row(row)

    @staticmethod
    def create(data):
        now = datetime.utcnow().isoformat()
        db = get_db()
        db.execute("""
            INSERT INTO opd_records (id, patient_id, type, symptoms, diagnosis, medicines,
                visit_date, clinical_notes, consultation_fee, medicine_fee, discount,
                payment_mode, charge_type, previous_visit_date, follow_up_reason,
                next_visit, blood_group, created_at, updated_at, is_synced)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)
        """, (
            data['id'], data['patient_id'], data.get('type', 'consultation'),
            data.get('symptoms', ''), data.get('diagnosis', ''),
            data.get('medicines', ''), data.get('visit_date', now),
            data.get('clinical_notes', ''), data.get('consultation_fee', '0'),
            data.get('medicine_fee', '0'), data.get('discount', '0'),
            data.get('payment_mode', ''), data.get('charge_type', ''),
            data.get('previous_visit_date', ''), data.get('follow_up_reason', ''),
            data.get('next_visit', ''), data.get('blood_group', ''),
            now, now
        ))
        db.commit()
        db.close()
        return OPDRecord.get(data['id'])

    @staticmethod
    def update(record_id, data):
        now = datetime.utcnow().isoformat()
        allowed = ('type', 'symptoms', 'diagnosis', 'medicines', 'visit_date',
                   'clinical_notes', 'consultation_fee', 'medicine_fee', 'discount',
                   'payment_mode', 'charge_type', 'previous_visit_date',
                   'follow_up_reason', 'next_visit', 'blood_group')
        fields = []
        values = []
        for k in allowed:
            if k in data:
                fields.append(f"{k} = ?")
                values.append(data[k])
        if not fields:
            return OPDRecord.get(record_id)
        fields.append("updated_at = ?")
        values.append(now)
        values.append(record_id)
        db = get_db()
        db.execute(f"UPDATE opd_records SET {', '.join(fields)} WHERE id = ?", values)
        db.commit()
        db.close()
        return OPDRecord.get(record_id)

    @staticmethod
    def delete(record_id):
        db = get_db()
        db.execute("DELETE FROM opd_records WHERE id = ?", (record_id,))
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
            "SELECT * FROM opd_records WHERE updated_at > ? ORDER BY updated_at",
            (timestamp,)
        ).fetchall()
        db.close()
        return [OPDRecord.dict_from_row(r) for r in rows]
