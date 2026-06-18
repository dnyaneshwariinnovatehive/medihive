from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required
from models.patient import Patient
from models.opd_record import OPDRecord
from models.appointment import Appointment

sync_bp = Blueprint('sync', __name__)


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
        'server_time': __import__('datetime').datetime.utcnow().isoformat(),
    }), 200


@sync_bp.route('/push', methods=['POST'])
@jwt_required()
def push():
    """
    Client sends local changes. Server upserts them.
    """
    data = request.get_json() or {}

    results = {'patients': [], 'opd_records': [], 'appointments': []}

    for p in data.get('patients', []):
        results['patients'].append(Patient.upsert(p))

    for r in data.get('opd_records', []):
        results['opd_records'].append(OPDRecord.upsert(r))

    for a in data.get('appointments', []):
        results['appointments'].append(Appointment.upsert(a))

    return jsonify({
        'results': results,
        'server_time': __import__('datetime').datetime.utcnow().isoformat(),
    }), 200
