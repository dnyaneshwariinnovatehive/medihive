from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required, get_jwt_identity
from models.patient import Patient
from models.opd_record import OPDRecord
from models.appointment import Appointment
from models.deleted_entity import DeletedEntity
from models.clinic import Clinic
from models.device_registry import DeviceRegistry
from database import get_db
from datetime import datetime
from services.log_service import get_logger

logger = get_logger(__name__)

cloud_bp = Blueprint('cloud', __name__)


def _validate_device(device_id, clinic_id):
    if not device_id or not clinic_id:
        return False
    device = DeviceRegistry.get(device_id)
    if not device:
        return False
    if device.get('clinic_id') != clinic_id:
        return False
    return True


def _sync_opd_to_google_sheets(opd):
    try:
        from routes.sync import _sync_opd_to_sheets
        _sync_opd_to_sheets(opd)
    except ImportError:
        logger.debug("Google Sheets sync not available")
    except RuntimeError as e:
        logger.warning("Google Sheets sync skipped for OPD %s: %s", opd.get('id'), e)
    except Exception as e:
        logger.warning("Google Sheets sync error for OPD %s: %s", opd.get('id'), e)


@cloud_bp.route('/register-device', methods=['POST'])
def register_device():
    """
    Register or update a device for cloud sync.
    Links the device to a clinic so data can be routed correctly.
    No JWT required — device identifies itself via device_id + clinic_id.
    """
    data = request.get_json() or {}
    device_id = data.get('device_id', '').strip()
    if not device_id:
        return jsonify({'error': 'device_id is required'}), 400

    device = DeviceRegistry.register({
        'device_id': device_id,
        'device_name': data.get('device_name', ''),
        'clinic_id': data.get('clinic_id', ''),
        'fcm_token': data.get('fcm_token', ''),
        'app_version': data.get('app_version', ''),
    })
    logger.info("Device registered: %s for clinic %s", device_id, data.get('clinic_id', ''))
    return jsonify({'device': device, 'message': 'Device registered'}), 200


@cloud_bp.route('/upload-changes', methods=['POST'])
def upload_changes():
    """
    Receive local changes from a device and upsert them into the cloud DB.
    Authenticated via device_id + clinic_id (no JWT required).
    After storage, syncs OPD records to Google Sheets when credentials exist.
    """
    data = request.get_json() or {}
    clinic_id = data.get('clinic_id', '')
    device_id = data.get('device_id', '')

    if not clinic_id:
        return jsonify({'error': 'clinic_id is required'}), 400

    if not _validate_device(device_id, clinic_id):
        return jsonify({'error': 'Invalid device or clinic'}), 401

    logger.info(
        "CLOUD DEVICE DEBUG: upload clinic_id=%s device_id=%s",
        clinic_id, device_id,
    )
    logger.info(
        "CLOUD DEVICE DEBUG: upload patients=%d opd=%d appts=%d",
        len(data.get('patients', [])),
        len(data.get('opd_records', [])),
        len(data.get('appointments', [])),
    )

    results = {'patients': [], 'opd_records': [], 'appointments': []}
    temp_id_map = {}

    for p in data.get('patients', []):
        p['user_id'] = device_id
        p['clinic_id'] = clinic_id
        old_id = p.get('id', '')
        is_temp = old_id.startswith('TEMP_')
        if is_temp:
            p['id'] = Patient.assign_next_id()
            temp_id_map[old_id] = p['id']
        patient = Patient.upsert(p)
        results['patients'].append(patient)
        logger.info("CLOUD DEVICE DEBUG: stored patient id=%s clinic_id=%s", p['id'], p.get('clinic_id', ''))

    for r in data.get('opd_records', []):
        r['user_id'] = device_id
        r['clinic_id'] = clinic_id
        pat_id = r.get('patient_id', '')
        if pat_id in temp_id_map:
            r['patient_id'] = temp_id_map[pat_id]
        logger.info("CLOUD DEBUG: OPD id=%s panchakarma_fee=%s total_fee=%s discount_type=%s",
                     r.get('id'), r.get('panchakarma_fee', ''), r.get('total_fee', ''), r.get('discount_type', ''))
        result = OPDRecord.upsert(r)
        results['opd_records'].append(result)
        logger.info("CLOUD DEVICE DEBUG: stored opd id=%s clinic_id=%s", r['id'], r.get('clinic_id', ''))
        # Sync to Google Sheets from any network
        _sync_opd_to_google_sheets(r)

    for a in data.get('appointments', []):
        a['user_id'] = device_id
        a['clinic_id'] = clinic_id
        results['appointments'].append(Appointment.upsert(a))

    for entry in data.get('deleted_entities', []):
        etype = entry.get('entity_type')
        eid = entry.get('entity_id')
        DeletedEntity.record(etype, eid, user_id=device_id, clinic_id=clinic_id)

    _log_sync(
        clinic_id, 'upload', device_id=device_id,
        patients=len(results['patients']),
        opd=len(results['opd_records']),
        appts=len(results['appointments']),
        deleted=len(data.get('deleted_entities', [])),
    )

    logger.info("CLOUD DEVICE DEBUG: stored patients=%d opd_records=%d appts=%d",
                len(results['patients']), len(results['opd_records']), len(results['appointments']))

    response = {
        'results': results,
        'server_time': datetime.utcnow().isoformat(),
    }
    if temp_id_map:
        response['temp_ids_mapped'] = temp_id_map
    return jsonify(response), 200


