from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required
from models.patient import Patient

patients_bp = Blueprint('patients', __name__)


@patients_bp.route('', methods=['GET'])
@jwt_required()
def list_patients():
    search = request.args.get('search', '').strip().lower()
    patients = Patient.all()
    if search:
        patients = [p for p in patients if
                    search in p['name'].lower() or
                    search in p['id'].lower() or
                    search in p.get('mobile', '').lower()]
    return jsonify({'patients': patients}), 200


@patients_bp.route('/<patient_id>', methods=['GET'])
@jwt_required()
def get_patient(patient_id):
    patient = Patient.get(patient_id)
    if patient is None:
        return jsonify({'error': 'Patient not found'}), 404
    return jsonify({'patient': patient}), 200


@patients_bp.route('', methods=['POST'])
@jwt_required()
def create_patient():
    data = request.get_json()
    if not data or not data.get('id') or not data.get('name'):
        return jsonify({'error': 'id and name required'}), 400
    patient = Patient.create(data)
    return jsonify({'patient': patient}), 201


@patients_bp.route('/<patient_id>', methods=['PUT'])
@jwt_required()
def update_patient(patient_id):
    data = request.get_json()
    if not data:
        return jsonify({'error': 'Request body required'}), 400
    patient = Patient.update(patient_id, data)
    if patient is None:
        return jsonify({'error': 'Patient not found'}), 404
    return jsonify({'patient': patient}), 200


@patients_bp.route('/<patient_id>', methods=['DELETE'])
@jwt_required()
def delete_patient(patient_id):
    Patient.delete(patient_id)
    return jsonify({'message': 'Deleted'}), 200
