from database import get_db
from datetime import datetime


class DeletedEntity:

    @staticmethod
    def record(entity_type, entity_id, user_id='', clinic_id=''):
        now = datetime.utcnow().isoformat()
        db = get_db()
        try:
            db.execute(
                "INSERT INTO deleted_entities (entity_type, entity_id, deleted_at, user_id, clinic_id) "
                "VALUES (%s, %s, %s, %s, %s)",
                (entity_type, entity_id, now, user_id, clinic_id)
            )
            db.commit()
        finally:
            db.close()

    @staticmethod
    def since(timestamp, user_id=None, clinic_id=None):
        db = get_db()
        if clinic_id:
            rows = db.execute(
                "SELECT entity_type, entity_id, deleted_at FROM deleted_entities "
                "WHERE deleted_at > %s AND clinic_id = %s "
                "ORDER BY deleted_at",
                (timestamp, clinic_id)
            ).fetchall()
        elif user_id:
            rows = db.execute(
                "SELECT entity_type, entity_id, deleted_at FROM deleted_entities "
                "WHERE deleted_at > %s AND (user_id = %s OR user_id = '') "
                "ORDER BY deleted_at",
                (timestamp, user_id)
            ).fetchall()
        else:
            rows = db.execute(
                "SELECT entity_type, entity_id, deleted_at FROM deleted_entities "
                "WHERE deleted_at > %s ORDER BY deleted_at",
                (timestamp,)
            ).fetchall()
        db.close()
        return [dict(r) for r in rows]