@cloud_bp.route('/download-changes', methods=['POST'])
def download_changes():
    """
    Return all records updated since the given timestamp for the specified clinic.
    Authenticated via device_id + clinic_id (no JWT required).
    """
    data = request.get_json() or {}
    clinic_id = data.get('clinic_id', '')
    device_id = data.get('device_id', '')
    last_sync = data.get('last_sync', '2000-01-01T00:00:00')

    if not clinic_id:
        return jsonify({'error': 'clinic_id is required'}), 400

    if not _validate_device(device_id, clinic_id):
        return jsonify({'error': 'Invalid device or clinic'}), 401

    patients = Patient.updated_since(last_sync, clinic_id=clinic_id)
    opd_records = OPDRecord.updated_since(last_sync, clinic_id=clinic_id)
    appointments = Appointment.updated_since(last_sync, clinic_id=clinic_id)
    deleted_entities = DeletedEntity.since(last_sync, clinic_id=clinic_id)

    logger.info(
        "CLOUD DEVICE DEBUG: download clinic_id=%s device_id=%s last_sync=%s",
        clinic_id, device_id, last_sync,
    )
    logger.info(
        "CLOUD DEVICE DEBUG: returned patients=%d opd=%d appts=%d deleted=%d",
        len(patients), len(opd_records), len(appointments), len(deleted_entities),
    )
    for p in patients[:3]:
        logger.info("CLOUD DEVICE DEBUG: patient id=%s name=%s updated_at=%s",
                      p['id'], p.get('full_name', ''), p.get('updated_at', ''))
    for r in opd_records[:3]:
        logger.info("CLOUD DEVICE DEBUG: opd id=%s patient_id=%s updated_at=%s",
                      r['id'], r.get('patient_id', ''), r.get('updated_at', ''))

    return jsonify({
        'patients': patients,
        'opd_records': opd_records,
        'appointments': appointments,
        'deleted_entities': deleted_entities,
        'server_time': datetime.utcnow().isoformat(),
    }), 200


@cloud_bp.route('/heartbeat', methods=['POST'])
def heartbeat():
    """
    Update the device's last_seen timestamp.
    Called periodically by devices to indicate they are active.
    No JWT required — device identifies itself via device_id.
    """
    data = request.get_json() or {}
    device_id = data.get('device_id', '')
    if device_id:
        DeviceRegistry.update_heartbeat(device_id)
    return jsonify({'message': 'ok'}), 200


