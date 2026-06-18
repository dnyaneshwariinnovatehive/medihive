from database import get_db
from datetime import datetime


class Appointment:
    TABLE = 'appointments'

    @staticmethod
    def dict_from_row(row):
        if row is None:
            return None
        return dict(row)

    @staticmethod
    def all(date=None):
        db = get_db()
        if date:
            rows = db.execute(
                "SELECT * FROM appointments WHERE date(date_time) = ? ORDER BY date_time",
                (date,)
            ).fetchall()
        else:
            rows = db.execute("SELECT * FROM appointments ORDER BY date_time DESC").fetchall()
        db.close()
        return [Appointment.dict_from_row(r) for r in rows]

    @staticmethod
    def get(appt_id):
        db = get_db()
        row = db.execute("SELECT * FROM appointments WHERE id = ?", (appt_id,)).fetchone()
        db.close()
        return Appointment.dict_from_row(row)

    @staticmethod
    def create(data):
        now = datetime.utcnow().isoformat()
        db = get_db()
        db.execute("""
            INSERT INTO appointments (id, patient_id, patient_name, date_time, notes,
                                      created_at, updated_at, is_synced)
            VALUES (?, ?, ?, ?, ?, ?, ?, 0)
        """, (
            data['id'], data.get('patient_id', ''),
            data.get('patient_name', ''), data['date_time'],
            data.get('notes', ''), now, now
        ))
        db.commit()
        db.close()
        return Appointment.get(data['id'])

    @staticmethod
    def update(appt_id, data):
        now = datetime.utcnow().isoformat()
        allowed = ('patient_id', 'patient_name', 'date_time', 'notes')
        fields = []
        values = []
        for k in allowed:
            if k in data:
                fields.append(f"{k} = ?")
                values.append(data[k])
        if not fields:
            return Appointment.get(appt_id)
        fields.append("updated_at = ?")
        values.append(now)
        values.append(appt_id)
        db = get_db()
        db.execute(f"UPDATE appointments SET {', '.join(fields)} WHERE id = ?", values)
        db.commit()
        db.close()
        return Appointment.get(appt_id)

    @staticmethod
    def delete(appt_id):
        db = get_db()
        db.execute("DELETE FROM appointments WHERE id = ?", (appt_id,))
        db.commit()
        db.close()

    @staticmethod
    def upsert(data):
        existing = Appointment.get(data['id'])
        if existing:
            return Appointment.update(data['id'], data)
        return Appointment.create(data)

    @staticmethod
    def updated_since(timestamp):
        db = get_db()
        rows = db.execute(
            "SELECT * FROM appointments WHERE updated_at > ? ORDER BY updated_at",
            (timestamp,)
        ).fetchall()
        db.close()
        return [Appointment.dict_from_row(r) for r in rows]
