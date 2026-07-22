from database import get_db
from datetime import datetime


class PatientImage:
    TABLE = 'patient_images'

    @staticmethod
    def dict_from_row(row):
        if row is None:
            return None
        return dict(row)

    @staticmethod
    def all(patient_id=None, opd_visit_id=None):
        db = get_db()
        query = "SELECT * FROM patient_images"
        params = []
        conditions = []
        if patient_id:
            conditions.append("patient_id = %s")
            params.append(patient_id)
        if opd_visit_id:
            conditions.append("opd_visit_id = %s")
            params.append(opd_visit_id)
        if conditions:
            query += " WHERE " + " AND ".join(conditions)
        query += " ORDER BY created_at DESC"
        rows = db.execute(query, tuple(params)).fetchall()
        db.close()
        return [PatientImage.dict_from_row(r) for r in rows]

    @staticmethod
    def updated_since(timestamp):
        db = get_db()
        rows = db.execute(
            "SELECT * FROM patient_images WHERE COALESCE(created_at, uploaded_at) > %s ORDER BY COALESCE(created_at, uploaded_at)",
            (timestamp,)
        ).fetchall()
        db.close()
        return [PatientImage.dict_from_row(r) for r in rows]

    @staticmethod
    def create(data):
        now = datetime.utcnow().isoformat()
        db = get_db()
        db.execute("""
            INSERT INTO patient_images (patient_id, opd_visit_id, file_path, image_type, sync_status, uploaded_at, drive_url, created_at)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
        """, (
            data.get('patient_id'),
            data.get('opd_visit_id'),
            data.get('file_path', ''),
            data.get('image_type', 'prescription'),
            data.get('sync_status', 'synced'),
            data.get('uploaded_at', now),
            data.get('drive_url', ''),
            data.get('created_at', now),
        ))
        db.commit()
        db.close()

    @staticmethod
    def save_drive_urls(opd_visit_id, patient_id, drive_urls):
        if not drive_urls:
            return
        now = datetime.utcnow().isoformat()
        db = get_db()
        for url in drive_urls:
            db.execute("""
                INSERT INTO patient_images (patient_id, opd_visit_id, file_path, image_type, sync_status, uploaded_at, drive_url, created_at)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
            """, (
                patient_id,
                opd_visit_id,
                url,
                'opd_attachment',
                'synced',
                now,
                url,
                now,
            ))
        db.commit()
        db.close()