@cloud_bp.route('/upload-images/<opd_id>', methods=['POST'])
def cloud_upload_images(opd_id):
    """
    Upload OPD images to Google Drive.
    Accepts multipart form with 'images' field.
    Reuses the same Drive upload logic as the local sync endpoint.
    """
    logger.info("CLOUD IMAGE DEBUG: endpoint entered opd_id=%s", opd_id)
    logger.info("CLOUD IMAGE DEBUG: request.method=%s", request.method)
    logger.info("CLOUD IMAGE DEBUG: request.files keys=%s", list(request.files.keys()))
    logger.info("CLOUD IMAGE DEBUG: request.content_type=%s", request.content_type)

    opd = OPDRecord.get(opd_id)
    if opd is None:
        logger.warning("CLOUD IMAGE DEBUG: OPD record not found for opd_id=%s", opd_id)
        return jsonify({'error': 'OPD record not found'}), 404
    logger.info("CLOUD IMAGE DEBUG: OPD record found opd_id=%s", opd_id)

    if 'images' not in request.files:
        logger.warning("CLOUD IMAGE DEBUG: 'images' key not in request.files, keys=%s", list(request.files.keys()))
        return jsonify({'error': 'No image files provided'}), 400

    files = request.files.getlist('images')
    logger.info("CLOUD IMAGE DEBUG: raw files count=%d", len(files))
    for idx, f in enumerate(files):
        logger.info("CLOUD IMAGE DEBUG: raw file[%d] filename=%s content_type=%s", idx, f.filename, f.content_type)

    files = [f for f in files if f.filename]
    logger.info("CLOUD IMAGE DEBUG: files received=%d", len(files))
    if not files:
        return jsonify({'error': 'No valid image files provided'}), 400

    logger.info("CLOUD IMAGE: found %d images for OPD %s", len(files), opd_id)

    try:
        visit_date = datetime.fromisoformat(opd['visit_datetime'])
    except (ValueError, TypeError):
        visit_date = datetime.utcnow()

    from desktop_google.drive_service import upload_image_fileobj_to_drive

    drive_urls = []
    for i, f in enumerate(files, 1):
        logger.info("CLOUD IMAGE DEBUG: uploading to drive image %d for OPD %s", i, opd_id)
        try:
            url = upload_image_fileobj_to_drive(opd_id, f, i)
            logger.info("CLOUD IMAGE DEBUG: drive returned url=%s", url)
        except Exception as e:
            logger.error("CLOUD IMAGE DEBUG: upload_image_fileobj_to_drive raised: %s", str(e), exc_info=True)
            raise
        if url:
            file_id = url.split('/d/')[1].split('/')[0] if '/d/' in url else url
            logger.info("CLOUD IMAGE DEBUG: drive file_id=%s", file_id)
            logger.info("CLOUD IMAGE DEBUG: generated url=%s", url)
            drive_urls.append(url)
        else:
            logger.warning("CLOUD IMAGE DEBUG: upload_image_fileobj_to_drive returned None for image %d", i)

    logger.info("CLOUD IMAGE DEBUG: updating image_links for OPD %s (urls count=%d)", opd_id, len(drive_urls))
    urls_text = "\n".join(drive_urls)
    OPDRecord.set_image_links(opd_id, urls_text)
    logger.info("CLOUD IMAGE DEBUG: updated image_links for OPD %s", opd_id)

    sheet_ok = True
    try:
        logger.info("CLOUD IMAGE DEBUG: syncing sheet for OPD %s", opd_id)
        from routes.sync import _sync_opd_to_sheets
        _sync_opd_to_sheets(opd, drive_urls)
        logger.info("CLOUD IMAGE DEBUG: synced sheet for OPD %s", opd_id)
    except RuntimeError as e:
        logger.warning("CLOUD IMAGE DEBUG: sheet update blocked for OPD %s: %s", opd_id, e)
        sheet_ok = False
    except Exception as e:
        logger.warning("CLOUD IMAGE DEBUG: sheet update failed for OPD %s: %s", opd_id, e)
        sheet_ok = False

    response = {
        'opd_id': opd_id,
        'image_count': len(drive_urls),
        'drive_urls': drive_urls,
        'images_uploaded': True,
        'sheet_updated': sheet_ok,
    }
    if sheet_ok:
        response['message'] = 'Images synced successfully'
        return jsonify(response), 200
    else:
        response['message'] = 'Images uploaded to Drive, but Google Sheet was not updated.'
        return jsonify(response), 207


@cloud_bp.route('/clinic-info', methods=['GET'])
@jwt_required()
def clinic_info():
    """
    Get clinic information for the authenticated user.
    The user's clinic_id is determined from the user record.
    """
    user_id = get_jwt_identity()
    db = get_db()
    user = db.execute(
        "SELECT clinic_id FROM users WHERE id = %s", (user_id,)
    ).fetchone()
    db.close()

    if user and user['clinic_id']:
        clinic = Clinic.get(user['clinic_id'])
        if clinic:
            return jsonify({'clinic': clinic}), 200
        return jsonify({'error': 'Clinic not found'}), 404

    return jsonify({'error': 'No clinic assigned to this user'}), 404


# ─── Cloud Sync Log Helper ────────────────────────────

def _log_sync(clinic_id, direction, device_id='', patients=0, opd=0, appts=0, deleted=0, status='success', error=''):
    db = get_db()
    now = datetime.utcnow().isoformat()
    db.execute(
        "INSERT INTO cloud_sync_log (clinic_id, device_id, direction, patients_count, opd_count, appointments_count, deleted_count, status, error_message, created_at) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)",
        (clinic_id, device_id, direction, patients, opd, appts, deleted, status, error, now)
    )
    db.commit()
    db.close()


# ─── New Cloud Sync Blueprint (registered at /api/sync) ──

sync_cloud_bp = Blueprint('sync_cloud', __name__)


