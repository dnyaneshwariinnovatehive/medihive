from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required, get_jwt_identity
from models.patient import Patient
from models.opd_record import OPDRecord
from models.appointment import Appointment
from models.deleted_entity import DeletedEntity
from database import get_db
from datetime import datetime
from pathlib import Path
from config import IMAGE_STORAGE_PATH, IS_CLOUD
from desktop_google.drive_service import upload_images_to_drive, check_existing_drive_files, upload_image_fileobj_to_drive
from config import GOOGLE_SHEET_ID
from desktop_google.sheets_service import (
    upsert_opd_row_in_sheet,
    update_opd_row_in_sheet,
    clear_opd_sheet_data,
)
from services.log_service import get_logger
from routes.opd import save_images_locally, build_sheet_row_data, _ImageRecord

logger = get_logger(__name__)

sync_bp = Blueprint('sync', __name__)


def _sync_opd_to_sheets(opd, image_links=None):
    """
    Append/upsert (Stage 1) or update (Stage 2) OPD row in Google Sheets.
    Raises RuntimeError if the sheet is not accessible — no new sheet is created.
    """
    patient = Patient.get(opd.get('patient_id'))
    if not patient:
        logger.warning(
            "Patient %s not found, creating placeholder for sheet sync for OPD %s",
            opd.get('patient_id'), opd['id'],
        )
        now = datetime.utcnow().isoformat()
        db = get_db()
        db.execute("""
            INSERT INTO patients
                (id, name, mobile, gender, created_at, updated_at, is_synced)
            VALUES (%s, %s, %s, %s, %s, %s, 0)
            ON CONFLICT DO NOTHING
        """, (
            opd.get('patient_id'), 'Unknown (Auto-created)',
            '', 'Not Specified', now, now,
        ))
        db.commit()
        db.close()
        patient = Patient.get(opd.get('patient_id'))
        if not patient:
            logger.error("Could not create placeholder patient %s", opd.get('patient_id'))
            return
    row_data = build_sheet_row_data(opd, patient, image_links or [])
    if image_links:
        update_opd_row_in_sheet(opd['id'], row_data)
    else:
        upsert_opd_row_in_sheet(opd['id'], row_data)


@sync_bp.route('/pull', methods=['POST'])
@jwt_required()
def pull():
    """
    Client sends its last_sync timestamp.
    Server returns all records updated after that timestamp for this user.
    """
    user_id = get_jwt_identity()
    data = request.get_json() or {}
    last_sync = data.get('last_sync', '2000-01-01T00:00:00')

    patients = Patient.updated_since(last_sync, user_id=user_id)
    opd_records = OPDRecord.updated_since(last_sync, user_id=user_id)
    appointments = Appointment.updated_since(last_sync, user_id=user_id)
    deleted_entities = DeletedEntity.since(last_sync, user_id=user_id)

    db = get_db()
    now = datetime.utcnow().isoformat()
    existing = db.execute(
        "SELECT id FROM last_sync WHERE user_id = %s", (user_id,)
    ).fetchone()
    if existing:
        db.execute(
            "UPDATE last_sync SET last_sync = %s, updated_at = %s WHERE user_id = %s",
            (last_sync, now, user_id)
        )
    else:
        db.execute(
            "INSERT INTO last_sync (user_id, last_sync, created_at, updated_at) VALUES (%s, %s, %s, %s)",
            (user_id, last_sync, now, now)
        )
    db.commit()
    db.close()

    return jsonify({
        'patients': patients,
        'opd_records': opd_records,
        'appointments': appointments,
        'deleted_entities': deleted_entities,
        'server_time': datetime.utcnow().isoformat(),
    }), 200


