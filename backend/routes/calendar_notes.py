from flask import Blueprint, request, jsonify
from models.calendar_note import CalendarNote
from services.log_service import get_logger

logger = get_logger(__name__)

calendar_notes_bp = Blueprint('calendar_notes', __name__)


@calendar_notes_bp.route('', methods=['GET'])
def list_notes():
    """List all calendar notes, optionally filtered by date range."""
    start_date = request.args.get('start_date')
    end_date = request.args.get('end_date')
    
    if start_date and end_date:
        db = __import__('database').get_db()
        rows = db.execute(
            "SELECT * FROM calendar_notes WHERE note_date >= %s AND note_date <= %s ORDER BY note_date DESC",
            (start_date, end_date)
        ).fetchall()
        db.close()
        notes = [CalendarNote.dict_from_row(r) for r in rows]
    else:
        notes = CalendarNote.all()
    
    return jsonify({'calendar_notes': notes}), 200


@calendar_notes_bp.route('/<int:note_id>', methods=['GET'])
def get_note(note_id):
    """Get a single calendar note by ID."""
    note = CalendarNote.get(note_id)
    if not note:
        return jsonify({'error': 'Note not found'}), 404
    return jsonify(note), 200


@calendar_notes_bp.route('', methods=['POST'])
def create_or_update_note():
    """Create or update a calendar note (upsert by note_date)."""
    data = request.get_json() or {}
    if not data.get('note_date'):
        return jsonify({'error': 'note_date is required'}), 400
    
    note = CalendarNote.upsert(data)
    return jsonify(note), 200


@calendar_notes_bp.route('/<int:note_id>', methods=['PUT'])
def update_note(note_id):
    """Update an existing calendar note."""
    data = request.get_json() or {}
    note = CalendarNote.get(note_id)
    if not note:
        return jsonify({'error': 'Note not found'}), 404
    
    updated = CalendarNote.update(note_id, data)
    return jsonify(updated), 200


@calendar_notes_bp.route('/<int:note_id>', methods=['DELETE'])
def delete_note(note_id):
    """Delete a calendar note."""
    note = CalendarNote.get(note_id)
    if not note:
        return jsonify({'error': 'Note not found'}), 404
    
    db = __import__('database').get_db()
    db.execute("DELETE FROM calendar_notes WHERE id = %s", (note_id,))
    db.commit()
    db.close()
    return jsonify({'message': 'Note deleted'}), 200