@sync_cloud_bp.route('/upload', methods=['POST'])
def sync_cloud_upload():
    data = request.get_json() or {}
    clinic_id = data.get('clinic_id', '')
    device_id = data.get('device_id', '')

    if not clinic_id:
        return jsonify({'error': 'clinic_id is required'}), 400

    if not _validate_device(device_id, clinic_id):
        return jsonify({'error': 'Invalid device or clinic'}), 401

    logger.info(
        "Cloud upload from device=%s clinic=%s",
        device_id, clinic_id,
    )

    results = {'patients': [], 'opd_records': [], 'appointments': []}
    temp_id_map = {}

    for p in data.get('patients', []):
        p['user_id'] = device_id
        p['clinic_id'] = clinic_id
        old_id = p.get('id', '')
        is_temp = old_id.startswith('TEMP_')
        if is_temp:
            p['id'] = Patient.assign_next_id()
            temp_id_map[old_id] = p['id']
        patient = Patient.upsert(p)
        results['patients'].append(patient)

    for r in data.get('opd_records', []):
        r['user_id'] = device_id
        r['clinic_id'] = clinic_id
        pat_id = r.get('patient_id', '')
        if pat_id in temp_id_map:
            r['patient_id'] = temp_id_map[pat_id]
        result = OPDRecord.upsert(r)
        results['opd_records'].append(result)
        _sync_opd_to_google_sheets(r)

    for a in data.get('appointments', []):
        a['user_id'] = device_id
        a['clinic_id'] = clinic_id
        results['appointments'].append(Appointment.upsert(a))

    deleted_count = 0
    for entry in data.get('deleted_entities', []):
        etype = entry.get('entity_type')
        eid = entry.get('entity_id')
        DeletedEntity.record(etype, eid, user_id=device_id, clinic_id=clinic_id)
        deleted_count += 1

    _log_sync(
        clinic_id, 'upload', device_id=device_id,
        patients=len(results['patients']),
        opd=len(results['opd_records']),
        appts=len(results['appointments']),
        deleted=deleted_count,
    )

    logger.info(
        "Cloud upload complete for clinic=%s: %d patients, %d OPDs, %d appts",
        clinic_id,
        len(results['patients']),
        len(results['opd_records']),
        len(results['appointments']),
    )

    response = {
        'results': results,
        'server_time': datetime.utcnow().isoformat(),
    }
    if temp_id_map:
        response['temp_ids_mapped'] = temp_id_map
    return jsonify(response), 200


@sync_cloud_bp.route('/download', methods=['GET'])
def sync_cloud_download():
    clinic_id = request.args.get('clinic_id', '')
    device_id = request.args.get('device_id', '')
    last_sync = request.args.get('last_sync', '2000-01-01T00:00:00')

    if not clinic_id:
        return jsonify({'error': 'clinic_id is required'}), 400

    if not _validate_device(device_id, clinic_id):
        return jsonify({'error': 'Invalid device or clinic'}), 401

    logger.info("Cloud download for clinic=%s last_sync=%s", clinic_id, last_sync)

    patients = Patient.updated_since(last_sync, clinic_id=clinic_id)
    opd_records = OPDRecord.updated_since(last_sync, clinic_id=clinic_id)
    appointments = Appointment.updated_since(last_sync, clinic_id=clinic_id)
    deleted_entities = DeletedEntity.since(last_sync, clinic_id=clinic_id)

    _log_sync(
        clinic_id, 'download',
        patients=len(patients),
        opd=len(opd_records),
        appts=len(appointments),
        deleted=len(deleted_entities),
    )

    logger.info(
        "Cloud download returned patients=%d opd=%d appts=%d deleted=%d",
        len(patients), len(opd_records), len(appointments), len(deleted_entities),
    )

    return jsonify({
        'patients': patients,
        'opd_records': opd_records,
        'appointments': appointments,
        'deleted_entities': deleted_entities,
        'server_time': datetime.utcnow().isoformat(),
    }), 200


@sync_cloud_bp.route('/ack', methods=['POST'])
def sync_cloud_ack():
    data = request.get_json() or {}
    clinic_id = data.get('clinic_id', '')
    device_id = data.get('device_id', '')
    logger.info("Cloud ack from device=%s clinic=%s", device_id, clinic_id)
    _log_sync(clinic_id, 'ack', device_id=device_id, status='acknowledged')
    return jsonify({'message': 'acknowledged', 'server_time': datetime.utcnow().isoformat()}), 200


# ─── Device Registration Blueprint (registered at /api/device) ──

device_bp = Blueprint('device', __name__)


@device_bp.route('/register', methods=['POST'])
def register_device_v2():
    data = request.get_json() or {}
    device_id = data.get('device_id', '').strip()
    if not device_id:
        return jsonify({'error': 'device_id is required'}), 400

    device = DeviceRegistry.register({
        'device_id': device_id,
        'device_name': data.get('device_name', ''),
        'clinic_id': data.get('clinic_id', ''),
        'fcm_token': data.get('fcm_token', ''),
        'app_version': data.get('app_version', ''),
    })
    logger.info("Device registered: %s for clinic %s", device_id, data.get('clinic_id', ''))
    return jsonify({'device': device, 'message': 'Device registered'}), 200
