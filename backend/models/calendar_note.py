from database import get_db
from datetime import datetime


class CalendarNote:
    TABLE = 'calendar_notes'

    @staticmethod
    def dict_from_row(row):
        if row is None:
            return None
        return dict(row)

    @staticmethod
    def all():
        db = get_db()
        rows = db.execute("SELECT * FROM calendar_notes ORDER BY note_date DESC").fetchall()
        db.close()
        return [CalendarNote.dict_from_row(r) for r in rows]

    @staticmethod
    def get(note_id):
        db = get_db()
        row = db.execute("SELECT * FROM calendar_notes WHERE id = %s", (note_id,)).fetchone()
        db.close()
        return CalendarNote.dict_from_row(row)

    @staticmethod
    def get_by_date(note_date):
        db = get_db()
        row = db.execute("SELECT * FROM calendar_notes WHERE note_date = %s", (note_date,)).fetchone()
        db.close()
        return CalendarNote.dict_from_row(row)

    @staticmethod
    def create(data):
        now = datetime.utcnow().isoformat()
        db = get_db()
        db.execute("""
            INSERT INTO calendar_notes (note_date, note_text, created_at, updated_at)
            VALUES (%s, %s, %s, %s)
            ON CONFLICT (note_date) DO UPDATE SET
                note_text = EXCLUDED.note_text,
                updated_at = EXCLUDED.updated_at
        """, (
            data['note_date'],
            data.get('note_text', ''),
            now,
            now
        ))
        db.commit()
        db.close()
        return CalendarNote.get_by_date(data['note_date'])

    @staticmethod
    def update(note_id, data):
        allowed = ('note_text',)
        fields = []
        values = []
        for k in allowed:
            if k in data:
                fields.append(f"{k} = %s")
                values.append(data[k])
        if not fields:
            return CalendarNote.get(note_id)
        now = datetime.utcnow().isoformat()
        fields.append("updated_at = %s")
        values.append(now)
        values.append(note_id)
        db = get_db()
        db.execute(f"UPDATE calendar_notes SET {', '.join(fields)} WHERE id = %s", values)
        db.commit()
        db.close()
        return CalendarNote.get(note_id)

    @staticmethod
    def upsert(data):
        existing = CalendarNote.get_by_date(data.get('note_date', ''))
        if existing:
            return CalendarNote.update(existing['id'], data)
        return CalendarNote.create(data)

    @staticmethod
    def updated_since(timestamp):
        db = get_db()
        rows = db.execute(
            "SELECT * FROM calendar_notes WHERE COALESCE(updated_at, created_at) > %s ORDER BY COALESCE(updated_at, created_at)",
            (timestamp,)
        ).fetchall()
        db.close()
        return [CalendarNote.dict_from_row(r) for r in rows]
