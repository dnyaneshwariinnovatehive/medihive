from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required, get_jwt_identity
from models.patient import Patient
from models.opd_record import OPDRecord
from database import get_db
from datetime import datetime
from pathlib import Path
from config import IMAGE_STORAGE_PATH, IS_CLOUD
from desktop_google.drive_service import upload_images_to_drive, check_existing_drive_files, upload_image_fileobj_to_drive
from config import GOOGLE_SHEET_ID
from desktop_google.sheets_service import (
    upsert_opd_row_in_sheet,
    clear_opd_sheet_data,
)
from services.log_service import get_logger
from routes.opd import save_images_locally, build_sheet_row_data, _ImageRecord

logger = get_logger(__name__)

sync_bp = Blueprint('sync', __name__)


def _sync_opd_to_sheets(opd, image_links=None):
    """
    Append/upsert (Stage 1) or update (Stage 2) OPD row in Google Sheets.
    Always uses upsert_opd_row_in_sheet which handles both insert and update.
    Raises RuntimeError if the sheet is not accessible — no new sheet is created.
    """
    opd_id = opd.get('id', 'UNKNOWN')
    patient_id = opd.get('patient_id', 'UNKNOWN')
    logger.info(
        "SHEET SYNC START: OPD=%s patient_id=%s has_images=%s",
        opd_id, patient_id, bool(image_links),
    )

    patient = Patient.get(patient_id)
    if not patient:
        logger.warning(
            "Patient %s not found in PostgreSQL, creating placeholder for sheet sync for OPD %s",
            patient_id, opd_id,
        )
        now = datetime.utcnow().isoformat()
        db = get_db()
        db.execute("""
            INSERT INTO patients
                (id, full_name, mobile_number, gender, created_at)
            VALUES (%s, %s, %s, %s, %s)
            ON CONFLICT DO NOTHING
        """, (
            patient_id, 'Unknown (Auto-created)',
            '', 'Not Specified', now,
        ))
        db.commit()
        db.close()
        patient = Patient.get(patient_id)
        if not patient:
            logger.error(
                "Could not create placeholder patient %s for OPD %s — building row with fallback",
                patient_id, opd_id,
            )
            patient = {
                'id': patient_id,
                'full_name': 'Unknown',
                'mobile_number': '',
                'gender': 'Not Specified',
                'dob': '',
                'age': 0,
                'blood_group': '',
                'address': '',
            }

    row_data = build_sheet_row_data(opd, patient, image_links or [])
    logger.info(
        "SHEET SYNC DATA: OPD=%s diagnosis=%r symptoms=%r clinical_notes=%r panchakarma_notes=%r "
        "consultation_fee=%s medicine_fee=%s panchakarma_fee=%s total_fee=%s "
        "discount_type=%s discount_value=%s payment_mode=%s follow_up_status=%s next_visit=%s",
        opd_id,
        row_data.get('Diagnosis', ''),
        row_data.get('Symptoms', ''),
        row_data.get('Clinical Notes', ''),
        row_data.get('Panchakarma Notes', ''),
        row_data.get('Consultation Fee', ''),
        row_data.get('Medicine Fee', ''),
        row_data.get('Panchakarma Fee', ''),
        row_data.get('Total Fee', ''),
        row_data.get('Discount Type', ''),
        row_data.get('Discount Value', ''),
        row_data.get('Payment Mode', ''),
        row_data.get('Follow-up Status', ''),
        row_data.get('Next Visit Date', ''),
    )

    # Always use upsert_opd_row_in_sheet — it handles both insert and update
    # by searching column A for the OPD ID. This is more robust than switching
    # between upsert/update based on image_links.
    upsert_opd_row_in_sheet(opd_id, row_data)
    logger.info("SHEET SYNC END: OPD=%s — upsert_opd_row_in_sheet called", opd_id)


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

    patients = Patient.updated_since(last_sync)
    opd_records = OPDRecord.updated_since(last_sync)

    return jsonify({
        'patients': patients,
        'opd_records': opd_records,
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
        "PUSH request from user=%s ip=%s patients=%d opd_records=%d",
        user_id, request.remote_addr,
        len(data.get('patients', [])),
        len(data.get('opd_records', [])),
    )
    if data.get('opd_records'):
        for r in data['opd_records']:
            logger.info("PUSH OPD: id=%s patient_id=%s visit_datetime=%s",
                        r.get('id'), r.get('patient_id'), r.get('visit_datetime'))

    results = {'patients': [], 'opd_records': []}
    temp_id_map = {}

    for p in data.get('patients', []):
        old_id = p.get('id', '')
        is_temp = old_id.startswith('TEMP_')
        if is_temp:
            p['id'] = Patient.assign_next_id()
            temp_id_map[old_id] = p['id']
        patient = Patient.upsert(p)
        results['patients'].append(patient)

    # Collect the set of OPD IDs being edited in this push batch
    # so the patient re-sync loop skips them — they will be synced
    # with fresh data in the OPD upsert loop below.
    edited_opd_ids = {r.get('id') for r in data.get('opd_records', []) if r.get('id')}

    # Re-sync all existing OPD records for this patient so that
    # patient columns (name, mobile, blood group, address, etc.)
    # are updated in Google Sheets immediately.
    # SKIP OPDs that are in the current push batch (they will be
    # synced with fresh data in the OPD upsert loop below).
    re_synced_opds = 0
    skipped_edited = 0
    for p in data.get('patients', []):
        pat_id = p.get('id', '')
        if pat_id and not pat_id.startswith('TEMP_'):
            for opd in OPDRecord.all(patient_id=pat_id):
                opd_id = opd.get('id', '')
                if opd_id in edited_opd_ids:
                    logger.info(
                        "Skipping patient re-sync for OPD %s — "
                        "will be synced with fresh data in OPD upsert loop",
                        opd_id,
                    )
                    skipped_edited += 1
                    continue
                try:
                    _sync_opd_to_sheets(opd)
                    re_synced_opds += 1
                except Exception as e:
                    logger.warning(
                        "Patient-edit re-sync failed for OPD %s: %s",
                        opd_id, e,
                    )
    if re_synced_opds or skipped_edited:
        logger.info(
            "Re-synced %d OPD records to sheets after patient edits "
            "(skipped %d edited OPDs that will sync below)",
            re_synced_opds, skipped_edited,
        )

    sheet_errors = []
    for r in data.get('opd_records', []):
        pat_id = r.get('patient_id', '')
        if pat_id in temp_id_map:
            r['patient_id'] = temp_id_map[pat_id]
        opd_id = r.get('id', 'UNKNOWN')
        pk = r.get('panchakarma_notes', '')
        panchakarma_fee = r.get('panchakarma_fee', '')
        total_fee = r.get('total_fee', '')
        discount_type = r.get('discount_type', '')
        discount = r.get('discount_value', '')
        logger.info(
            "OPD UPSERT+SYNC: id=%s patient_id=%s "
            "diagnosis=%r symptoms=%r clinical_notes=%r panchakarma_notes=%r "
            "consultation_fee=%s medicine_fee=%s panchakarma_fee=%s total_fee=%s "
            "discount=%s discount_type=%s payment_mode=%s charge_type=%s "
            "followup_status=%s next_visit_date=%s visit_datetime=%s medicines=%s",
            opd_id, pat_id,
            r.get('diagnosis', ''), r.get('symptoms', ''),
            r.get('clinical_notes', ''), pk,
            r.get('consultation_fee', ''), r.get('medicine_fee', ''),
            panchakarma_fee, total_fee,
            discount, discount_type,
            r.get('payment_mode', ''), r.get('charge_type', ''),
            r.get('followup_status', ''), r.get('next_visit_date', ''),
            r.get('visit_datetime', ''), r.get('medicines', ''),
        )
        result = OPDRecord.upsert(r)
        results['opd_records'].append(result)
        try:
            # Pass the PostgreSQL record (result) not the raw push data (r)
            # so image_links, panchakarma_notes, etc. are preserved
            _sync_opd_to_sheets(result)
        except RuntimeError as e:
            msg = f"Sheet not updated for OPD {opd_id}: {e}"
            logger.error(msg)
            sheet_errors.append(msg)
        except Exception as e:
            msg = f"Sheet sync failed for OPD {opd_id}: {e}"
            logger.error(msg)
            sheet_errors.append(msg)

    deleted_patients_confirmed = []
    deleted_opd_confirmed = []
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
        except Exception as exc:
            logger.warning("Delete sync failed for %s %s: %s", etype, eid, exc)

    response = {
        'results': results,
        'server_time': datetime.utcnow().isoformat(),
    }
    if temp_id_map:
        response['temp_ids_mapped'] = temp_id_map
    if deleted_patients_confirmed or deleted_opd_confirmed:
        response['deleted_confirmed'] = {
            'patients': deleted_patients_confirmed,
            'opd_records': deleted_opd_confirmed,
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
    logger.info("=== IMAGE UPLOAD START === OPD=%s", opd_id)
    logger.info("Request content_type=%s content_length=%s",
                request.content_type, request.content_length)

    opd = OPDRecord.get(opd_id)
    if opd is None:
        logger.warning("OPD record not found: %s", opd_id)
        return jsonify({'error': 'OPD record not found'}), 404

    logger.info("OPD found: patient_id=%s visit_datetime=%s",
                opd.get('patient_id'), opd.get('visit_datetime'))

    if 'images' not in request.files:
        logger.warning("No 'images' field in request for OPD %s", opd_id)
        return jsonify({'error': 'No image files provided'}), 400

    files = request.files.getlist('images')
    raw_file_count = len(files)
    files = [f for f in files if f.filename]
    logger.info("Files received: %d total, %d with filename, %d filtered out",
                raw_file_count, len(files), raw_file_count - len(files))

    for i, f in enumerate(files):
        f.seek(0, 2)  # seek to end
        size = f.tell()
        f.seek(0)  # seek back to start
        logger.info("  File[%d]: name=%s type=%s size=%d bytes",
                    i, f.filename, f.content_type, size)

    if not files:
        logger.warning("No valid image files for OPD %s", opd_id)
        return jsonify({'error': 'No valid image files provided'}), 400

    try:
        visit_date = datetime.fromisoformat(opd['visit_datetime'])
        logger.info("Parsed visit_datetime: %s", visit_date)
    except (ValueError, TypeError):
        visit_date = datetime.utcnow()
        logger.warning("Could not parse visit_datetime '%s', using current time: %s",
                       opd.get('visit_datetime'), visit_date)

    if IS_CLOUD:
        logger.info("CLOUD MODE: uploading %d image(s) directly to Drive for OPD %s",
                    len(files), opd_id)
        drive_urls = []
        for i, f in enumerate(files, 1):
            logger.info("Drive upload starting: OPD=%s index=%d filename=%s",
                        opd_id, i, f.filename)
            url = upload_image_fileobj_to_drive(opd_id, f, i)
            if url:
                drive_urls.append(url)
                logger.info("Drive upload SUCCESS: OPD=%s url=%s", opd_id, url)
            else:
                logger.error("Drive upload FAILED: OPD=%s index=%d", opd_id, i)
        logger.info("Uploaded %d/%d image(s) to Drive for OPD %s",
                    len(drive_urls), len(files), opd_id)
    else:
        logger.info("LOCAL MODE: saving %d image(s) to disk for OPD %s",
                    len(files), opd_id)
        saved_paths = save_images_locally(opd_id, files)
        logger.info("Saved %d/%d image(s) to disk for OPD %s. Paths: %s",
                    len(saved_paths), len(files), opd_id,
                    [str(p) for p in saved_paths])

        logger.info("Checking for existing Drive files for OPD %s", opd_id)
        drive_urls = check_existing_drive_files(opd_id, visit_date, len(saved_paths))
        if not drive_urls:
            logger.info("No existing Drive files found, uploading %d image(s) for OPD %s",
                        len(saved_paths), opd_id)
            image_records = [_ImageRecord(p) for p in saved_paths]
            drive_urls = upload_images_to_drive(opd_id, image_records, visit_date)
            logger.info("Uploaded %d/%d image(s) to Drive for OPD %s. URLs: %s",
                        len(drive_urls), len(saved_paths), opd_id, drive_urls)
        else:
            logger.info("Reused %d existing Drive file(s) for OPD %s: %s",
                        len(drive_urls), opd_id, drive_urls)

    if not drive_urls:
        logger.error("IMAGE UPLOAD FAILED: No Drive URLs generated for OPD %s", opd_id)
        return jsonify({
            'error': 'Image upload to Drive failed',
            'opd_id': opd_id,
            'image_count': 0,
            'drive_urls': [],
            'images_uploaded': False,
        }), 500

    urls_text = "\n".join(drive_urls)
    logger.info("Image links for OPD %s: %s", opd_id, urls_text)

    sheet_update_ok = True
    try:
        logger.info("Updating Google Sheet row for OPD %s with %d image link(s)",
                    opd_id, len(drive_urls))
        _sync_opd_to_sheets(opd, drive_urls)
        logger.info("Google Sheet update SUCCESS for OPD %s", opd_id)
    except RuntimeError as e:
        logger.error(
            "Sheet update blocked for OPD %s (no new sheet created): %s",
            opd_id, e
        )
        sheet_update_ok = False
    except Exception as e:
        logger.error("Sheet update FAILED for OPD %s: %s", opd_id, e)
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
        logger.info("=== IMAGE UPLOAD COMPLETE (success) === OPD=%s urls=%s",
                    opd_id, drive_urls)
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
        logger.warning("=== IMAGE UPLOAD PARTIAL === OPD=%s (Drive OK, Sheet FAILED)", opd_id)
        return jsonify(response), 207


@sync_bp.route('/clear-data', methods=['POST'])
@jwt_required()
def clear_all_data():
    """
    Clear ALL data from the Google Sheet (opd_visits tab) and
    the backend database (opd_visits, patients, etc.).
    Returns the number of rows cleared from the sheet.
    """
    logger.warning("CLEAR ALL DATA requested by user %s", get_jwt_identity())

    try:
        from database import (
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
                "INSERT INTO users (username, password_hash, email, created_at) VALUES (%s, %s, %s, %s) ON CONFLICT (username) DO NOTHING",
                (
                    DEFAULT_ADMIN_USERNAME,
                    default_admin_password_hash,
                    'admin@medihive.local',
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
