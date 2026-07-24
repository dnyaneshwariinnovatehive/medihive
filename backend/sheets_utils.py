"""Google Sheets utility functions for MediHive.

Extracted from desktop_google/sheets_service.py.
Uses centralized config and auth.
"""

import json
import os
from datetime import date, datetime

import gspread
from google.oauth2.service_account import Credentials

from config import GOOGLE_CREDENTIALS_PATH, GOOGLE_CREDENTIALS_JSON, GOOGLE_SHEET_NAME, GOOGLE_SHEET_ID, DRIVE_ROOT_FOLDER_ID
from database import get_db
from services.log_service import get_logger

logger = get_logger(__name__)

SCOPES = [
    "https://www.googleapis.com/auth/spreadsheets",
    "https://www.googleapis.com/auth/drive",
]

OPD_TAB_NAME      = "opd_visits"
CALENDAR_TAB_NAME = "calendar_notes"

HEADERS = [
    "OPD ID", "Patient ID", "Patient Name", "Mobile",
    "Gender", "DOB", "Age", "Blood Group", "Address", "Visit Date",
    "OPD Type", "Charge Type", "Diagnosis", "Symptoms", "Clinical Notes","Panchakarma Notes",
    "Medicines",
    "Consultation Fee", "Medicine Fee", "Panchakarma Fee", "Total Fee",
    "Discount Type", "Discount Value", "Payment Mode",
    "Next Visit Date", "Follow-up Status", "Image Links",
]

HEADER_TO_INDEX = {h: i for i, h in enumerate(HEADERS)}

COLUMN_WIDTHS = [
    180, 120, 220, 130, 110, 110, 70, 110, 260, 150,
    120, 120, 180, 180, 260, 260,
    280,
    130, 120, 140, 110, 110,
    120, 120, 140, 130, 280,
]
CALENDAR_HEADERS = ["Date", "Note"]


def _fmt(value, default="NA"):
    if value is None:
        return default
    if isinstance(value, datetime):
        return value.strftime("%Y-%m-%d %H:%M")
    if isinstance(value, date):
        return value.strftime("%Y-%m-%d")
    if isinstance(value, float):
        return str(int(value)) if value.is_integer() else f"{value:.2f}"
    text = str(value).strip()
    return text if text else default


def _col_letter(n):
    result = ""
    n += 1
    while n:
        n, r = divmod(n - 1, 26)
        result = chr(65 + r) + result
    return result


def _build_row(data: dict) -> list:
    row = ["NA"] * len(HEADERS)
    for header, value in data.items():
        idx = HEADER_TO_INDEX.get(header)
        if idx is not None:
            if isinstance(value, list):
                value = "\n".join(value) if value else None
            row[idx] = _fmt(value)
    return row


# ── Sheet ID persistence ─────────────────────────────

def _load_sheet_id_from_db():
    try:
        db = get_db()
        row = db.execute(
            "SELECT value FROM clinic_settings WHERE key = 'spreadsheet_id'"
        ).fetchone()
        db.close()
        if row and row['value']:
            sid = row['value']
            logger.info("Loaded sheet ID from database: %s", sid)
            return sid
    except Exception as e:
        logger.warning("Could not load sheet ID from database: %s", e)
    return None


def _load_sheet_id():
    sid = _load_sheet_id_from_db()
    if sid:
        return sid
    return None


# ── Google Sheets client ────────────────────────────

def _get_client():
    if GOOGLE_CREDENTIALS_JSON:
        logger.info("Loading credentials from GOOGLE_CREDENTIALS_JSON env var")
        info = json.loads(GOOGLE_CREDENTIALS_JSON)
        creds = Credentials.from_service_account_info(info, scopes=SCOPES)
    else:
        logger.info("Loading credentials from: %s", GOOGLE_CREDENTIALS_PATH)
        if not os.path.exists(GOOGLE_CREDENTIALS_PATH):
            raise FileNotFoundError(
                "credentials.json not found at: %s\n"
                "Set GOOGLE_CREDENTIALS_JSON env var or place the file at the expected path."
                % GOOGLE_CREDENTIALS_PATH
            )
        creds = Credentials.from_service_account_file(
            GOOGLE_CREDENTIALS_PATH, scopes=SCOPES
        )
    return gspread.authorize(creds)


