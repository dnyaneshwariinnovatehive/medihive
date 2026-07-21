from flask import Blueprint, request, jsonify
from models.medicine import Medicine
from services.log_service import get_logger

logger = get_logger(__name__)

medicines_bp = Blueprint('medicines', __name__)


@medicines_bp.route('', methods=['GET'])
def list_medicines():
    """List all medicines, optionally filtered by search query."""
    search = request.args.get('search')
    
    if search:
        db = __import__('database').get_db()
        rows = db.execute(
            "SELECT * FROM medicines WHERE name LIKE %s ORDER BY name ASC",
            (f'%{search}%',)
        ).fetchall()
        db.close()
        medicines = [Medicine.dict_from_row(r) for r in rows]
    else:
        medicines = Medicine.all()
    
    return jsonify({'medicines': medicines}), 200


@medicines_bp.route('/<int:medicine_id>', methods=['GET'])
def get_medicine(medicine_id):
    """Get a single medicine by ID."""
    medicine = Medicine.get(medicine_id)
    if not medicine:
        return jsonify({'error': 'Medicine not found'}), 404
    return jsonify(medicine), 200


@medicines_bp.route('', methods=['POST'])
def create_medicine():
    """Create a new medicine."""
    data = request.get_json() or {}
    if not data.get('name'):
        return jsonify({'error': 'name is required'}), 400
    
    medicine = Medicine.upsert(data)
    if not medicine:
        return jsonify({'error': 'Failed to create medicine'}), 500
    return jsonify(medicine), 201


@medicines_bp.route('/<int:medicine_id>', methods=['DELETE'])
def delete_medicine(medicine_id):
    """Delete a medicine."""
    medicine = Medicine.get(medicine_id)
    if not medicine:
        return jsonify({'error': 'Medicine not found'}), 404
    
    Medicine.delete(medicine_id)
    return jsonify({'message': 'Medicine deleted'}), 200
