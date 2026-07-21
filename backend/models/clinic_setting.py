from database import get_db
from datetime import datetime


class ClinicSetting:
    TABLE = 'clinic_settings'

    @staticmethod
    def dict_from_row(row):
        if row is None:
            return None
        return dict(row)

    @staticmethod
    def get_first():
        db = get_db()
        row = db.execute("SELECT * FROM clinic_settings ORDER BY id ASC LIMIT 1").fetchone()
        db.close()
        return ClinicSetting.dict_from_row(row)

    @staticmethod
    def get(setting_id):
        db = get_db()
        row = db.execute("SELECT * FROM clinic_settings WHERE id = %s", (setting_id,)).fetchone()
        db.close()
        return ClinicSetting.dict_from_row(row)

    @staticmethod
    def create(data):
        now = datetime.utcnow().isoformat()
        db = get_db()
        db.execute("""
            INSERT INTO clinic_settings (
                doctor_name, doctor_email, doctor_contact, doctor_license_no,
                doctor_photo_path, clinic_name, clinic_logo_path, clinic_address,
                clinic_phone, website, operating_hours, smtp_email, smtp_password,
                smtp_server, smtp_port, created_at, updated_at
            ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
        """, (
            data.get('doctor_name', ''),
            data.get('doctor_email', ''),
            data.get('doctor_contact', ''),
            data.get('doctor_license_no', ''),
            data.get('doctor_photo_path', ''),
            data.get('clinic_name', ''),
            data.get('clinic_logo_path', ''),
            data.get('clinic_address', ''),
            data.get('clinic_phone', ''),
            data.get('website', ''),
            data.get('operating_hours', ''),
            data.get('smtp_email', ''),
            data.get('smtp_password', ''),
            data.get('smtp_server', ''),
            data.get('smtp_port', ''),
            now,
            now
        ))
        db.commit()
        db.close()
        return ClinicSetting.get_first()

    @staticmethod
    def update(setting_id, data):
        allowed = ('doctor_name', 'doctor_email', 'doctor_contact', 'doctor_license_no',
                   'doctor_photo_path', 'clinic_name', 'clinic_logo_path', 'clinic_address',
                   'clinic_phone', 'website', 'operating_hours', 'smtp_email', 'smtp_password',
                   'smtp_server', 'smtp_port')
        fields = []
        values = []
        for k in allowed:
            if k in data:
                fields.append(f"{k} = %s")
                values.append(data[k])
        if not fields:
            return ClinicSetting.get(setting_id)
        now = datetime.utcnow().isoformat()
        fields.append("updated_at = %s")
        values.append(now)
        values.append(setting_id)
        db = get_db()
        db.execute(f"UPDATE clinic_settings SET {', '.join(fields)} WHERE id = %s", values)
        db.commit()
        db.close()
        return ClinicSetting.get(setting_id)

    @staticmethod
    def upsert(data):
        existing = ClinicSetting.get_first()
        if existing:
            return ClinicSetting.update(existing['id'], data)
        return ClinicSetting.create(data)

    @staticmethod
    def updated_since(timestamp):
        db = get_db()
        rows = db.execute(
            "SELECT * FROM clinic_settings WHERE COALESCE(updated_at, created_at) > %s ORDER BY COALESCE(updated_at, created_at)",
            (timestamp,)
        ).fetchall()
        db.close()
        return [ClinicSetting.dict_from_row(r) for r in rows]
