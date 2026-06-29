from flask import request, jsonify, Blueprint
from backend.services.auth_service import send_otp_email
from backend.services.auth_service import reset_password

auth_bp = Blueprint("auth", __name__, url_prefix="/api/auth")

@auth_bp.route("/send-otp", methods=["POST"])
def send_otp():
    data = request.get_json()
    email = data.get("email")
    response, status = send_otp_email(email)
    return jsonify(response), status

@auth_bp.route("/reset-password", methods=["POST"])
def reset_password_route():
    data = request.get_json()

    email = data.get("email")
    otp = data.get("otp")
    new_password = data.get("newPassword")

    response, status = reset_password(email, otp, new_password)
    return jsonify(response), status