@sync_bp.route('/push', methods=['POST'])
@jwt_required()
def push():
    """
    Stage 1: Client sends local changes. Server upserts them,
    then immediately syncs each OPD to Google Sheets (no images yet).
    """
    user_id = get_jwt_identity()
    data = request.get_json() or {}
    logger.info(
        "PUSH request from user=%s ip=%s patients=%d opd_records=%d appointments=%d",
        user_id, request.remote_addr,
        len(data.get('patients', [])),
        len(data.get('opd_records', [])),
        len(data.get('appointments', [])),
    )
    if data.get('opd_records'):
        for r in data['opd_records']:
            logger.info("PUSH OPD: id=%s patient_id=%s visit_date=%s",
                        r.get('id'), r.get('patient_id'), r.get('visit_date'))

    results = {'patients': [], 'opd_records': [], 'appointments': []}
    temp_id_map = {}

    for p in data.get('patients', []):
        p['user_id'] = user_id
        old_id = p.get('id', '')
        is_temp = old_id.startswith('TEMP_')
        if is_temp:
            p['id'] = Patient.assign_next_id()
            temp_id_map[old_id] = p['id']
        patient = Patient.upsert(p)
        results['patients'].append(patient)

    # Re-sync all existing OPD records for this patient so that
    # patient columns (name, mobile, blood group, address, etc.)
    # are updated in Google Sheets immediately.
    re_synced_opds = 0
    for p in data.get('patients', []):
        pat_id = p.get('id', '')
        if pat_id and not pat_id.startswith('TEMP_'):
            for opd in OPDRecord.all(patient_id=pat_id):
                try:
                    _sync_opd_to_sheets(opd)
                    re_synced_opds += 1
                except Exception as e:
                    logger.warning(
                        "Patient-edit re-sync failed for OPD %s: %s",
                        opd['id'], e,
                    )
    if re_synced_opds:
        logger.info(
            "Re-synced %d OPD records to sheets after patient edits",
            re_synced_opds,
        )

    sheet_errors = []
    for r in data.get('opd_records', []):
        r['user_id'] = user_id
        pat_id = r.get('patient_id', '')
        if pat_id in temp_id_map:
            r['patient_id'] = temp_id_map[pat_id]
        result = OPDRecord.upsert(r)
        results['opd_records'].append(result)
        try:
            _sync_opd_to_sheets(r)
        except RuntimeError as e:
            msg = f"Sheet not updated for OPD {r.get('id')}: {e}"
            logger.error(msg)
            sheet_errors.append(msg)
        except Exception as e:
            msg = f"Sheet sync failed for OPD {r.get('id')}: {e}"
            logger.error(msg)
            sheet_errors.append(msg)

    deleted_patients_confirmed = []
    deleted_opd_confirmed = []
    deleted_appts_confirmed = []
    for entry in data.get('deleted_entities', []):
        etype = entry.get('entity_type')
        eid = entry.get('entity_id')
        try:
            if etype == 'patient':
                Patient.delete(eid)
                deleted_patients_confirmed.append(eid)
            elif etype == 'opd_visit':
                OPDRecord.delete(eid)
                deleted_opd_confirmed.append(eid)
            elif etype == 'appointment':
                Appointment.delete(eid)
                deleted_appts_confirmed.append(eid)
        except Exception as exc:
            logger.warning("Delete sync failed for %s %s: %s", etype, eid, exc)

    for a in data.get('appointments', []):
        a['user_id'] = user_id
        results['appointments'].append(Appointment.upsert(a))

    response = {
        'results': results,
        'server_time': datetime.utcnow().isoformat(),
    }
    if temp_id_map:
        response['temp_ids_mapped'] = temp_id_map
    if deleted_patients_confirmed or deleted_opd_confirmed or deleted_appts_confirmed:
        response['deleted_confirmed'] = {
            'patients': deleted_patients_confirmed,
            'opd_records': deleted_opd_confirmed,
            'appointments': deleted_appts_confirmed,
        }
    if sheet_errors:
        response['sheet_warnings'] = sheet_errors
        response['message'] = 'Data saved locally, but Google Sheet was not updated. Grant the service account Editor access to the sheet, then re-sync.'
        return jsonify(response), 207  # Multi-Status: partial success

    return jsonify(response), 200


