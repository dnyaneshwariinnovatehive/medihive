import shutil
from datetime import datetime
from pathlib import Path

from backend.config import IMAGE_STORAGE_PATH
from backend.models.patient_images import PatientImage
from backend.services.log_service import get_logger

logger = get_logger(__name__)


def save_patient_images(opd_visit, image_files, session):
    """
    Save patient images to local disk and create DB records.
    Drive upload happens later via background sync_service.
    """

    if not image_files:
        return []

    saved_paths = []

    # =====================================================
    # CREATE OPD FOLDER LOCALLY
    # =====================================================
    opd_folder = Path(IMAGE_STORAGE_PATH) / opd_visit.opd_id
    opd_folder.mkdir(parents=True, exist_ok=True)

    logger.info(f"Saving images for OPD {opd_visit.opd_id} to {opd_folder}")

    image_records = []

    try:
        for index, image in enumerate(image_files, start=1):

            filename = getattr(image, "filename", f"image_{index}")
            ext = Path(filename).suffix or ".jpg"
            file_path = opd_folder / f"image_{index}{ext}"

            try:
                image.seek(0)
            except Exception:
                pass

            # Save image to local disk
            with open(file_path, "wb") as f:
                f.write(image.read())

            logger.info(f"Saved image locally: {file_path}")

            # Create DB record — drive_url is null until sync runs
            image_record = PatientImage(
                patient_id=opd_visit.patient_id,
                opd_visit_id=opd_visit.id,
                file_path=str(file_path),
                sync_status="PENDING",
                uploaded_at=datetime.now()
            )

            session.add(image_record)
            image_records.append(image_record)
            saved_paths.append(file_path)

        # Flush so image IDs are available before sync_queue commit
        session.flush()

        logger.info(
            f"Saved {len(saved_paths)} image(s) locally for OPD {opd_visit.opd_id}"
        )

        return saved_paths

    except Exception as e:
        # Remove local folder on failure so no partial files remain
        if opd_folder.exists():
            shutil.rmtree(opd_folder)
        logger.error(f"Image save failed for OPD {opd_visit.opd_id}: {e}")
        raise RuntimeError(f"Image save failed: {str(e)}")