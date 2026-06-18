from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required
from models.appointment import Appointment

appointments_bp = Blueprint('appointments', __name__)


@appointments_bp.route('', methods=['GET'])
@jwt_required()
def list_appointments():
    date = request.args.get('date')
    appts = Appointment.all(date=date)
    return jsonify({'appointments': appts}), 200


@appointments_bp.route('/<appt_id>', methods=['GET'])
@jwt_required()
def get_appointment(appt_id):
    appt = Appointment.get(appt_id)
    if appt is None:
        return jsonify({'error': 'Appointment not found'}), 404
    return jsonify({'appointment': appt}), 200


@appointments_bp.route('', methods=['POST'])
@jwt_required()
def create_appointment():
    data = request.get_json()
    if not data or not data.get('id') or not data.get('date_time'):
        return jsonify({'error': 'id and date_time required'}), 400
    appt = Appointment.create(data)
    return jsonify({'appointment': appt}), 201


@appointments_bp.route('/<appt_id>', methods=['PUT'])
@jwt_required()
def update_appointment(appt_id):
    data = request.get_json()
    if not data:
        return jsonify({'error': 'Request body required'}), 400
    appt = Appointment.update(appt_id, data)
    if appt is None:
        return jsonify({'error': 'Appointment not found'}), 404
    return jsonify({'appointment': appt}), 200


@appointments_bp.route('/<appt_id>', methods=['DELETE'])
@jwt_required()
def delete_appointment(appt_id):
    Appointment.delete(appt_id)
    return jsonify({'message': 'Deleted'}), 200