@sync_bp.route('/push/images/<opd_id>', methods=['POST'])
@jwt_required()
def push_images(opd_id):
    """
    Stage 2: Upload images to Google Drive, persist links in SQLite,
    then update the existing Google Sheets row with image links.
    """
    logger.info("Image push requested for OPD %s", opd_id)

    opd = OPDRecord.get(opd_id)
    if opd is None:
        logger.warning("OPD record not found: %s", opd_id)
        return jsonify({'error': 'OPD record not found'}), 404

    if 'images' not in request.files:
        logger.warning("No 'images' field in request for OPD %s", opd_id)
        return jsonify({'error': 'No image files provided'}), 400

    files = request.files.getlist('images')
    files = [f for f in files if f.filename]
    if not files:
        logger.warning("No valid image files for OPD %s", opd_id)
        return jsonify({'error': 'No valid image files provided'}), 400

    try:
        visit_date = datetime.fromisoformat(opd['visit_date'])
    except (ValueError, TypeError):
        visit_date = datetime.utcnow()

    if IS_CLOUD:
        logger.info("Cloud mode: uploading %d image(s) directly to Drive for OPD %s", len(files), opd_id)
        drive_urls = []
        for i, f in enumerate(files, 1):
            url = upload_image_fileobj_to_drive(opd_id, f, i)
            if url:
                drive_urls.append(url)
        logger.info("Uploaded %d image(s) to Drive for OPD %s", len(drive_urls), opd_id)
    else:
        saved_paths = save_images_locally(opd_id, files)
        logger.info("Saved %d image(s) for OPD %s", len(saved_paths), opd_id)
        drive_urls = check_existing_drive_files(opd_id, visit_date, len(saved_paths))
        if not drive_urls:
            image_records = [_ImageRecord(p) for p in saved_paths]
            drive_urls = upload_images_to_drive(opd_id, image_records, visit_date)
            logger.info("Uploaded %d image(s) to Drive for OPD %s",
                        len(drive_urls), opd_id)
        else:
            logger.info("Reused %d existing Drive file(s) for OPD %s",
                        len(drive_urls), opd_id)

    urls_text = "\n".join(drive_urls)
    OPDRecord.set_image_links(opd_id, urls_text)
    logger.info("Image links persisted for OPD %s", opd_id)

    sheet_update_ok = True
    try:
        _sync_opd_to_sheets(opd, drive_urls)
    except RuntimeError as e:
        logger.error(
            "Sheet update blocked for OPD %s (no new sheet created): %s",
            opd_id, e
        )
        sheet_update_ok = False
    except Exception as e:
        logger.error("Sheet update failed for OPD %s: %s", opd_id, e)
        sheet_update_ok = False

    response = {
        'opd_id': opd_id,
        'image_count': len(drive_urls),
        'drive_urls': drive_urls,
        'images_uploaded': True,
        'sheet_updated': sheet_update_ok,
    }

    if sheet_update_ok:
        response['message'] = 'Images synced successfully'
        return jsonify(response), 200
    else:
        response['message'] = (
            'Images uploaded to Drive, but the Google Sheet was not updated. '
            'Grant the service account Editor access to the sheet, then re-sync.'
        )
        response['error'] = (
            f'Sheet ID {GOOGLE_SHEET_ID} is not accessible. '
            f'Add medihive-service@medihive-500611.iam.gserviceaccount.com '
            f'as Editor on the sheet.'
        )
        return jsonify(response), 207


@sync_bp.route('/clear-data', methods=['POST'])
@jwt_required()
def clear_all_data():
    """
    Clear ALL data from the Google Sheet (opd_visits tab) and
    the backend SQLite database (opd_records, patients, etc.).
    Returns the number of rows cleared from the sheet.
    """
    logger.warning("CLEAR ALL DATA requested by user %s", get_jwt_identity())

    try:
        from database import (
            DEFAULT_ADMIN_NAME,
            DEFAULT_ADMIN_PASSWORD,
            DEFAULT_ADMIN_USERNAME,
            get_db,
        )
        import hashlib

        rows_cleared = clear_opd_sheet_data()

        # Additional backend cleanup
        db = get_db()

        # Re-create the default admin user if it was deleted
        from datetime import datetime
        now = datetime.utcnow().isoformat()
        default_admin_password_hash = hashlib.sha256(
            DEFAULT_ADMIN_PASSWORD.encode()
        ).hexdigest()

        # Re-create default user
        try:
            db.execute(
                "INSERT INTO users (username, password, name, created_at) VALUES (%s, %s, %s, %s) ON CONFLICT (username) DO NOTHING",
                (
                    DEFAULT_ADMIN_USERNAME,
                    default_admin_password_hash,
                    DEFAULT_ADMIN_NAME,
                    now,
                )
            )
            db.commit()
        except Exception:
            db.rollback()

        db.close()

        return jsonify({
            'message': f'All data cleared successfully. Removed {rows_cleared} rows from sheet.',
            'sheet_rows_cleared': rows_cleared,
        }), 200

    except RuntimeError as e:
        logger.error("Clear data failed (sheet access error): %s", e)
        return jsonify({
            'error': f'Could not clear sheet data: {e}',
            'detail': 'Verify the service account has EDITOR access to the sheet.'
        }), 500
    except Exception as e:
        logger.error("Clear data failed: %s", e)
        return jsonify({'error': f'Clear data failed: {e}'}), 500
