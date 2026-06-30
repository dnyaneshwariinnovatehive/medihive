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
  All images upload directly into the 'MediHive Images' root folder.
  No subfolders are created — filenames are prefixed with OPD ID to
  avoid collisions (e.g. R001_image_1.jpeg).
"""

import io
import json
from pathlib import Path

from google.oauth2.credentials import Credentials
from google.auth.transport.requests import Request
from googleapiclient.discovery import build
from googleapiclient.http import MediaFileUpload, MediaIoBaseUpload
from googleapiclient.errors import HttpError

from config import (
    DRIVE_ROOT_FOLDER_ID,
    DRIVE_TOKEN_PATH,
    DRIVE_TOKEN_JSON
)
from services.log_service import get_logger

logger = get_logger(__name__)

SCOPES = ["https://www.googleapis.com/auth/drive"]


def get_drive_service():
    """
    Load personal OAuth token and return Drive API client.
    Credentials can come from DRIVE_TOKEN_JSON env var (cloud) or drive_token.json file (local).
    Token auto-refreshes when expired — no manual action needed.
    """
    token_path = Path(DRIVE_TOKEN_PATH)

    if DRIVE_TOKEN_JSON:
        logger.info("Loading Drive token from DRIVE_TOKEN_JSON env var")
        info = json.loads(DRIVE_TOKEN_JSON)
        creds = Credentials.from_authorized_user_info(info, SCOPES)
    else:
        if not token_path.exists():
            raise FileNotFoundError(
                f"drive_token.json not found at: {DRIVE_TOKEN_PATH}\n"
                "Run once from your project root:\n"
                "  python generate_drive_token.py"
            )
        creds = Credentials.from_authorized_user_file(str(token_path), SCOPES)

    # Auto-refresh if expired
    if not creds.valid:
        if creds.expired and creds.refresh_token:
            logger.info("OAuth token expired — refreshing...")
            creds.refresh(Request())
            token_str = creds.to_json()
            if DRIVE_TOKEN_JSON:
                pass  # Can't persist env var, logging is fine
            else:
                with open(str(token_path), "w", encoding="utf-8") as f:
                    f.write(token_str)
                logger.info("Token refreshed and saved.")
        else:
            raise RuntimeError(
                "OAuth token is invalid and cannot be refreshed.\n"
                "Run again: python generate_drive_token.py"
            )

    return build("drive", "v3", credentials=creds)


def check_existing_drive_files(opd_id, visit_date, expected_count):
    """
    Check if OPD images already exist in the root 'MediHive Images' folder.
    Returns list of public URLs if enough files found.
    Returns empty list if none or fewer files found.
    """
    if not DRIVE_ROOT_FOLDER_ID:
        return []

    service = get_drive_service()

    query = (
        f"name contains '{opd_id}' "
        f"and '{DRIVE_ROOT_FOLDER_ID}' in parents "
        f"and trashed=false"
    )
    response = service.files().list(
        q=query,
        fields="files(id, name)"
    ).execute()
    existing_files = response.get("files", [])

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
    Upload all images for one OPD visit to the existing 'MediHive Images' folder.
    No subfolders are created — all images go directly into the root folder.
    Returns list of public view URLs in same order as image_records.
    """
    if not DRIVE_ROOT_FOLDER_ID:
        raise ValueError(
            "DRIVE_ROOT_FOLDER_ID is empty in config.py\n"
            "Open your MediHive Images folder in Drive, copy the ID from the URL."
        )

    logger.info(
        "Starting Drive upload: OPD=%s root_folder=%s",
        opd_id, DRIVE_ROOT_FOLDER_ID
    )

    service = get_drive_service()
    uploaded_links = []

    for image in image_records:
        local_path = Path(image.file_path)

        if not local_path.exists():
            logger.warning("Image missing on disk: %s", local_path)
            continue

        try:
            # Prefix filename with OPD ID to avoid name collisions in flat folder
            safe_name = f"{opd_id}_{local_path.name}"
            logger.info("Uploading: %s", safe_name)

            media = MediaFileUpload(str(local_path), resumable=True)

            uploaded = service.files().create(
                body={
                    "name": safe_name,
                    "parents": [DRIVE_ROOT_FOLDER_ID]
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

            logger.info("Uploaded '%s' -> %s", safe_name, public_url)

        except HttpError as e:
            logger.error("Drive upload error for '%s': %s", local_path.name, e)
            raise

    logger.info(
        "Drive upload complete: %d/%d image(s) for OPD %s",
        len(uploaded_links), len(image_records), opd_id
    )

    return uploaded_links


def upload_image_fileobj_to_drive(opd_id, file_storage, index):
    """
    Upload a single image from a Flask FileStorage object directly to Drive.
    Saves to a temp file first (required by Google API), uploads, then deletes.
    Returns the public Drive URL.

    This function is cloud-compatible — it does not require a permanent
    local storage directory.
    """
    import tempfile
    import os

    service = get_drive_service()
    filename = file_storage.filename or f"image_{index}.jpg"
    safe_name = f"{opd_id}_{index:02d}_{filename}"

    # Save to temp file, upload, then delete
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=os.path.splitext(filename)[1] or '.jpg')
    try:
        file_storage.save(tmp.name)
        tmp.close()

        media = MediaFileUpload(tmp.name, resumable=True)
        uploaded = service.files().create(
            body={"name": safe_name, "parents": [DRIVE_ROOT_FOLDER_ID]},
            media_body=media,
            fields="id"
        ).execute()

        file_id = uploaded["id"]
        service.permissions().create(
            fileId=file_id,
            body={"type": "anyone", "role": "reader"}
        ).execute()

        public_url = f"https://drive.google.com/file/d/{file_id}/view"
        logger.info("Uploaded '%s' -> %s", safe_name, public_url)
        return public_url
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)