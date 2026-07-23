from database import get_db
from datetime import datetime
from models.patient import parse_patient_id


class PatientImage:
    TABLE = 'patient_images'

    @staticmethod
    def dict_from_row(row):
        if row is None:
            return None
        d = dict(row)
        if 'patient_id' in d and isinstance(d['patient_id'], int):
            d['patient_id'] = f"P{d['patient_id']:03d}"
        if 'opd_visit_id' in d and isinstance(d['opd_visit_id'], int):
            from models.opd_record import OPDRecord
            opd = OPDRecord.get(d['opd_visit_id'])
            d['opd_visit_id'] = opd['id'] if opd else None
        return d

    @staticmethod
    def all(patient_id=None, opd_visit_id=None):
        pid = parse_patient_id(patient_id)
        
        # Resolve opd_visit_id to integer database id
        opd_int_id = None
        if opd_visit_id:
            from models.opd_record import OPDRecord
            opd = OPDRecord.get_by_opd_id(opd_visit_id)
            opd_int_id = opd['db_id'] if opd else None
            
        db = get_db()
        query = "SELECT * FROM patient_images"
        params = []
        conditions = []
        if pid:
            conditions.append("patient_id = %s")
            params.append(str(pid))
        if opd_int_id:
            conditions.append("opd_visit_id = %s")
            params.append(str(opd_int_id))
        if conditions:
            query += " WHERE " + " AND ".join(conditions)
        query += " ORDER BY created_at DESC"
        try:
            rows = db.execute(query, tuple(params)).fetchall()
            return [PatientImage.dict_from_row(r) for r in rows]
        finally:
            db.close()

    @staticmethod
    def updated_since(timestamp):
        db = get_db()
        try:
            rows = db.execute(
                "SELECT * FROM patient_images WHERE COALESCE(created_at, uploaded_at) > %s ORDER BY COALESCE(created_at, uploaded_at)",
                (timestamp,)
            ).fetchall()
            return [PatientImage.dict_from_row(r) for r in rows]
        finally:
            db.close()

    @staticmethod
    def create(data):
        pid = parse_patient_id(data.get('patient_id'))
        
        # Resolve opd_visit_id string to database integer
        from models.opd_record import OPDRecord
        opd = OPDRecord.get_by_opd_id(data.get('opd_visit_id'))
        opd_int_id = opd['db_id'] if opd else None
        
        now = datetime.utcnow().isoformat()
        db = get_db()
        try:
            db.execute("""
                INSERT INTO patient_images (patient_id, opd_visit_id, file_path, image_type, sync_status, uploaded_at, drive_url, created_at)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
            """, (
                str(pid) if pid else None,
                str(opd_int_id) if opd_int_id else None,
                data.get('file_path', ''),
                data.get('image_type', 'prescription'),
                data.get('sync_status', 'synced'),
                data.get('uploaded_at', now),
                data.get('drive_url', ''),
                data.get('created_at', now),
            ))
            db.commit()
        finally:
            db.close()

    @staticmethod
    def save_drive_urls(opd_visit_id, patient_id, drive_urls):
        if not drive_urls:
            return
        pid = parse_patient_id(patient_id)
        
        # Resolve opd_visit_id string to database integer
        from models.opd_record import OPDRecord
        opd = OPDRecord.get_by_opd_id(opd_visit_id)
        opd_int_id = opd['db_id'] if opd else None
        
        now = datetime.utcnow().isoformat()
        db = get_db()
        try:
            for url in drive_urls:
                db.execute("""
                    INSERT INTO patient_images (patient_id, opd_visit_id, file_path, image_type, sync_status, uploaded_at, drive_url, created_at)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
                """, (
                    str(pid) if pid else None,
                    str(opd_int_id) if opd_int_id else None,
                    url,
                    'opd_attachment',
                    'synced',
                    now,
                    url,
                    now,
                ))
            db.commit()
        finally:
            db.close()