def _open_spreadsheet(client):
    if GOOGLE_SHEET_ID:
        try:
            spreadsheet = client.open_by_key(GOOGLE_SHEET_ID)
            logger.info("Opened spreadsheet by config ID: %s", GOOGLE_SHEET_ID)
            return spreadsheet
        except Exception as e:
            logger.error(
                "Config sheet ID %s from config.py FAILED: %s. "
                "Verify the service account has editor access to this sheet.",
                GOOGLE_SHEET_ID, e
            )

    saved_id = _load_sheet_id()
    if saved_id:
        try:
            spreadsheet = client.open_by_key(saved_id)
            logger.info("Opened spreadsheet by persisted ID: %s", saved_id)
            return spreadsheet
        except Exception as e:
            logger.warning("Persisted sheet ID %s failed: %s", saved_id, e)

    try:
        spreadsheet = client.open(GOOGLE_SHEET_NAME)
        logger.info("Opened spreadsheet by name: %s", GOOGLE_SHEET_NAME)
        return spreadsheet
    except Exception as e:
        logger.warning("Spreadsheet by name '%s' not found: %s", GOOGLE_SHEET_NAME, e)

    raise RuntimeError(
        "Cannot open Google Sheet. "
        "Please verify:\n"
        "  1) GOOGLE_SHEET_ID in config is correct\n"
        "  2) The service account has EDITOR access to this sheet\n"
        "  3) The sheet still exists in Google Drive"
    )


def _get_opd_worksheet(client):
    spreadsheet = _open_spreadsheet(client)

    try:
        ws = spreadsheet.worksheet(OPD_TAB_NAME)
        logger.info("Using existing tab: %s", OPD_TAB_NAME)
        needs_formatting = False
    except gspread.WorksheetNotFound:
        logger.info("Tab '%s' not found — creating", OPD_TAB_NAME)
        ws = spreadsheet.add_worksheet(
            title=OPD_TAB_NAME,
            rows=1000,
            cols=len(HEADERS)
        )
        needs_formatting = True

    existing_headers = ws.row_values(1)
    if existing_headers != HEADERS:
        end_col = _col_letter(len(HEADERS) - 1)
        ws.update(range_name=f"A1:{end_col}1", values=[HEADERS])
        needs_formatting = True
        logger.info("Headers written to tab: %s", OPD_TAB_NAME)

    if needs_formatting:
        logger.info("Applying formatting (first time only)...")
        _apply_opd_formatting(ws)

    return ws


def _apply_opd_formatting(ws):
    sid = ws.id
    requests = [
        {
            "updateSheetProperties": {
                "properties": {
                    "sheetId": sid,
                    "gridProperties": {"frozenRowCount": 1}
                },
                "fields": "gridProperties.frozenRowCount"
            }
        },
        {
            "repeatCell": {
                "range": {
                    "sheetId": sid,
                    "startRowIndex": 0, "endRowIndex": 1,
                    "startColumnIndex": 0, "endColumnIndex": len(HEADERS)
                },
                "cell": {
                    "userEnteredFormat": {
                        "backgroundColor": {
                            "red": 0.86, "green": 0.93, "blue": 0.98
                        },
                        "horizontalAlignment": "CENTER",
                        "textFormat": {
                            "bold": True,
                            "foregroundColor": {
                                "red": 0.11, "green": 0.28, "blue": 0.43
                            }
                        }
                    }
                },
                "fields": "userEnteredFormat(backgroundColor,textFormat,horizontalAlignment)"
            }
        },
        {
            "repeatCell": {
                "range": {
                    "sheetId": sid,
                    "startRowIndex": 1,
                    "startColumnIndex": 0,
                    "endColumnIndex": len(HEADERS)
                },
                "cell": {
                    "userEnteredFormat": {
                        "verticalAlignment": "TOP",
                        "wrapStrategy": "WRAP"
                    }
                },
                "fields": "userEnteredFormat(verticalAlignment,wrapStrategy)"
            }
        },
    ]
    for i, width in enumerate(COLUMN_WIDTHS):
        requests.append({
            "updateDimensionProperties": {
                "range": {
                    "sheetId": sid,
                    "dimension": "COLUMNS",
                    "startIndex": i,
                    "endIndex": i + 1
                },
                "properties": {"pixelSize": width},
                "fields": "pixelSize"
            }
        })
    ws.spreadsheet.batch_update({"requests": requests})


def _get_calendar_worksheet(client):
    spreadsheet = _open_spreadsheet(client)

    try:
        ws = spreadsheet.worksheet(CALENDAR_TAB_NAME)
        logger.info("Using existing tab: %s", CALENDAR_TAB_NAME)
        needs_formatting = False
    except gspread.WorksheetNotFound:
        logger.info("Tab '%s' not found — creating", CALENDAR_TAB_NAME)
        ws = spreadsheet.add_worksheet(
            title=CALENDAR_TAB_NAME,
            rows=1000,
            cols=2
        )
        needs_formatting = True

    existing_headers = ws.row_values(1)
    if existing_headers != CALENDAR_HEADERS:
        ws.update(range_name="A1:B1", values=[CALENDAR_HEADERS])
        needs_formatting = True
        logger.info("Headers written to tab: %s", CALENDAR_TAB_NAME)

    if needs_formatting:
        _apply_calendar_formatting(ws)

    return ws


