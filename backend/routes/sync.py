from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required
from models.patient import Patient
from models.opd_record import OPDRecord
from models.appointment import Appointment
from datetime import datetime
from pathlib import Path
from config import IMAGE_STORAGE_PATH
from desktop_google.drive_service import upload_images_to_drive, check_existing_drive_files
from desktop_google.sheets_service import (
    upsert_opd_row_in_sheet,
    update_opd_row_in_sheet,
)
from services.log_service import get_logger
from routes.opd import save_images_locally, build_sheet_row_data, _ImageRecord

logger = get_logger(__name__)

sync_bp = Blueprint('sync', __name__)


def _sync_opd_to_sheets(opd, image_links=None):
    """Append/upsert (Stage 1) or update (Stage 2) OPD row in Google Sheets."""
    patient = Patient.get(opd.get('patient_id'))
    if not patient:
        logger.warning(
            "Patient %s not found, skipping sheet sync for OPD %s",
            opd.get('patient_id'), opd['id'],
        )
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
    Server returns all records updated after that timestamp.
    """
    data = request.get_json() or {}
    last_sync = data.get('last_sync', '2000-01-01T00:00:00')

    patients = Patient.updated_since(last_sync)
    opd_records = OPDRecord.updated_since(last_sync)
    appointments = Appointment.updated_since(last_sync)

    return jsonify({
        'patients': patients,
        'opd_records': opd_records,
        'appointments': appointments,
        'server_time': datetime.utcnow().isoformat(),
    }), 200


@sync_bp.route('/push', methods=['POST'])
@jwt_required()
def push():
    """
    Stage 1: Client sends local changes. Server upserts them,
    then immediately syncs each OPD to Google Sheets (no images yet).
    """
    data = request.get_json() or {}

    results = {'patients': [], 'opd_records': [], 'appointments': []}

    for p in data.get('patients', []):
        results['patients'].append(Patient.upsert(p))

    for r in data.get('opd_records', []):
        result = OPDRecord.upsert(r)
        results['opd_records'].append(result)
        try:
            _sync_opd_to_sheets(r)
        except Exception as e:
            logger.error("Sheet sync failed for OPD %s: %s", r.get('id'), e)

    for a in data.get('appointments', []):
        results['appointments'].append(Appointment.upsert(a))

    return jsonify({
        'results': results,
        'server_time': datetime.utcnow().isoformat(),
    }), 200


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

    saved_paths = save_images_locally(opd_id, files)
    logger.info("Saved %d image(s) for OPD %s", len(saved_paths), opd_id)

    try:
        visit_date = datetime.fromisoformat(opd['visit_date'])
    except (ValueError, TypeError):
        visit_date = datetime.utcnow()

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

    try:
        _sync_opd_to_sheets(opd, drive_urls)
    except Exception as e:
        logger.error("Sheet update failed for OPD %s: %s", opd_id, e)

    return jsonify({
        'message': 'Images synced successfully',
        'opd_id': opd_id,
        'image_count': len(drive_urls),
        'drive_urls': drive_urls,
    }), 200
