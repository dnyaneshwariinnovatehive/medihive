from flask import Blueprint, request, jsonify
from models.clinic_setting import ClinicSetting
from services.log_service import get_logger

logger = get_logger(__name__)

clinic_settings_bp = Blueprint('clinic_settings', __name__)


@clinic_settings_bp.route('', methods=['GET'])
def get_settings():
    """Get current clinic settings."""
    settings = ClinicSetting.get_first()
    if not settings:
        return jsonify({'clinic_settings': None}), 200
    return jsonify({'clinic_settings': settings}), 200


@clinic_settings_bp.route('', methods=['PUT'])
def update_settings():
    """Update clinic settings (singleton)."""
    data = request.get_json() or {}
    settings = ClinicSetting.upsert(data)
    return jsonify({'clinic_settings': settings}), 200


@clinic_settings_bp.route('', methods=['POST'])
def create_or_update_settings():
    """Create or update clinic settings (alias for PUT)."""
    data = request.get_json() or {}
    settings = ClinicSetting.upsert(data)
    return jsonify({'clinic_settings': settings}), 200
