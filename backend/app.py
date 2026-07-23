import os
from flask import Flask
from flask_jwt_extended import JWTManager
from flask_cors import CORS
from config import SECRET_KEY, JWT_SECRET_KEY, JWT_ACCESS_TOKEN_EXPIRES
from services.log_service import get_logger

from routes.auth import auth_bp
from routes.patients import patients_bp
from routes.opd import opd_bp
from routes.sync import sync_bp, cloud_bp
from routes.whatsapp import whatsapp_bp
from routes.calendar_notes import calendar_notes_bp
from routes.clinic_settings import clinic_settings_bp
from routes.medicines import medicines_bp
from routes.symptoms import symptoms_bp

logger = get_logger(__name__)


def create_app():
    app = Flask(__name__)
    CORS(app)

    app.config['SECRET_KEY'] = SECRET_KEY
    app.config['JWT_SECRET_KEY'] = JWT_SECRET_KEY
    app.config['JWT_ACCESS_TOKEN_EXPIRES'] = JWT_ACCESS_TOKEN_EXPIRES

    JWTManager(app)

    from database import teardown_db
    app.teardown_appcontext(teardown_db)

    app.register_blueprint(auth_bp, url_prefix='/api/auth')
    app.register_blueprint(patients_bp, url_prefix='/api/patients')
    app.register_blueprint(opd_bp, url_prefix='/api/opd')
    app.register_blueprint(sync_bp, url_prefix='/api/sync')
    app.register_blueprint(cloud_bp, url_prefix='/api/cloud')
    app.register_blueprint(whatsapp_bp, url_prefix='/api/whatsapp')
    app.register_blueprint(calendar_notes_bp, url_prefix='/api/calendar-notes')
    app.register_blueprint(clinic_settings_bp, url_prefix='/api/clinic-settings')
    app.register_blueprint(medicines_bp, url_prefix='/api/medicines')
    app.register_blueprint(symptoms_bp, url_prefix='/api/symptoms')

    @app.route('/api/health', methods=['GET'])
    def health():
        return {'status': 'ok', 'version': '1.0.0'}

    @app.route('/api/fcm/token', methods=['POST'])
    def fcm_token():
        return {'message': 'ok'}, 200

    @app.route('/', methods=['GET'])
    def root():
        return {
            'message': 'MediHive Backend Running',
            'health': '/api/health'
        }

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
        from sheets_utils import validate_sheet_access, validate_drive_folder_access
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

# Lazy initialize Google services validation
initialize_google_services()

if __name__ == '__main__':
    port = int(os.environ.get("PORT", 8080))
    app.run(
        host='0.0.0.0',
        port=port,
        debug=False
    )
