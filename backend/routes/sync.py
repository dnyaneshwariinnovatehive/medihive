"""Mobile-only sync endpoints for MediHive.

Consolidated sync module with incremental upload/download and disaster recovery.
Supports legacy and consolidated endpoint names for backward compatibility.
"""

from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required, get_jwt_identity
from models.patient import Patient
from models.opd_record import OPDRecord
from models.calendar_note import CalendarNote
from models.clinic_setting import ClinicSetting
from models.medicine import Medicine
from models.symptom_master import SymptomMaster
from models.patient_image import PatientImage
from database import get_db
from datetime import datetime
from config import IMAGE_STORAGE_PATH, IS_CLOUD
from services.log_service import get_logger
from routes.opd import save_images_locally, build_sheet_row_data, _ImageRecord

logger = get_logger(__name__)

sync_bp = Blueprint('sync', __name__)
cloud_bp = Blueprint('cloud', __name__)


def _sync_opd_to_sheets(opd, image_links=None):
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
                "Could not create placeholder patient %s for OPD %s",
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
    try:
        from sheets_utils import upsert_opd_row_in_sheet
        upsert_opd_row_in_sheet(opd_id, row_data)
        logger.info("SHEET SYNC END: OPD=%s", opd_id)
        return None
    except RuntimeError as e:
        logger.warning("Sheet sync skipped for OPD %s: %s", opd_id, e)
        return f"Sheet sync skipped: {e}"
    except Exception as e:
        logger.warning("Sheet sync error for OPD %s: %s", opd_id, e)
        return f"Sheet sync error: {e}"


# ── Device Registration (Dummy for compatibility) ──

@sync_bp.route('/register-device', methods=['POST'])
@cloud_bp.route('/register-device', methods=['POST'])
def register_device():
    logger.info("Device registration request received (dummy endpoint)")
    return jsonify({'message': 'Device registered'}), 200


@sync_bp.route('/heartbeat', methods=['POST'])
@cloud_bp.route('/heartbeat', methods=['POST'])
def heartbeat():
    return jsonify({'message': 'ok'}), 200


# ── Incremental Sync Upload ──────────────────────────

@sync_bp.route('/upload', methods=['POST'])
@sync_bp.route('/push', methods=['POST'])
@cloud_bp.route('/upload-changes', methods=['POST'])
@jwt_required()
def sync_upload():
    user_id = get_jwt_identity()
    data = request.get_json() or {}
    device_id = data.get('device_id', '')
    now = datetime.utcnow().isoformat()

    logger.info(
        "UPLOAD user=%s device=%s patients=%d opd_records=%d calendar_notes=%d deleted=%d",
        user_id, device_id,
        len(data.get('patients', [])),
        len(data.get('opd_records', [])),
        len(data.get('calendar_notes', [])),
        len(data.get('deleted_entities', [])),
    )

    results = {'patients': [], 'opd_records': []}
    sheet_warnings = []
    temp_id_map = {}

    # ── Patients ──
    for p in data.get('patients', []):
        old_id = p.get('id', '')
        is_temp = str(old_id).startswith('TEMP_')
        if is_temp:
            p['id'] = Patient.assign_next_id()
            temp_id_map[old_id] = p['id']

        patient = Patient.upsert(p)
        results['patients'].append(patient)

        # Sync all OPD records of this patient to Google Sheet to update patient details there immediately!
        try:
            opds = OPDRecord.all(patient_id=patient['id'])
            for opd in opds:
                sheet_err = _sync_opd_to_sheets(opd)
                if sheet_err:
                    sheet_warnings.append(sheet_err)
        except Exception as e:
            logger.warning("Failed to sync patient %s OPDs to sheets: %s", patient['id'], e)
            sheet_warnings.append(str(e))

    # ── OPD Records ──
    for r in data.get('opd_records', []):
        pat_id = r.get('patient_id', '')
        if pat_id in temp_id_map:
            r['patient_id'] = temp_id_map[pat_id]

        result = OPDRecord.upsert(r)
        results['opd_records'].append(result)

        try:
            sheet_err = _sync_opd_to_sheets(result)
            if sheet_err:
                sheet_warnings.append(sheet_err)
        except Exception as e:
            logger.warning("Sheet sync failed for OPD %s: %s", r.get('id'), e)
            sheet_warnings.append(str(e))

    # ── Calendar Notes ──
    for note in data.get('calendar_notes', []):
        try:
            CalendarNote.upsert(note)
            logger.info("PUSH: calendar note for date %s synced", note.get('note_date'))
        except Exception as e:
            logger.warning("PUSH: calendar note sync failed: %s", e)

    # ── Clinic Settings ──
    for setting in data.get('clinic_settings', []):
        try:
            ClinicSetting.upsert(setting)
            logger.info("PUSH: clinic settings synced")
        except Exception as e:
            logger.warning("PUSH: clinic settings sync failed: %s", e)

    # ── Medicines ──
    for med in data.get('medicines', []):
        try:
            Medicine.upsert(med)
        except Exception as e:
            logger.warning("PUSH: medicine sync failed: %s", e)

    # ── Symptoms ──
    for sym in data.get('symptoms', []):
        try:
            SymptomMaster.upsert(sym)
        except Exception as e:
            logger.warning("PUSH: symptom sync failed: %s", e)

    # ── Deleted Entities ──
    for entry in data.get('deleted_entities', []):
        etype = entry.get('entity_type')
        eid = entry.get('entity_id')
        try:
            if etype == 'patient':
                Patient.delete(eid)
            elif etype == 'opd_visit':
                OPDRecord.delete(eid)
        except Exception as exc:
            logger.warning("Delete sync failed for %s %s: %s", etype, eid, exc)

    response = {
        'results': results,
        'server_time': now,
    }
    if temp_id_map:
        response['temp_ids_mapped'] = temp_id_map
    if sheet_warnings:
        response['sheet_warnings'] = sheet_warnings

    try:
        from services.fcm_service import notify_data_sync
        notify_data_sync(user_id)
    except Exception as exc:
        logger.warning("FCM sync notification failed: %s", exc)

    return jsonify(response), 200


