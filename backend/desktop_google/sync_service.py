import time
import traceback
from datetime import datetime

from backend.database.db import SessionLocal
from backend.models.sync_queue import SyncQueue
from backend.models.opd_visits import OPDVisit
from backend.models.patients import Patient
from backend.models.patient_images import PatientImage
from backend.models.calendar_notes import CalendarNote
from backend.services.drive_service import upload_images_to_drive
from backend.services.sheets_service import append_row_to_sheet, upsert_calendar_note_to_sheet
from backend.services.log_service import get_logger

logger = get_logger(__name__)

SYNC_INTERVAL_SECONDS = 60
MAX_RETRY_COUNT = 5


# ─────────────────────────────────────────────
# OPD — DRIVE UPLOAD
# ─────────────────────────────────────────────
def _upload_images(session, opd_visit, images):
    if not images:
        return []

    already_uploaded = [img for img in images if img.drive_url]
    pending_upload   = [img for img in images if not img.drive_url]

    if already_uploaded:
        logger.info(
            "%d image(s) already have Drive URLs for OPD %s",
            len(already_uploaded), opd_visit.opd_id
        )

    if not pending_upload:
        return [img.drive_url for img in images if img.drive_url]

    logger.info(
        "Uploading %d image(s) to Drive for OPD %s",
        len(pending_upload), opd_visit.opd_id
    )

    try:
        uploaded_urls = upload_images_to_drive(
            opd_id=opd_visit.opd_id,
            image_records=pending_upload,
            visit_date=opd_visit.visit_datetime
        )

        for image, url in zip(pending_upload, uploaded_urls):
            image.drive_url = url
            image.sync_status = "SYNCED"

        session.commit()
        logger.info("Drive upload done. %d URL(s) saved.", len(uploaded_urls))

        return [img.drive_url for img in images if img.drive_url]

    except Exception as drive_error:
        session.rollback()
        logger.warning(
            "Drive upload failed for OPD %s (will still write text to Sheets): %s",
            opd_visit.opd_id, drive_error
        )
        return [img.drive_url for img in already_uploaded]


# ─────────────────────────────────────────────
# OPD — SHEETS WRITE
# ─────────────────────────────────────────────
def _write_opd_to_sheets(opd_visit, patient, image_links):

    logger.info("medicines value at sync time: %r", opd_visit.medicines)  # ← ADD THIS

    logger.info(
        "Writing to Sheets: OPD %s | %d image link(s)",
        opd_visit.opd_id, len(image_links)
    )

    append_row_to_sheet(
        opd_id=opd_visit.opd_id,
        patient_id=f"P{patient.id:04d}",  
        patient_name=patient.full_name,
        mobile=patient.mobile_number,
        
        gender=patient.gender,
        dob=patient.dob,
        age=patient.age,
        blood_group=patient.blood_group,
        address=patient.address,
        visit_date=opd_visit.visit_datetime,
        opd_type=opd_visit.opd_type,
        charge_type=opd_visit.charge_type,
        diagnosis=opd_visit.diagnosis,
        symptoms=opd_visit.symptoms,
        clinical_notes=opd_visit.clinical_notes,
        panchakarma_notes=opd_visit.panchakarma_notes,

                medicines=opd_visit.medicines,

        consultation_fee=opd_visit.consultation_fee,
        medicine_fee=opd_visit.medicine_fee,
        panchakarma_fee=opd_visit.panchakarma_fee,
        total_fee=opd_visit.total_fee,
        discount_type=opd_visit.discount_type,
        discount_value=opd_visit.discount_value,
        payment_mode=opd_visit.payment_mode,
        next_visit_date=opd_visit.next_visit_date,
        followup_status=opd_visit.followup_status,
        image_links=image_links
    )

    logger.info("Sheets row written for OPD %s", opd_visit.opd_id)


# ─────────────────────────────────────────────
# OPD SYNC QUEUE
# ─────────────────────────────────────────────
def _process_opd_queue(session):
    pending_items = (
        session.query(SyncQueue)
        .filter(
            SyncQueue.status == "PENDING",
            SyncQueue.retry_count < MAX_RETRY_COUNT,
            SyncQueue.entity_type == "OPD_VISIT"
        )
        .order_by(SyncQueue.created_at.asc())
        .all()
    )

    logger.info("Found %d PENDING OPD item(s)", len(pending_items))

    for item in pending_items:
        try:
            logger.info("Syncing OPD entity_id=%s", item.entity_id)

            opd_visit = session.get(OPDVisit, int(item.entity_id))
            if not opd_visit:
                raise ValueError("OPD visit not found: id=%s" % item.entity_id)

            patient = session.get(Patient, opd_visit.patient_id)
            if not patient:
                raise ValueError("Patient not found: id=%s" % opd_visit.patient_id)

            images = (
                session.query(PatientImage)
                .filter(PatientImage.opd_visit_id == opd_visit.id)
                .all()
            )
            logger.info("Found %d image(s) for OPD %s", len(images), opd_visit.opd_id)

            image_links = _upload_images(session, opd_visit, images)
            _write_opd_to_sheets(opd_visit, patient, image_links)

            item.status = "SYNCED"
            item.last_attempt = datetime.utcnow()
            item.last_error = None
            session.commit()

            logger.info("Sync SUCCESS for OPD %s", opd_visit.opd_id)

        except Exception as e:
            session.rollback()
            item.retry_count += 1
            item.last_attempt = datetime.utcnow()
            item.last_error = str(e)[:500]
            if item.retry_count >= MAX_RETRY_COUNT:
                item.status = "FAILED"
                logger.error(
                    "Sync FAILED permanently for entity_id=%s: %s",
                    item.entity_id, e
                )
            else:
                logger.warning(
                    "Sync error for entity_id=%s (retry %d/%d): %s",
                    item.entity_id, item.retry_count, MAX_RETRY_COUNT, e
                )
            session.commit()


