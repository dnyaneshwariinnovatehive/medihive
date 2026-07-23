from database import get_db
from datetime import datetime
from models.patient import parse_patient_id
from services.log_service import get_logger

logger = get_logger(__name__)


class OPDRecord:
    TABLE = 'opd_visits'

    @staticmethod
    def dict_from_row(row):
        if row is None:
            return None
        d = dict(row)
        d['db_id'] = row['id']
        if 'opd_id' in d:
            d['id'] = d['opd_id']
        if 'patient_id' in d and isinstance(d['patient_id'], int):
            d['patient_id'] = f"P{d['patient_id']:03d}"
        return d

    @staticmethod
    def all(patient_id=None):
        db = get_db()
        pid = parse_patient_id(patient_id)
        try:
            if pid:
                rows = db.execute(
                    "SELECT * FROM opd_visits WHERE patient_id = %s ORDER BY visit_datetime DESC",
                    (str(pid),)
                ).fetchall()
            else:
                rows = db.execute("SELECT * FROM opd_visits ORDER BY visit_datetime DESC").fetchall()
            return [OPDRecord.dict_from_row(r) for r in rows]
        finally:
            db.close()

    @staticmethod
    def get(record_id):
        db = get_db()
        try:
            if isinstance(record_id, int) or (isinstance(record_id, str) and record_id.isdigit()):
                row = db.execute("SELECT * FROM opd_visits WHERE id = %s", (str(record_id),)).fetchone()
            else:
                row = db.execute("SELECT * FROM opd_visits WHERE opd_id = %s", (str(record_id),)).fetchone()
            return OPDRecord.dict_from_row(row)
        finally:
            db.close()

    @staticmethod
    def get_by_opd_id(opd_id):
        return OPDRecord.get(opd_id)

    @staticmethod
    def create(data):
        pid = parse_patient_id(data['patient_id'])
        now = datetime.utcnow().isoformat()
        db = get_db()
        try:
            try:
                db.execute("""
                    INSERT INTO opd_visits (opd_id, patient_id, opd_type, symptoms, diagnosis, medicines,
                        visit_datetime, clinical_notes, consultation_fee, medicine_fee, panchakarma_fee,
                        total_fee, discount_value, discount_type, payment_mode, charge_type,
                        followup_status, next_visit_date, panchakarma_notes, created_at)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                """, (
                    data['id'], str(pid) if pid else None, data.get('opd_type', 'consultation'),
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
            except Exception as e:
                db.rollback()
                logger.warning("OPD create failed for opd_id=%s (%s), falling back to update", data['id'], e)
                try:
                    OPDRecord.update(data['id'], data)
                except Exception as e2:
                    logger.error("OPD fallback update also failed for opd_id=%s: %s", data['id'], e2)
        finally:
            db.close()
        return OPDRecord.get_by_opd_id(data['id'])

    @staticmethod
    def update(record_id, data):
        allowed = ('opd_type', 'symptoms', 'diagnosis', 'medicines', 'visit_datetime',
                   'clinical_notes', 'consultation_fee', 'medicine_fee',
                   'panchakarma_fee', 'total_fee', 'discount_value', 'discount_type',
                   'payment_mode', 'charge_type',
                   'followup_status', 'next_visit_date',
                   'panchakarma_notes', 'opd_id')
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

        if isinstance(record_id, int) or (isinstance(record_id, str) and record_id.isdigit()):
            where_clause = "WHERE id = %s"
            where_val = str(record_id)
        else:
            where_clause = "WHERE opd_id = %s"
            where_val = str(record_id)

        values.append(where_val)
        db = get_db()
        try:
            db.execute(f"UPDATE opd_visits SET {', '.join(fields)} {where_clause}", values)
            db.commit()
        finally:
            db.close()
        return OPDRecord.get(record_id)

    @staticmethod
    def delete(record_id):
        db = get_db()
        try:
            if isinstance(record_id, int) or (isinstance(record_id, str) and record_id.isdigit()):
                db.execute("DELETE FROM opd_visits WHERE id = %s", (str(record_id),))
            else:
                db.execute("DELETE FROM opd_visits WHERE opd_id = %s", (str(record_id),))
            db.commit()
        finally:
            db.close()

    @staticmethod
    def upsert(data):
        try:
            existing = OPDRecord.get(data['id'])
        except Exception as e:
            logger.warning("OPD upsert get failed for id=%s: %s", data['id'], e)
            existing = None
        if existing:
            try:
                return OPDRecord.update(data['id'], data)
            except Exception as e:
                logger.warning("OPD upsert update failed for id=%s: %s, falling back to create", data['id'], e)
        try:
            return OPDRecord.create(data)
        except Exception as e:
            logger.error("OPD upsert create failed for id=%s: %s", data['id'], e)
            raise

    @staticmethod
    def updated_since(timestamp):
        db = get_db()
        try:
            rows = db.execute(
                "SELECT * FROM opd_visits WHERE COALESCE(updated_at, created_at) > %s ORDER BY COALESCE(updated_at, created_at)",
                (timestamp,)
            ).fetchall()
            return [OPDRecord.dict_from_row(r) for r in rows]
        finally:
            db.close()
