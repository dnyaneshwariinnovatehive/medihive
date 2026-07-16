import os
from flask import Flask
from flask_jwt_extended import JWTManager
from flask_cors import CORS
from config import SECRET_KEY, JWT_SECRET_KEY, JWT_ACCESS_TOKEN_EXPIRES
from services.log_service import get_logger

from routes.auth import auth_bp
from routes.patients import patients_bp
from routes.opd import opd_bp
from routes.appointments import appointments_bp
from routes.sync import sync_bp
from routes.fcm import fcm_bp
from routes.whatsapp import whatsapp_bp
from routes.cloud import cloud_bp, sync_cloud_bp, device_bp

logger = get_logger(__name__)


def create_app():
    app = Flask(__name__)
    CORS(app)

    app.config['SECRET_KEY'] = SECRET_KEY
    app.config['JWT_SECRET_KEY'] = JWT_SECRET_KEY
    app.config['JWT_ACCESS_TOKEN_EXPIRES'] = JWT_ACCESS_TOKEN_EXPIRES

    JWTManager(app)

    app.register_blueprint(auth_bp, url_prefix='/api/auth')
    app.register_blueprint(patients_bp, url_prefix='/api/patients')
    app.register_blueprint(opd_bp, url_prefix='/api/opd')
    app.register_blueprint(appointments_bp, url_prefix='/api/appointments')
    app.register_blueprint(sync_bp, url_prefix='/api/sync')
    app.register_blueprint(fcm_bp, url_prefix='/api/fcm')
    app.register_blueprint(whatsapp_bp, url_prefix='/api/whatsapp')
    app.register_blueprint(cloud_bp, url_prefix='/api/cloud')
    app.register_blueprint(sync_cloud_bp, url_prefix='/api/sync')
    app.register_blueprint(device_bp, url_prefix='/api/device')

    @app.route('/api/health', methods=['GET'])
    def health():
        return {'status': 'ok', 'version': '1.0.0'}

    @app.route('/', methods=['GET'])
    def root():
        return {
            'message': 'MediHive Backend Running',
            'health': '/api/health'
        }

    @app.route('/debug-users', methods=['GET'])
    def debug_users():
        from database import get_db

        db = get_db()
        try:
            rows = db.execute(
                "SELECT id, username, name, created_at FROM users ORDER BY id"
            ).fetchall()
            return {'users': [dict(row) for row in rows]}
        finally:
            db.close()

    @app.route('/debug-sync', methods=['GET'])
    def debug_sync():
        from database import get_db

        db = get_db()
        try:
            patients = db.execute("SELECT COUNT(*) AS count FROM patients").fetchone()
            opd_visits = db.execute("SELECT COUNT(*) AS count FROM opd_visits").fetchone()
            recent_opd = db.execute(
                """
                SELECT id, patient_id, visit_datetime
                FROM opd_visits
                ORDER BY created_at DESC
                LIMIT 10
                """
            ).fetchall()
            return {
                'patients_count': patients['count'] if patients else 0,
                'opd_visits_count': opd_visits['count'] if opd_visits else 0,
                'recent_opd_records': [dict(row) for row in recent_opd],
            }
        finally:
            db.close()

    @app.route('/debug-google', methods=['GET'])
    def debug_google():
        import os
        from config import (
            DRIVE_ROOT_FOLDER_ID,
            DRIVE_TOKEN_JSON,
            GOOGLE_CREDENTIALS_JSON,
            GOOGLE_SHEET_ID,
            IS_CLOUD,
        )

        result = {
            'is_cloud': IS_CLOUD,
            'google_sheet_id_set': bool(GOOGLE_SHEET_ID),
            'google_credentials_json_set': bool(GOOGLE_CREDENTIALS_JSON),
            'drive_root_folder_id_set': bool(DRIVE_ROOT_FOLDER_ID),
            'drive_token_json_set': bool(DRIVE_TOKEN_JSON),
            'medihive_cloud_env': os.environ.get('MEDIHIVE_CLOUD', ''),
            'sheet_access': {'ok': False},
            'drive_folder_access': {'ok': False},
        }

        try:
            from desktop_google.sheets_service import validate_sheet_access

            spreadsheet = validate_sheet_access()
            result['sheet_access'] = {
                'ok': True,
                'title': spreadsheet.title,
            }
        except Exception as e:
            result['sheet_access'] = {
                'ok': False,
                'error': str(e),
            }

        try:
            from desktop_google.drive_service import get_drive_service

            service = get_drive_service()
            folder = service.files().get(
                fileId=DRIVE_ROOT_FOLDER_ID,
                fields='id,name,mimeType,trashed',
            ).execute()
            result['drive_folder_access'] = {
                'ok': True,
                'name': folder.get('name'),
                'mime_type': folder.get('mimeType'),
                'trashed': folder.get('trashed'),
            }
        except Exception as e:
            result['drive_folder_access'] = {
                'ok': False,
                'error': str(e),
            }

        return result

    return app


def initialize_google_services():
    """
    Run startup validation for Google Sheets and Drive ONCE.
    This verifies the existing sheet and folder are accessible
    before the server starts accepting requests.
    If validation fails, a clear error is logged so the admin
    can fix permissions — no new sheet or folder is ever created.
    """
    try:
        from desktop_google.sheets_service import validate_sheet_access, validate_drive_folder_access
        validate_sheet_access()
        validate_drive_folder_access()
        logger.info("Google setup validation PASSED — sheet and folder are accessible")
    except ImportError as e:
        logger.warning("Google validation dependencies not available: %s", e)
    except RuntimeError as e:
        logger.critical(
            "GOOGLE SETUP VALIDATION FAILED — sync will NOT work:\n%s\n\n"
            "Fix: Grant the service account EDITOR access to the sheet, "
            "then restart the server.",
            e
        )
    except Exception as e:
        logger.critical("Google setup validation error: %s", e)


app = create_app()

from database import init_db
init_db()

if __name__ == '__main__':
    port = int(os.environ.get("PORT", 8080))
    app.run(
        host='0.0.0.0',
        port=port,
        debug=False
    )
