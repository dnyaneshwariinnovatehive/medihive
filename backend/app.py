from flask import Flask
from flask_jwt_extended import JWTManager
from flask_cors import CORS
from config import SECRET_KEY, JWT_SECRET_KEY, JWT_ACCESS_TOKEN_EXPIRES
from database import init_db

from routes.auth import auth_bp
from routes.patients import patients_bp
from routes.opd import opd_bp
from routes.appointments import appointments_bp
from routes.sync import sync_bp


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

    @app.route('/api/health', methods=['GET'])
    def health():
        return {'status': 'ok', 'version': '1.0.0'}

    return app


if __name__ == '__main__':
    init_db()
    app = create_app()
    app.run(host='0.0.0.0', port=5000, debug=True)
