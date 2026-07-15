from flask import Blueprint, request, jsonify
from flask_jwt_extended import create_access_token
from database import get_db
from datetime import datetime
import hashlib

auth_bp = Blueprint('auth', __name__)


@auth_bp.route('/login', methods=['POST'])
def login():
    data = request.get_json()
    if not data:
        return jsonify({'error': 'Request body required'}), 400

    username = data.get('username', '').strip()
    password = data.get('password', '')

    if not username or not password:
        return jsonify({'error': 'Username and password required'}), 400

    db = get_db()
    hashed = hashlib.sha256(password.encode()).hexdigest()
    user = db.execute(
        "SELECT * FROM users WHERE username = %s AND password_hash = %s",
        (username, hashed)
    ).fetchone()
    db.close()

    if user is None:
        return jsonify({'error': 'Invalid credentials'}), 401

    token = create_access_token(identity=str(user['id']))
    return jsonify({
        'token': token,
        'user': {
            'id': str(user['id']),
            'username': user['username'],
            'name': user['name'],
        }
    }), 200


@auth_bp.route('/register', methods=['POST'])
def register():
    data = request.get_json()
    if not data:
        return jsonify({'error': 'Request body required'}), 400

    username = data.get('username', '').strip()
    password = data.get('password', '')
    name = data.get('name', 'Doctor')

    if not username or not password:
        return jsonify({'error': 'Username and password required'}), 400

    db = get_db()
    existing = db.execute("SELECT id FROM users WHERE username = %s", (username,)).fetchone()
    if existing:
        db.close()
        return jsonify({'error': 'Username already exists'}), 409

    hashed = hashlib.sha256(password.encode()).hexdigest()
    now = datetime.utcnow().isoformat()
    email = data.get('email', f"{username}@medihive.local")
    clinic_id = data.get('clinic_id', 'CLI001')
    role = data.get('role', 'Doctor')
    row = db.execute(
        "INSERT INTO users (username, password_hash, email, role, name, created_at, clinic_id) VALUES (%s, %s, %s, %s, %s, %s, %s) RETURNING id",
        (username, hashed, email, role, name, now, clinic_id)
    ).fetchone()
    db.commit()
    user_id = row['id']

    token = create_access_token(identity=str(user_id))
    db.close()

    return jsonify({
        'token': token,
        'user': {
            'id': str(user_id),
            'username': username,
            'name': name,
        }
    }), 201


@auth_bp.route('/me', methods=['GET'])
def me():
    from flask_jwt_extended import get_jwt_identity
    user_id = get_jwt_identity()
    db = get_db()
    user = db.execute(
        "SELECT id, username, name, created_at FROM users WHERE id = %s",
        (user_id,)
    ).fetchone()
    db.close()
    if user is None:
        return jsonify({'error': 'User not found'}), 404
    return jsonify({'user': dict(user)}), 200