def _apply_calendar_formatting(ws):
    sid = ws.id
    requests = [
        {
            "updateSheetProperties": {
                "properties": {
                    "sheetId": sid,
                    "gridProperties": {"frozenRowCount": 1}
                },
                "fields": "gridProperties.frozenRowCount"
            }
        },
        {
            "repeatCell": {
                "range": {
                    "sheetId": sid,
                    "startRowIndex": 0, "endRowIndex": 1,
                    "startColumnIndex": 0, "endColumnIndex": 2
                },
                "cell": {
                    "userEnteredFormat": {
                        "backgroundColor": {
                            "red": 0.86, "green": 0.93, "blue": 0.98
                        },
                        "horizontalAlignment": "CENTER",
                        "textFormat": {
                            "bold": True,
                            "foregroundColor": {
                                "red": 0.11, "green": 0.28, "blue": 0.43
                            }
                        }
                    }
                },
                "fields": "userEnteredFormat(backgroundColor,textFormat,horizontalAlignment)"
            }
        },
        {
            "updateDimensionProperties": {
                "range": {
                    "sheetId": sid, "dimension": "COLUMNS",
                    "startIndex": 0, "endIndex": 1
                },
                "properties": {"pixelSize": 140},
                "fields": "pixelSize"
            }
        },
        {
            "updateDimensionProperties": {
                "range": {
                    "sheetId": sid, "dimension": "COLUMNS",
                    "startIndex": 1, "endIndex": 2
                },
                "properties": {"pixelSize": 400},
                "fields": "pixelSize"
            }
        },
    ]
    ws.spreadsheet.batch_update({"requests": requests})


# ── Startup validation ──────────────────────────────

def validate_sheet_access():
    logger.info("Validating Google Sheet access...")
    client = _get_client()

    if not GOOGLE_SHEET_ID:
        raise RuntimeError("GOOGLE_SHEET_ID is empty in config.")

    try:
        spreadsheet = client.open_by_key(GOOGLE_SHEET_ID)
        logger.info(
            "Sheet validation PASSED: opened '%s' (id=%s)",
            spreadsheet.title, GOOGLE_SHEET_ID
        )
        return spreadsheet
    except Exception as e:
        raise RuntimeError(
            "SHEET VALIDATION FAILED: Cannot access Google Sheet '%s'.\n"
            "Root cause: %s" % (GOOGLE_SHEET_ID, e)
        ) from e


def validate_drive_folder_access():
    if not DRIVE_ROOT_FOLDER_ID:
        raise RuntimeError("DRIVE_ROOT_FOLDER_ID is empty in config.")
    logger.info(
        "Drive folder ID present in config: %s (validation deferred to upload)",
        DRIVE_ROOT_FOLDER_ID
    )
    return True


# ── PUBLIC API: OPD upsert ──────────────────────────

def upsert_opd_row_in_sheet(opd_id, row_data):
    logger.info("=== SHEET UPSERT START === OPD=%s", opd_id)

    if row_data:
        log_fields = [
            'OPD ID', 'Patient ID', 'Patient Name', 'Mobile',
            'Visit Date', 'OPD Type', 'Charge Type',
            'Diagnosis', 'Symptoms', 'Clinical Notes', 'Panchakarma Notes',
            'Medicines', 'Consultation Fee', 'Medicine Fee',
            'Panchakarma Fee', 'Total Fee', 'Discount Type',
            'Discount Value', 'Payment Mode', 'Next Visit Date',
            'Follow-up Status',
        ]
        for f in log_fields:
            val = row_data.get(f, '')
            if val:
                logger.info(
                    "SHEET FIELD: OPD=%s %s=%r",
                    opd_id, f, str(val)[:200],
                )

    client = _get_client()
    ws = _get_opd_worksheet(client)

    row = _build_row(row_data)
    logger.info("SHEET BUILT_ROW: OPD=%s row=%s", opd_id, row)

    col_a = ws.col_values(1)
    logger.info(
        "SHEET COL_A: OPD=%s column_A_has_rows=%d header=%r",
        opd_id, len(col_a), col_a[0] if col_a else '(empty)',
    )

    for i, existing_id in enumerate(col_a):
        if i == 0:
            continue
        if existing_id == opd_id:
            sheet_row = i + 1
            end_col = _col_letter(len(HEADERS) - 1)
            logger.info(
                "SHEET MATCH FOUND: OPD=%s at sheet_row=%d — UPDATING row",
                opd_id, sheet_row,
            )
            ws.update(
                range_name=f"A{sheet_row}:{end_col}{sheet_row}",
                values=[row]
            )
            logger.info("=== SHEET UPSERT END (UPDATE) === OPD=%s row=%d", opd_id, sheet_row)
            return

    next_row = max(len(col_a) + 1, 2)
    end_col = _col_letter(len(HEADERS) - 1)
    logger.info(
        "SHEET NO MATCH: OPD=%s not found in column A — APPENDING new row at row=%d",
        opd_id, next_row,
    )
    ws.update(range_name=f"A{next_row}:{end_col}{next_row}", values=[row])
    logger.info("=== SHEET UPSERT END (APPEND) === OPD=%s row=%d", opd_id, next_row)


