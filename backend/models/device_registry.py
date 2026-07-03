from database import get_db
from datetime import datetime


class DeviceRegistry:
    TABLE = 'device_registry'

    @staticmethod
    def dict_from_row(row):
        if row is None:
            return None
        return dict(row)

    @staticmethod
    def get(device_id):
        db = get_db()
        row = db.execute(
            "SELECT * FROM device_registry WHERE device_id = %s", (device_id,)
        ).fetchone()
        db.close()
        return DeviceRegistry.dict_from_row(row)

    @staticmethod
    def get_by_clinic(clinic_id):
        db = get_db()
        rows = db.execute(
            "SELECT * FROM device_registry WHERE clinic_id = %s ORDER BY last_seen DESC",
            (clinic_id,)
        ).fetchall()
        db.close()
        return [DeviceRegistry.dict_from_row(r) for r in rows]

    @staticmethod
    def register(data):
        now = datetime.utcnow().isoformat()
        db = get_db()
        existing = db.execute(
            "SELECT id FROM device_registry WHERE device_id = %s",
            (data['device_id'],)
        ).fetchone()
        if existing:
            db.execute("""
                UPDATE device_registry
                SET device_name = %s, clinic_id = %s, fcm_token = %s,
                    app_version = %s, last_seen = %s, updated_at = %s
                WHERE device_id = %s
            """, (
                data.get('device_name', ''),
                data.get('clinic_id', ''),
                data.get('fcm_token', ''),
                data.get('app_version', ''),
                now, now,
                data['device_id']
            ))
            db.commit()
            db.close()
            return DeviceRegistry.get(data['device_id'])
        db.execute("""
            INSERT INTO device_registry
                (device_id, device_name, clinic_id, fcm_token, app_version,
                 last_seen, created_at, updated_at)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
        """, (
            data['device_id'], data.get('device_name', ''),
            data.get('clinic_id', ''), data.get('fcm_token', ''),
            data.get('app_version', ''), now, now, now
        ))
        db.commit()
        db.close()
        return DeviceRegistry.get(data['device_id'])

    @staticmethod
    def update_heartbeat(device_id):
        now = datetime.utcnow().isoformat()
        db = get_db()
        db.execute(
            "UPDATE device_registry SET last_seen = %s, updated_at = %s WHERE device_id = %s",
            (now, now, device_id)
        )
        db.commit()
        db.close()