# ─────────────────────────────────────────────
# OPD UPDATE SYNC QUEUE  ← NEW, don't touch existing logic above
# Handles rows that were edited (not newly created)
# Uses update_opd_row_in_sheet instead of append
# ─────────────────────────────────────────────
def _process_opd_update_queue(session):
    from backend.services.sheets_service import update_opd_row_in_sheet

    pending_items = (
        session.query(SyncQueue)
        .filter(
            SyncQueue.status == "PENDING",
            SyncQueue.entity_type == "OPD_UPDATE"
        )
        .order_by(SyncQueue.created_at.asc())
        .all()
    )

    logger.info("Found %d PENDING OPD_UPDATE item(s)", len(pending_items))

    for item in pending_items:
        try:
            logger.info("Syncing OPD_UPDATE entity_id=%s", item.entity_id)

            # ── Upload any pending images to Drive first ──────────
            opd_visit = session.query(OPDVisit).filter(
                OPDVisit.opd_id == item.entity_id
            ).first()

            if opd_visit:
                images = (
                    session.query(PatientImage)
                    .filter(PatientImage.opd_visit_id == opd_visit.id)
                    .all()
                )
                if images:
                    logger.info(
                        "Found %d image(s) for OPD_UPDATE %s",
                        len(images), item.entity_id
                    )
                    _upload_images(session, opd_visit, images)
            # ─────────────────────────────────────────────────────

            # ── Update sheet row with latest data + drive links ──
            update_opd_row_in_sheet(item.entity_id)

            item.status = "SYNCED"
            item.last_attempt = datetime.utcnow()
            item.last_error = None
            session.commit()

            logger.info("OPD_UPDATE sync SUCCESS for %s", item.entity_id)

        except Exception as e:
            session.rollback()
            item.retry_count += 1
            item.last_attempt = datetime.utcnow()
            item.last_error = str(e)[:500]
            if item.retry_count >= MAX_RETRY_COUNT:
                item.status = "FAILED"
                logger.error(
                    "OPD_UPDATE sync FAILED permanently for %s: %s",
                    item.entity_id, e
                )
            else:
                logger.warning(
                    "OPD_UPDATE sync error for %s (retry %d/%d): %s",
                    item.entity_id, item.retry_count, MAX_RETRY_COUNT, e
                )
            session.commit()





# ─────────────────────────────────────────────
# CALENDAR NOTES SYNC
# Runs every cycle — syncs ALL calendar notes
# to the calendar_notes tab (upsert by date)
# ─────────────────────────────────────────────
def _process_calendar_notes(session):
    try:
        notes = session.query(CalendarNote).order_by(CalendarNote.note_date.asc()).all()

        if not notes:
            logger.info("No calendar notes to sync")
            return

        logger.info("Syncing %d calendar note(s) to Sheets", len(notes))

        for note in notes:
            try:
                upsert_calendar_note_to_sheet(
                    note_date=note.note_date,
                    note_text=note.note_text
                )
            except Exception as e:
                logger.warning(
                    "Failed to sync calendar note for date %s: %s",
                    note.note_date, e
                )

        logger.info("Calendar notes sync complete")

    except Exception as e:
        logger.error("Calendar notes sync error: %s", e)


# ─────────────────────────────────────────────
# MAIN LOOP
# ─────────────────────────────────────────────
def process_sync_queue():
    logger.info("process_sync_queue running...")
    session = SessionLocal()

    try:
        # Sync OPD visits
        _process_opd_queue(session)

        logger.info("About to call _process_opd_update_queue")  # ← ADD THIS
        _process_opd_update_queue(session)

        # Sync calendar notes
        _process_calendar_notes(session)

    finally:
        session.close()


def start_background_sync():
    logger.info("Background sync service started")
    while True:
        try:
            process_sync_queue()
        except Exception:
            logger.error("Sync loop crashed:\n%s", traceback.format_exc())
        time.sleep(SYNC_INTERVAL_SECONDS)

