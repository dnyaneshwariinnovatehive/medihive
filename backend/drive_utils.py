"""Google Drive utility functions for MediHive.

Extracted from desktop_google/drive_service.py.
Uses GoogleAuthService for centralized credential management.
"""

import io
from pathlib import Path

from googleapiclient.discovery import build
from googleapiclient.http import MediaFileUpload, MediaIoBaseUpload
from googleapiclient.errors import HttpError

from config import DRIVE_ROOT_FOLDER_ID, DRIVE_TOKEN_PATH
from services.google_auth_service import GoogleAuthService
from services.log_service import get_logger

logger = get_logger(__name__)

SCOPES = ["https://www.googleapis.com/auth/drive"]


def get_drive_service():
    auth = GoogleAuthService(DRIVE_TOKEN_PATH)
    creds = auth.get_credentials()
    if creds is None:
        raise RuntimeError(
            "Google Drive credentials not available. "
            "Run utils/generate_drive_token.py first."
        )
    return build("drive", "v3", credentials=creds)


def check_existing_drive_files(opd_id, visit_date, expected_count):
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
    drive_root_folder_id = DRIVE_ROOT_FOLDER_ID
    if not drive_root_folder_id:
        raise ValueError("DRIVE_ROOT_FOLDER_ID is empty")

    logger.info(
        "DRIVE_UPLOAD: Starting batch upload: OPD=%s root_folder=%s record_count=%d",
        opd_id, drive_root_folder_id, len(image_records)
    )

    service = get_drive_service()
    uploaded_links = []

    for idx, image in enumerate(image_records, 1):
        local_path = Path(image.file_path)

        if not local_path.exists():
            logger.warning("DRIVE_UPLOAD: Image missing on disk: %s (index=%d)", local_path, idx)
            continue

        file_size = local_path.stat().st_size
        logger.info("DRIVE_UPLOAD: Starting file upload: OPD=%s index=%d path=%s size=%d bytes",
                    opd_id, idx, local_path, file_size)

        try:
            safe_name = f"{opd_id}_{local_path.name}"
            logger.info("DRIVE_UPLOAD: Creating Drive file: name=%s", safe_name)

            media = MediaFileUpload(str(local_path), resumable=True)

            uploaded = service.files().create(
                body={
                    "name": safe_name,
                    "parents": [drive_root_folder_id]
                },
                media_body=media,
                fields="id"
            ).execute()

            file_id = uploaded["id"]
            logger.info("DRIVE_UPLOAD: File created: file_id=%s name=%s", file_id, safe_name)

            service.permissions().create(
                fileId=file_id,
                body={"type": "anyone", "role": "reader"}
            ).execute()
            logger.info("DRIVE_UPLOAD: Public permission set for file_id=%s", file_id)

            public_url = f"https://drive.google.com/file/d/{file_id}/view"
            uploaded_links.append(public_url)

            logger.info("DRIVE_UPLOAD: SUCCESS: index=%d name=%s url=%s", idx, safe_name, public_url)

        except HttpError as e:
            logger.error("DRIVE_UPLOAD: FAILED: index=%d name=%s error=%s",
                        idx, local_path.name, e)
            raise

    logger.info(
        "DRIVE_UPLOAD: Batch complete: %d/%d image(s) uploaded for OPD %s",
        len(uploaded_links), len(image_records), opd_id
    )

    return uploaded_links


def upload_image_fileobj_to_drive(opd_id, file_storage, index):
    logger.info("DRIVE_UPLOAD_FILEOBJ: START: OPD=%s index=%d filename=%s content_type=%s",
                opd_id, index, file_storage.filename, file_storage.content_type)

    content = file_storage.read()
    content_len = len(content)
    logger.info("DRIVE_UPLOAD_FILEOBJ: Read file content: OPD=%s index=%d size=%d bytes",
                opd_id, index, content_len)

    if content_len == 0:
        logger.error("DRIVE_UPLOAD_FILEOBJ: Empty file content for OPD=%s index=%d", opd_id, index)
        return None

    file_io = io.BytesIO(content)

    service = get_drive_service()
    filename = file_storage.filename or f"image_{index}.jpg"
    safe_name = f"{opd_id}_{index:02d}_{filename}"
    logger.info("DRIVE_UPLOAD_FILEOBJ: safe_name=%s size=%d", safe_name, content_len)

    mimetype = file_storage.content_type or 'image/jpeg'
    media = MediaIoBaseUpload(file_io, mimetype=mimetype, resumable=True)

    logger.info("DRIVE_UPLOAD_FILEOBJ: Calling files().create() for %s", safe_name)
    try:
        uploaded = service.files().create(
            body={"name": safe_name, "parents": [DRIVE_ROOT_FOLDER_ID]},
            media_body=media,
            fields="id"
        ).execute()
    except HttpError as e:
        logger.error("DRIVE_UPLOAD_FILEOBJ: files().create() FAILED: OPD=%s index=%d error=%s",
                     opd_id, index, e)
        raise
    except Exception as e:
        logger.error("DRIVE_UPLOAD_FILEOBJ: files().create() FAILED: OPD=%s index=%d error=%s",
                     opd_id, index, e)
        raise

    file_id = uploaded["id"]
    logger.info("DRIVE_UPLOAD_FILEOBJ: files().create() SUCCESS: file_id=%s", file_id)

    logger.info("DRIVE_UPLOAD_FILEOBJ: Setting public permissions for file_id=%s", file_id)
    try:
        service.permissions().create(
            fileId=file_id,
            body={"type": "anyone", "role": "reader"}
        ).execute()
        logger.info("DRIVE_UPLOAD_FILEOBJ: Permission set SUCCESS for file_id=%s", file_id)
    except HttpError as e:
        logger.error("DRIVE_UPLOAD_FILEOBJ: Permission set FAILED for file_id=%s: %s", file_id, e)
        raise

    public_url = f"https://drive.google.com/file/d/{file_id}/view"
    logger.info("DRIVE_UPLOAD_FILEOBJ: COMPLETE: OPD=%s index=%d url=%s", opd_id, index, public_url)
    return public_url
