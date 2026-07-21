from flask import Blueprint, request, jsonify
from models.symptom_master import SymptomMaster
from services.log_service import get_logger

logger = get_logger(__name__)

symptoms_bp = Blueprint('symptoms', __name__)


@symptoms_bp.route('', methods=['GET'])
def list_symptoms():
    """List all symptoms, optionally filtered by search query."""
    search = request.args.get('search')
    
    if search:
        db = __import__('database').get_db()
        rows = db.execute(
            "SELECT * FROM symptoms_master WHERE name LIKE %s ORDER BY name ASC",
            (f'%{search}%',)
        ).fetchall()
        db.close()
        symptoms = [SymptomMaster.dict_from_row(r) for r in rows]
    else:
        symptoms = SymptomMaster.all()
    
    return jsonify({'symptoms': symptoms}), 200


@symptoms_bp.route('/<int:symptom_id>', methods=['GET'])
def get_symptom(symptom_id):
    """Get a single symptom by ID."""
    symptom = SymptomMaster.get(symptom_id)
    if not symptom:
        return jsonify({'error': 'Symptom not found'}), 404
    return jsonify(symptom), 200


@symptoms_bp.route('', methods=['POST'])
def create_symptom():
    """Create a new symptom."""
    data = request.get_json() or {}
    if not data.get('name'):
        return jsonify({'error': 'name is required'}), 400
    
    symptom = SymptomMaster.upsert(data)
    if not symptom:
        return jsonify({'error': 'Failed to create symptom'}), 500
    return jsonify(symptom), 201


@symptoms_bp.route('/<int:symptom_id>', methods=['DELETE'])
def delete_symptom(symptom_id):
    """Delete a symptom."""
    symptom = SymptomMaster.get(symptom_id)
    if not symptom:
        return jsonify({'error': 'Symptom not found'}), 404
    
    SymptomMaster.delete(symptom_id)
    return jsonify({'message': 'Symptom deleted'}), 200
