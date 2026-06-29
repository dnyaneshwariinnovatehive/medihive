from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required
from models.opd_record import OPDRecord
from models.patient import Patient
from datetime import datetime
from pathlib import Path
from config import IMAGE_STORAGE_PATH
from desktop_google.drive_service import upload_images_to_drive
from desktop_google.sheets_service import append_row_to_sheet
from services.log_service import get_logger

logger = get_logger(__name__)

opd_bp = Blueprint('opd', __name__)


@opd_bp.route('', methods=['GET'])
@jwt_required()
def list_opd():
    patient_id = request.args.get('patient_id')
    records = OPDRecord.all(patient_id=patient_id)
    return jsonify({'records': records}), 200


@opd_bp.route('/<record_id>', methods=['GET'])
@jwt_required()
def get_opd(record_id):
    record = OPDRecord.get(record_id)
    if record is None:
        return jsonify({'error': 'Record not found'}), 404
    return jsonify({'record': record}), 200


@opd_bp.route('', methods=['POST'])
@jwt_required()
def create_opd():
    data = request.get_json()
    if not data or not data.get('id') or not data.get('patient_id'):
        return jsonify({'error': 'id and patient_id required'}), 400

    record = OPDRecord.create(data)

    # Update patient's last diagnosis and last visit
    patient = Patient.get(data['patient_id'])
    if patient:
        Patient.update(data['patient_id'], {
            'last_diagnosis': data.get('diagnosis', patient.get('last_diagnosis', '')),
            'last_visit_date': data.get('visit_date', datetime.utcnow().isoformat()),
        })

    return jsonify({'record': record}), 201


@opd_bp.route('/<record_id>', methods=['PUT'])
@jwt_required()
def update_opd(record_id):
    data = request.get_json()
    if not data:
        return jsonify({'error': 'Request body required'}), 400
    record = OPDRecord.update(record_id, data)
    if record is None:
        return jsonify({'error': 'Record not found'}), 404
    return jsonify({'record': record}), 200


@opd_bp.route('/<record_id>', methods=['DELETE'])
@jwt_required()
def delete_opd(record_id):
    OPDRecord.delete(record_id)
    return jsonify({'message': 'Deleted'}), 200


# ─────────────────────────────────────────────
# Image sync endpoint
# ─────────────────────────────────────────────

class _ImageRecord:
    def __init__(self, path):
        self.file_path = str(path)


def save_images_locally(opd_id, files):
    opd_dir = Path(IMAGE_STORAGE_PATH) / str(opd_id)
    opd_dir.mkdir(parents=True, exist_ok=True)
    saved = []
    for i, f in enumerate(files, 1):
        ext = Path(f.filename).suffix or '.jpg'
        dest = opd_dir / f"image_{i}{ext}"
        f.save(str(dest))
        saved.append(dest)
    return saved


def build_sheet_row_data(opd, patient, drive_urls):
    def safe_int(val):
        try:
            return int(val or '0')
        except (ValueError, TypeError):
            return 0

    consultation_fee = safe_int(opd.get('consultation_fee'))
    medicine_fee = safe_int(opd.get('medicine_fee'))
    discount = safe_int(opd.get('discount'))
    total_fee = consultation_fee + medicine_fee - discount

    return {
        'OPD ID': opd['id'],
        'Patient ID': opd['patient_id'],
        'Patient Name': patient.get('name', ''),
        'Mobile': patient.get('mobile', ''),
        'Gender': patient.get('gender', ''),
        'DOB': patient.get('dob', ''),
        'Age': patient.get('age', 0),
        'Blood Group': opd.get('blood_group', ''),
        'Address': patient.get('address', ''),
        'Visit Date': opd.get('visit_date', ''),
        'OPD Type': opd.get('type', 'consultation'),
        'Charge Type': opd.get('charge_type', ''),
        'Diagnosis': opd.get('diagnosis', ''),
        'Symptoms': opd.get('symptoms', ''),
        'Clinical Notes': opd.get('clinical_notes', ''),
        'Panchakarma Notes': '',
        'Medicines': opd.get('medicines', ''),
        'Consultation Fee': opd.get('consultation_fee', '0'),
        'Medicine Fee': opd.get('medicine_fee', '0'),
        'Panchakarma Fee': '0',
        'Total Fee': str(total_fee),
        'Discount Type': 'NA',
        'Discount Value': opd.get('discount', '0'),
        'Payment Mode': opd.get('payment_mode', ''),
        'Next Visit Date': opd.get('next_visit', ''),
        'Follow-up Status': opd.get('follow_up_reason', ''),
        'Image Links': drive_urls,
    }


@opd_bp.route('/<opd_id>/images', methods=['POST'])
@jwt_required()
def upload_opd_images(opd_id):
    logger.info("Image sync requested for OPD %s", opd_id)

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

    logger.info("Saving %d image(s) locally for OPD %s", len(files), opd_id)
    saved_paths = save_images_locally(opd_id, files)
    logger.info("Saved %d image(s) at %s", len(saved_paths), IMAGE_STORAGE_PATH)

    try:
        visit_date = datetime.fromisoformat(opd['visit_date'])
    except (ValueError, TypeError):
        logger.warning("Could not parse visit_date '%s', using current time", opd.get('visit_date'))
        visit_date = datetime.utcnow()

    image_records = [_ImageRecord(p) for p in saved_paths]
    logger.info("Uploading %d image(s) to Google Drive for OPD %s", len(image_records), opd_id)
    drive_urls = upload_images_to_drive(opd_id, image_records, visit_date)
    logger.info("Uploaded %d image(s) to Drive for OPD %s", len(drive_urls), opd_id)

    patient = Patient.get(opd['patient_id'])
    if patient is None:
        logger.error("Patient not found for OPD %s (patient_id=%s)", opd_id, opd['patient_id'])
        return jsonify({'error': 'Patient not found'}), 404

    logger.info("Appending row to Google Sheets for OPD %s", opd_id)
    row_data = build_sheet_row_data(opd, patient, drive_urls)
    append_row_to_sheet(**row_data)
    logger.info("Sheet append complete for OPD %s", opd_id)

    urls_text = "\n".join(drive_urls)
    OPDRecord.set_image_links(opd_id, urls_text)
    logger.info("Image links persisted in opd_records for OPD %s", opd_id)

    return jsonify({
        'message': 'Images synced successfully',
        'opd_id': opd_id,
        'image_count': len(drive_urls),
        'drive_urls': drive_urls,
    }), 200
