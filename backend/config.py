import os

BASE_DIR = os.path.dirname(os.path.abspath(__file__))

SECRET_KEY = os.environ.get('SECRET_KEY', 'medihive-secret-key-change-in-production')
JWT_SECRET_KEY = os.environ.get('JWT_SECRET_KEY', 'medihive-jwt-secret-change-in-production')
JWT_ACCESS_TOKEN_EXPIRES = 86400  # 24 hours

DATABASE_PATH = os.path.join(BASE_DIR, 'medihive.db')