# ── Incremental Sync Download ────────────────────────

@sync_bp.route('/download', methods=['POST'])
@sync_bp.route('/pull', methods=['POST'])
@cloud_bp.route('/download-changes', methods=['POST'])
@jwt_required()
def sync_download():
    user_id = get_jwt_identity()
    data = request.get_json() or {}
    last_sync = data.get('last_sync', '2000-01-01T00:00:00')

    patients = Patient.updated_since(last_sync)
    opd_records = OPDRecord.updated_since(last_sync)
    calendar_notes = CalendarNote.updated_since(last_sync)
    clinic_settings = ClinicSetting.updated_since(last_sync)
    medicines = Medicine.all()
    symptoms = SymptomMaster.all()
    patient_images = PatientImage.updated_since(last_sync)

    logger.info(
        "DOWNLOAD user=%s since=%s patients=%d opd=%d notes=%d images=%d",
        user_id, last_sync,
        len(patients), len(opd_records),
        len(calendar_notes), len(patient_images),
    )

    return jsonify({
        'patients': patients,
        'opd_records': opd_records,
        'calendar_notes': calendar_notes,
        'clinic_settings': clinic_settings,
        'medicines': medicines,
        'symptoms': symptoms,
        'patient_images': patient_images,
        'server_time': datetime.utcnow().isoformat(),
    }), 200


# ── Disaster Recovery: Full Restore ──────────────────

@sync_bp.route('/full-restore', methods=['GET'])
@jwt_required()
def full_restore():
    user_id = get_jwt_identity()

    patients = Patient.all()
    opd_records = OPDRecord.all()
    calendar_notes = CalendarNote.all()
    clinic_settings = ClinicSetting.get_first()
    medicines = Medicine.all()
    symptoms = SymptomMaster.all()
    patient_images = PatientImage.all()

    return jsonify({
        'patients': patients,
        'opd_records': opd_records,
        'calendar_notes': calendar_notes,
        'clinic_settings': [clinic_settings] if clinic_settings else [],
        'medicines': medicines,
        'symptoms': symptoms,
        'patient_images': patient_images,
        'server_time': datetime.utcnow().isoformat(),
    }), 200


# ── Mobile Sync: Upload Images ──────────────────────

