"""
drive_service.py
================
Uploads patient images to YOUR personal Google Drive using OAuth token.

WHY OAUTH INSTEAD OF SERVICE ACCOUNT:
- Service accounts have 0 storage quota (causes storageQuotaExceeded)
- OAuth token represents YOUR personal Google account
- Files upload into YOUR Drive using YOUR 15GB quota
- No quota errors, no shared drives needed

HOW IT WORKS:
1. One-time: run generate_drive_token.py to authorize
2. Token saved to drive_token.json (path set in config.py as DRIVE_TOKEN_PATH)
3. This service loads that token on every upload
4. Token auto-refreshes — never expires

FOLDER STRUCTURE IN YOUR DRIVE:
  Clinic_Data/
    2026/
      May/
        OPD-20260512-xxxxx/
          image_1.jpeg
"""

from pathlib import Path

from google.oauth2.credentials import Credentials
from google.auth.transport.requests import Request
from googleapiclient.discovery import build
from googleapiclient.http import MediaFileUpload
from googleapiclient.errors import HttpError

from config import (
    DRIVE_ROOT_FOLDER_ID,
    DRIVE_TOKEN_PATH
)
from services.log_service import get_logger

logger = get_logger(__name__)

SCOPES = ["https://www.googleapis.com/auth/drive"]


def get_drive_service():
    """
    Load personal OAuth token from drive_token.json and return Drive API client.
    drive_token.json is created by running: python generate_drive_token.py
    Token auto-refreshes when expired — no manual action needed.
    """
    token_path = Path(DRIVE_TOKEN_PATH)

    if not token_path.exists():
        raise FileNotFoundError(
            f"drive_token.json not found at: {DRIVE_TOKEN_PATH}\n"
            "Run once from your project root:\n"
            "  python generate_drive_token.py"
        )

    # Credentials.from_authorized_user_file reads the JSON token file
    creds = Credentials.from_authorized_user_file(str(token_path), SCOPES)

    # Auto-refresh if expired
    if not creds.valid:
        if creds.expired and creds.refresh_token:
            logger.info("OAuth token expired — refreshing...")
            creds.refresh(Request())
            with open(str(token_path), "w", encoding="utf-8") as f:
                f.write(creds.to_json())
            logger.info("Token refreshed and saved.")
        else:
            raise RuntimeError(
                "OAuth token is invalid and cannot be refreshed.\n"
                "Run again: python generate_drive_token.py"
            )

    return build("drive", "v3", credentials=creds)


def get_or_create_folder(service, name, parent_id):
    """
    Find existing folder or create new one inside parent.
    """
    query = (
        f"name='{name}' "
        f"and mimeType='application/vnd.google-apps.folder' "
        f"and '{parent_id}' in parents "
        f"and trashed=false"
    )

    response = service.files().list(
        q=query,
        fields="files(id, name)"
    ).execute()

    files = response.get("files", [])

    if files:
        folder_id = files[0]["id"]
        logger.info("Found folder '%s' id=%s", name, folder_id)
        return folder_id

    folder = service.files().create(
        body={
            "name": name,
            "mimeType": "application/vnd.google-apps.folder",
            "parents": [parent_id]
        },
        fields="id"
    ).execute()

    folder_id = folder["id"]
    logger.info("Created folder '%s' id=%s", name, folder_id)
    return folder_id


def check_existing_drive_files(opd_id, visit_date, expected_count):
    """
    Check if OPD folder already has files in Drive.
    Returns list of public URLs if folder exists with >= expected_count files.
    Returns empty list if folder doesn't exist or has fewer files.
    """
    if not DRIVE_ROOT_FOLDER_ID:
        return []

    service = get_drive_service()

    year  = visit_date.strftime("%Y")
    month = visit_date.strftime("%b")

    year_folder_id  = get_or_create_folder(service, year,   DRIVE_ROOT_FOLDER_ID)
    month_folder_id = get_or_create_folder(service, month,  year_folder_id)

    query = (
        f"name='{opd_id}' "
        f"and mimeType='application/vnd.google-apps.folder' "
        f"and '{month_folder_id}' in parents "
        f"and trashed=false"
    )
    response = service.files().list(q=query, fields="files(id, name)").execute()
    folders = response.get("files", [])

    if not folders:
        logger.info("No existing Drive folder for OPD %s", opd_id)
        return []

    opd_folder_id = folders[0]["id"]

    files_response = service.files().list(
        q=f"'{opd_folder_id}' in parents and trashed=false",
        fields="files(id, name)"
    ).execute()
    existing_files = files_response.get("files", [])

    if len(existing_files) >= expected_count:
        logger.info(
            "Found %d existing file(s) in Drive for OPD %s, skipping upload",
            len(existing_files), opd_id
        )
        return [
            f"https://drive.google.com/file/d/{f['id']}/view"
            for f in existing_files
        ]

    logger.info(
        "Found %d existing file(s) in Drive for OPD %s, need %d — proceeding with upload",
        len(existing_files), opd_id, expected_count
    )
    return []


def upload_images_to_drive(opd_id, image_records, visit_date):
    """
    Upload all images for one OPD visit to personal Google Drive.
    Returns list of public view URLs in same order as image_records.
    """
    if not DRIVE_ROOT_FOLDER_ID:
        raise ValueError(
            "DRIVE_ROOT_FOLDER_ID is empty in config.py\n"
            "Open your Clinic_Data folder in Drive, copy the ID from the URL."
        )

    logger.info(
        "Starting Drive upload: OPD=%s root_folder=%s",
        opd_id, DRIVE_ROOT_FOLDER_ID
    )

    service = get_drive_service()

    year  = visit_date.strftime("%Y")
    month = visit_date.strftime("%b")

    year_folder_id  = get_or_create_folder(service, year,   DRIVE_ROOT_FOLDER_ID)
    month_folder_id = get_or_create_folder(service, month,  year_folder_id)
    opd_folder_id   = get_or_create_folder(service, opd_id, month_folder_id)

    uploaded_links = []

    for image in image_records:
        local_path = Path(image.file_path)

        if not local_path.exists():
            logger.warning("Image missing on disk: %s", local_path)
            continue

        try:
            logger.info("Uploading: %s", local_path.name)

            media = MediaFileUpload(str(local_path), resumable=True)

            uploaded = service.files().create(
                body={
                    "name": local_path.name,
                    "parents": [opd_folder_id]
                },
                media_body=media,
                fields="id"
            ).execute()

            file_id = uploaded["id"]

            # Make file publicly viewable (anyone with link)
            service.permissions().create(
                fileId=file_id,
                body={"type": "anyone", "role": "reader"}
            ).execute()

            public_url = f"https://drive.google.com/file/d/{file_id}/view"
            uploaded_links.append(public_url)

            logger.info("Uploaded '%s' -> %s", local_path.name, public_url)

        except HttpError as e:
            logger.error("Drive upload error for '%s': %s", local_path.name, e)
            raise

    logger.info(
        "Drive upload complete: %d/%d image(s) for OPD %s",
        len(uploaded_links), len(image_records), opd_id
    )

    return uploaded_links