# ── PUBLIC API: Calendar notes ──────────────────────

def upsert_calendar_note_to_sheet(note_date, note_text):
    logger.info("upsert_calendar_note_to_sheet called for date %s", note_date)

    date_str = note_date.strftime("%Y-%m-%d") if hasattr(note_date, "strftime") else str(note_date)
    text_str = note_text if note_text else ""

    client = _get_client()
    ws = _get_calendar_worksheet(client)

    all_dates = ws.col_values(1)

    for row_index, existing_date in enumerate(all_dates):
        if row_index == 0:
            continue
        if existing_date == date_str:
            sheet_row = row_index + 1
            ws.update(range_name=f"A{sheet_row}:B{sheet_row}", values=[[date_str, text_str]])
            logger.info("Updated calendar note at row %d for date %s", sheet_row, date_str)
            return

    next_row = max(len(all_dates) + 1, 2)
    ws.update(range_name=f"A{next_row}:B{next_row}", values=[[date_str, text_str]])
    logger.info("Appended calendar note at row %d for date %s", next_row, date_str)


# ── PUBLIC API: Clear OPD sheet data ────────────────

def clear_opd_sheet_data():
    logger.warning("clear_opd_sheet_data CALLED — ALL OPD SHEET DATA WILL BE DELETED")

    client = _get_client()
    ws = _get_opd_worksheet(client)

    all_values = ws.get_all_values()
    if len(all_values) <= 1:
        logger.info("Sheet has no data rows — nothing to clear")
        row_count = 0
    else:
        row_count = len(all_values) - 1
        rows_to_delete = len(all_values)
        for r in range(rows_to_delete, 1, -1):
            ws.delete_rows(r)
        logger.info("Cleared %d data rows from opd_visits tab", row_count)

    end_col = _col_letter(len(HEADERS) - 1)
    ws.update(range_name=f"A1:{end_col}1", values=[HEADERS])
    _apply_opd_formatting(ws)

    try:
        db = get_db()
        db.execute("DELETE FROM opd_visits")
        db.execute("DELETE FROM patients")
        db.execute("DELETE FROM patient_images")
        db.execute("DELETE FROM sync_queue")
        db.execute("DELETE FROM calendar_notes")
        db.execute("DELETE FROM clinic_settings")
        db.commit()
        db.close()
        logger.info("Backend database cleared (opd_visits, patients, patient_images, sync_queue, calendar_notes, clinic_settings)")
    except Exception as e:
        logger.error("Failed to clear backend database: %s", e)

    return row_count


# ── PUBLIC API: Update OPD row ──────────────────────

def update_opd_row_in_sheet(opd_id, row_data):
    logger.info("=== SHEET UPDATE START === OPD=%s", opd_id)
    if row_data:
        pk_val = row_data.get("Panchakarma Notes", "NOT_FOUND")
        logger.info("SHEET DEBUG: update OPD=%s Panchakarma Notes value=%r", opd_id, pk_val)

    client = _get_client()
    ws = _get_opd_worksheet(client)

    row = _build_row(row_data)
    records = ws.get_all_values()
    logger.info(
        "SHEET UPDATE SCAN: OPD=%s sheet_has_rows=%d header=%r",
        opd_id, len(records), records[0] if records else '(empty)',
    )

    for i, existing_row in enumerate(records):
        if i == 0:
            continue
        if existing_row and existing_row[0] == opd_id:
            sheet_row = i + 1
            end_col = _col_letter(len(HEADERS) - 1)
            logger.info("SHEET UPDATE MATCH: OPD=%s at sheet_row=%d — UPDATING row", opd_id, sheet_row)
            ws.update(
                range_name=f"A{sheet_row}:{end_col}{sheet_row}",
                values=[row]
            )
            logger.info("=== SHEET UPDATE END === OPD=%s row=%d", opd_id, sheet_row)
            return

    logger.warning(
        "SHEET UPDATE FAILED: OPD=%s not found in sheet after scanning %d data rows — cannot update",
        opd_id, len(records) - 1,
    )