@sync_bp.route('/upload-images/<opd_id>', methods=['POST'])
@sync_bp.route('/push/images/<opd_id>', methods=['POST'])
@cloud_bp.route('/upload-images/<opd_id>', methods=['POST'])
@jwt_required()
def sync_upload_images(opd_id):
    user_id = get_jwt_identity()
    logger.info("=== IMAGE UPLOAD START === OPD=%s user=%s", opd_id, user_id)

    opd = OPDRecord.get_by_opd_id(opd_id)
    if opd is None:
        try:
            opd = OPDRecord.get(int(opd_id))
        except (ValueError, TypeError):
            opd = None

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
        visit_date = datetime.fromisoformat(opd['visit_datetime'])
    except (ValueError, TypeError):
        visit_date = datetime.utcnow()

    from drive_utils import upload_image_fileobj_to_drive, upload_images_to_drive, check_existing_drive_files

    if IS_CLOUD:
        logger.info("CLOUD MODE: uploading %d image(s) directly to Drive for OPD %s",
                    len(files), opd_id)
        drive_urls = []
        for i, f in enumerate(files, 1):
            url = upload_image_fileobj_to_drive(opd_id, f, i)
            if url:
                drive_urls.append(url)
    else:
        logger.info("LOCAL MODE: saving %d image(s) to disk for OPD %s", len(files), opd_id)
        saved_paths = save_images_locally(opd_id, files)

        drive_urls = check_existing_drive_files(opd_id, visit_date, len(saved_paths))
        if not drive_urls:
            image_records = [_ImageRecord(p) for p in saved_paths]
            drive_urls = upload_images_to_drive(opd_id, image_records, visit_date)

    if not drive_urls:
        logger.error("IMAGE UPLOAD FAILED: No Drive URLs generated for OPD %s", opd_id)
        return jsonify({
            'error': 'Image upload to Drive failed',
            'opd_id': opd_id,
            'image_count': 0,
            'drive_urls': [],
            'images_uploaded': False,
        }), 500

    try:
        PatientImage.save_drive_urls(opd['id'], opd.get('patient_id'), drive_urls)
        logger.info("Saved %d drive URLs to patient_images DB for OPD %s", len(drive_urls), opd_id)
    except Exception as exc:
        logger.warning("Could not save drive URLs to patient_images DB: %s", exc)

    sheet_update_ok = True
    sheet_error = None
    try:
        updated_opd = OPDRecord.get_by_opd_id(opd_id) or OPDRecord.get(opd['id'])
        sheet_error = _sync_opd_to_sheets(updated_opd, drive_urls)
        if sheet_error:
            logger.error("Sheet update FAILED for OPD %s: %s", opd_id, sheet_error)
            sheet_update_ok = False
        else:
            logger.info("Google Sheet update SUCCESS for OPD %s", opd_id)
    except Exception as e:
        logger.error("Sheet update FAILED for OPD %s: %s", opd_id, e)
        sheet_update_ok = False
        sheet_error = str(e)

    response = {
        'opd_id': opd_id,
        'image_count': len(drive_urls),
        'drive_urls': drive_urls,
        'images_uploaded': True,
        'sheet_updated': sheet_update_ok,
    }

    try:
        from services.fcm_service import notify_data_sync
        notify_data_sync(user_id)
    except Exception as exc:
        logger.warning("FCM sync notification failed: %s", exc)

    if sheet_update_ok:
        response['message'] = 'Images synced successfully'
        return jsonify(response), 200
    else:
        response['message'] = 'Images uploaded to Drive, but Google Sheet was not updated.'
        if sheet_error:
            response['sheet_error_detail'] = sheet_error
        return jsonify(response), 207


# ── Clinic Info ─────────────────────────────────────

@sync_bp.route('/clinic-info', methods=['GET'])
@jwt_required()
def clinic_info():
    logger.info("Clinic settings info requested")
    settings = ClinicSetting.get_first()
    if settings:
        return jsonify({'clinic': settings}), 200
    return jsonify({'error': 'Clinic info not found'}), 404


# ── Clear Sheet and Local Data ──────────────────────

@sync_bp.route('/clear-data', methods=['POST'])
@jwt_required()
def clear_data():
    try:
        from sheets_utils import clear_opd_sheet_data
        row_count = clear_opd_sheet_data()
        return jsonify({
            'message': 'Clear data process completed successfully',
            'sheets_rows_cleared': row_count
        }), 200
    except Exception as e:
        logger.error("Failed to clear data: %s", e)
        return jsonify({'error': str(e)}), 500
