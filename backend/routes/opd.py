from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required
from models.opd_record import OPDRecord
from models.patient import Patient
from datetime import datetime

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
