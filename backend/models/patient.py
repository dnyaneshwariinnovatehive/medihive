from database import get_db
from datetime import datetime
from services.log_service import get_logger

logger = get_logger(__name__)


def parse_patient_id(pid):
    if pid is None:
        return None
    if isinstance(pid, int):
        return pid
    if isinstance(pid, str):
        # Remove any leading non-digits (like 'P' or 'P0')
        digits = ''.join(c for c in pid if c.isdigit())
        if digits:
            return int(digits)
    return None


class Patient:
    TABLE = 'patients'

    @staticmethod
    def dict_from_row(row):
        if row is None:
            return None
        d = dict(row)
        if 'id' in d:
            d['db_id'] = d['id']
            if isinstance(d['id'], int):
                d['id'] = f"P{d['id']:03d}"
        return d

    @staticmethod
    def all():
        db = get_db()
        try:
            rows = db.execute("SELECT * FROM patients ORDER BY created_at DESC").fetchall()
            return [Patient.dict_from_row(r) for r in rows]
        finally:
            db.close()

    @staticmethod
    def get(patient_id):
        pid = parse_patient_id(patient_id)
        if pid is None:
            return None
        db = get_db()
        try:
            row = db.execute("SELECT * FROM patients WHERE id = %s", (str(pid),)).fetchone()
            return Patient.dict_from_row(row)
        finally:
            db.close()

    @staticmethod
    def create(data):
        pid = parse_patient_id(data['id'])
        now = datetime.utcnow().isoformat()
        db = get_db()
        try:
            try:
                db.execute("""
                    INSERT INTO patients (id, full_name, dob, age, gender, blood_group, mobile_number, alternate_mobile, address,
                                          created_at)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                """, (
                    str(pid), data['full_name'], data.get('dob', ''),
                    data.get('age', 0), data.get('gender', 'Not Specified'),
                    data.get('blood_group', 'Not Specified'),
                    data.get('mobile_number', ''), data.get('alternate_mobile', ''),
                    data.get('address', ''),
                    now
                ))
                db.commit()
                return Patient.get(pid)
            except Exception as e:
                db.rollback()
                logger.warning("Patient create with explicit id=%s failed (%s), retrying with auto-generated id", pid, e)
                db.execute("""
                    INSERT INTO patients (full_name, dob, age, gender, blood_group, mobile_number, alternate_mobile, address,
                                          created_at)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
                """, (
                    data['full_name'], data.get('dob', ''),
                    data.get('age', 0), data.get('gender', 'Not Specified'),
                    data.get('blood_group', 'Not Specified'),
                    data.get('mobile_number', ''), data.get('alternate_mobile', ''),
                    data.get('address', ''),
                    now
                ))
                db.commit()
                row = db.execute(
                    "SELECT * FROM patients WHERE full_name = %s AND created_at = %s ORDER BY id DESC LIMIT 1",
                    (data['full_name'], now)
                ).fetchone()
                return Patient.dict_from_row(row) if row else None
        finally:
            db.close()

    @staticmethod
    def update(patient_id, data):
        pid = parse_patient_id(patient_id)
        if pid is None:
            return None
        allowed = ('full_name', 'dob', 'age', 'gender', 'blood_group', 'mobile_number',
                   'alternate_mobile', 'address')
        fields = []
        values = []
        for k in allowed:
            if k in data:
                fields.append(f"{k} = %s")
                values.append(data[k])
        if not fields:
            return Patient.get(pid)
        now = datetime.utcnow().isoformat()
        fields.append("updated_at = %s")
        values.append(now)
        values.append(str(pid))
        db = get_db()
        try:
            db.execute(f"UPDATE patients SET {', '.join(fields)} WHERE id = %s", values)
            db.commit()
            return Patient.get(pid)
        finally:
            db.close()

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
        pid = parse_patient_id(patient_id)
        if pid is None:
            return
        from models.opd_record import OPDRecord
        db = get_db()
        try:
            opd_rows = db.execute(
                "SELECT id FROM opd_visits WHERE patient_id = %s", (str(pid),)
            ).fetchall()
        finally:
            db.close()

        for row in opd_rows:
            OPDRecord.delete(row['id'])

        db = get_db()
        try:
            db.execute("DELETE FROM patients WHERE id = %s", (str(pid),))
            db.commit()
        finally:
            db.close()

    @staticmethod
    def upsert(data):
        existing = Patient.get(data['id'])
        if existing:
            return Patient.update(data['id'], data)
        # Also try to find by name+mobile to avoid duplicate patients
        row = None
        db = get_db()
        try:
            row = db.execute(
                "SELECT * FROM patients WHERE full_name = %s AND mobile_number = %s LIMIT 1",
                (data.get('full_name', ''), data.get('mobile_number', ''))
            ).fetchone()
        except Exception as e:
            logger.warning("Patient upsert name+mobile lookup failed: %s", e)
        finally:
            db.close()

        if row:
            existing = Patient.dict_from_row(row)
            logger.info("Patient upsert: found existing patient by name+mobile, id=%s", existing['id'])
            return Patient.update(existing['id'], data)

        return Patient.create(data)

    @staticmethod
    def updated_since(timestamp):
        db = get_db()
        try:
            rows = db.execute(
                "SELECT * FROM patients WHERE COALESCE(updated_at, created_at) > %s ORDER BY COALESCE(updated_at, created_at)",
                (timestamp,)
            ).fetchall()
            return [Patient.dict_from_row(r) for r in rows]
        finally:
            db.close()
