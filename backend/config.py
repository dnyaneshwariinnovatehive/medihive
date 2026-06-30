import os
import tempfile

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
IS_CLOUD = os.environ.get('MEDIHIVE_CLOUD', '').lower() in ('1', 'true', 'yes')

SECRET_KEY = os.environ.get('SECRET_KEY', 'medihive-secret-key-change-in-production')
JWT_SECRET_KEY = os.environ.get('JWT_SECRET_KEY', 'medihive-jwt-secret-change-in-production')
JWT_ACCESS_TOKEN_EXPIRES = 86400  # 24 hours

if IS_CLOUD:
    DATABASE_PATH = os.environ.get(
        'DATABASE_PATH',
        os.path.join(BASE_DIR, 'medihive.db')
    )
else:
    DATABASE_PATH = os.path.join(BASE_DIR, 'medihive.db')

# WhatsApp Cloud API
WHATSAPP_TOKEN = os.environ.get('WHATSAPP_TOKEN', '')
WHATSAPP_PHONE_NUMBER_ID = os.environ.get('WHATSAPP_PHONE_NUMBER_ID', '')
WHATSAPP_API_VERSION = 'v22.0'
WHATSAPP_API_BASE = f'https://graph.facebook.com/{WHATSAPP_API_VERSION}'

# ─────────────────────────────────────────────────────────
# ⚠  SINGLE SOURCE OF TRUTH — DO NOT CHANGE UNLESS ABSOLUTELY NECESSARY
# ─────────────────────────────────────────────────────────
# These IDs are the permanent identifiers for the existing
# Google Sheet and Drive folder. The system NEVER creates
# new ones — it ALWAYS reuses these.
#
# Google Sheet ID (inside "MediHive - Patient Records" folder):
GOOGLE_SHEET_ID = os.environ.get(
    'GOOGLE_SHEET_ID',
    '1NECj89gjbga45i5ZlwwHU04l107vmKbQGrEJLPQBmpY'
)
#
# Google Drive folder ID for OPD images ("MediHive Images"):
DRIVE_ROOT_FOLDER_ID = os.environ.get(
    'DRIVE_ROOT_FOLDER_ID',
    '1Ogx1JHYBBSLTx4glL4-yhcGPLOdBN0GI'
)
# ─────────────────────────────────────────────────────────

# Persisted sheet ID file (backup copy of GOOGLE_SHEET_ID)
if IS_CLOUD:
    SHEET_ID_FILE = os.path.join(BASE_DIR, 'sheet_id.json')
else:
    SHEET_ID_FILE = os.path.join(BASE_DIR, 'sheet_id.json')

# Service Account Credentials
GOOGLE_CREDENTIALS_FILE = os.environ.get(
    'GOOGLE_CREDENTIALS_FILE',
    os.path.join(BASE_DIR, '..', 'credentials', 'credentials.json')
)
# Read credentials JSON directly from env var (used on Render/Railway where file upload is unavailable)
GOOGLE_CREDENTIALS_JSON = os.environ.get('GOOGLE_CREDENTIALS_JSON', '')

GOOGLE_CREDENTIALS_PATH = GOOGLE_CREDENTIALS_FILE
GOOGLE_SHEET_NAME = os.environ.get('GOOGLE_SHEET_NAME', "MediHive - Patient Records")

# Google Drive OAuth Token
DRIVE_TOKEN_PATH = os.environ.get(
    'DRIVE_TOKEN_PATH',
    os.path.join(BASE_DIR, '..', 'drive_token.json')
)
DRIVE_TOKEN_JSON = os.environ.get('DRIVE_TOKEN_JSON', '')

# Image storage: local dir (default) or system temp (cloud)
if IS_CLOUD:
    IMAGE_STORAGE_PATH = os.path.join(tempfile.gettempdir(), 'medihive_images')
else:
    IMAGE_STORAGE_PATH = os.path.join(BASE_DIR, '..', 'storage', 'images')