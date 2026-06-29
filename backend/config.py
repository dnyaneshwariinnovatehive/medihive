import os

BASE_DIR = os.path.dirname(os.path.abspath(__file__))

SECRET_KEY = os.environ.get('SECRET_KEY', 'medihive-secret-key-change-in-production')
JWT_SECRET_KEY = os.environ.get('JWT_SECRET_KEY', 'medihive-jwt-secret-change-in-production')
JWT_ACCESS_TOKEN_EXPIRES = 86400  # 24 hours

DATABASE_PATH = os.path.join(BASE_DIR, 'medihive.db')

# WhatsApp Cloud API
WHATSAPP_TOKEN = os.environ.get('WHATSAPP_TOKEN', '')
WHATSAPP_PHONE_NUMBER_ID = os.environ.get('WHATSAPP_PHONE_NUMBER_ID', '')
WHATSAPP_API_VERSION = 'v22.0'
WHATSAPP_API_BASE = f'https://graph.facebook.com/{WHATSAPP_API_VERSION}'

#google 
# Google Sheets
GOOGLE_SHEET_ID = '1NECj89gjbga45i5ZlwwHU04l107vmKbQGrEJLPQBmpY'

# Google Drive
DRIVE_ROOT_FOLDER_ID = '1Ogx1JHYBBSLTx4glL4-yhcGPLOdBN0GI'

# Service Account Credentials
GOOGLE_CREDENTIALS_FILE = os.path.join(
    BASE_DIR,
    '..',
    'credentials',
    'credentials.json'
)

GOOGLE_CREDENTIALS_PATH = GOOGLE_CREDENTIALS_FILE
GOOGLE_SHEET_NAME = "MediHive - Patient Records"
# Google Drive OAuth Token
DRIVE_TOKEN_PATH = os.path.join(
    BASE_DIR,
    '..',
    'drive_token.json'
)

# Local image storage for OPD images
IMAGE_STORAGE_PATH = os.path.join(BASE_DIR, '..', 'storage', 'images')