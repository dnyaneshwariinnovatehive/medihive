"""
sheets_service.py
=================
Writes OPD visit rows into 'opd_visits' tab and
calendar notes into 'calendar_notes' tab of Clinic_Backup spreadsheet.
"""

import os
from datetime import date, datetime

import gspread
from google.oauth2.service_account import Credentials

from config import GOOGLE_CREDENTIALS_PATH, GOOGLE_SHEET_NAME
from services.log_service import get_logger

logger = get_logger(__name__)

SCOPES = [
    "https://www.googleapis.com/auth/spreadsheets",
    "https://www.googleapis.com/auth/drive",
]

OPD_TAB_NAME      = "opd_visits"
CALENDAR_TAB_NAME = "calendar_notes"

# REPLACE old HEADERS with this:
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

# REPLACE old COLUMN_WIDTHS with this:
COLUMN_WIDTHS = [
    180, 120, 220, 130, 110, 110, 70, 110, 260, 150,
    120, 120, 180, 180, 260,260,
    280,
    130, 120, 140, 110, 110,
    120, 120, 140, 130, 280,
]
CALENDAR_HEADERS = ["Date", "Note"]


# ─────────────────────────────────────────────
# VALUE FORMATTING
# ─────────────────────────────────────────────
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
            """Convert 0-based column index to letter (0=A, 25=Z, 26=AA)"""
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
            row[idx] = _fmt(value)
    return row


# ─────────────────────────────────────────────
# GOOGLE SHEETS CLIENT
# ─────────────────────────────────────────────
def _get_client():
    logger.info("Loading credentials from: %s", GOOGLE_CREDENTIALS_PATH)

    if not os.path.exists(GOOGLE_CREDENTIALS_PATH):
        raise FileNotFoundError(
            "credentials.json not found at: %s\n"
            "Download from Google Cloud Console -> IAM -> Service Accounts -> Keys."
            % GOOGLE_CREDENTIALS_PATH
        )

    creds = Credentials.from_service_account_file(
        GOOGLE_CREDENTIALS_PATH, scopes=SCOPES
    )
    return gspread.authorize(creds)


def _open_spreadsheet(client):
    try:
        spreadsheet = client.open(GOOGLE_SHEET_NAME)
        logger.info("Opened spreadsheet: %s", GOOGLE_SHEET_NAME)
    except gspread.SpreadsheetNotFound:
        logger.info("Spreadsheet not found — creating: %s", GOOGLE_SHEET_NAME)
        spreadsheet = client.create(GOOGLE_SHEET_NAME)
    return spreadsheet


# ─────────────────────────────────────────────
# OPD VISITS TAB
# ─────────────────────────────────────────────
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


# ─────────────────────────────────────────────
# CALENDAR NOTES TAB
# ─────────────────────────────────────────────
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


# ─────────────────────────────────────────────
# PUBLIC API — OPD
# ─────────────────────────────────────────────
# REPLACE the entire append_row_to_sheet function:
def append_row_to_sheet(
    opd_id, patient_id, patient_name, mobile,
    gender, dob, age, blood_group, address, visit_date,
    opd_type, charge_type, diagnosis, symptoms, clinical_notes,panchakarma_notes,
    medicines,
    consultation_fee, medicine_fee, panchakarma_fee, total_fee,
    discount_type, discount_value, payment_mode,
    next_visit_date, followup_status, image_links,
):
    logger.info("append_row_to_sheet called for OPD %s", opd_id)

    image_links_text = "\n".join(image_links) if image_links else None

    row = _build_row({
        "OPD ID": opd_id,
        "Patient ID": patient_id,
        "Patient Name": patient_name,
        "Mobile": mobile,
        "Gender": gender,
        "DOB": dob,
        "Age": age,
        "Blood Group": blood_group,
        "Address": address,
        "Visit Date": visit_date,
        "OPD Type": opd_type,
        "Charge Type": charge_type,
        "Diagnosis": diagnosis,
        "Symptoms": symptoms,
        "Clinical Notes": clinical_notes,
        "Panchakarma Notes": panchakarma_notes,

                "Medicines": medicines,

        "Consultation Fee": consultation_fee,
        "Medicine Fee": medicine_fee,
        "Panchakarma Fee": panchakarma_fee,
        "Total Fee": total_fee,
        "Discount Type": discount_type,
        "Discount Value": discount_value,
        "Payment Mode": payment_mode,
        "Next Visit Date": next_visit_date,
        "Follow-up Status": followup_status,
        "Image Links": image_links_text,
    })

    client = _get_client()
    ws = _get_opd_worksheet(client)

    col_a_values = ws.col_values(1)
    next_row = max(len(col_a_values) + 1, 2)

    end_col = _col_letter(len(HEADERS) - 1)
    ws.update(range_name=f"A{next_row}:{end_col}{next_row}", values=[row])

    logger.info("Row written to Sheets at row %d for OPD %s", next_row, opd_id)


# ─────────────────────────────────────────────
# PUBLIC API — OPD (UPSERT)
# ─────────────────────────────────────────────
def upsert_opd_row_in_sheet(opd_id, row_data):
    """
    Insert or update a row in the OPD visits sheet.
    If OPD ID exists in column A, update that row.
    Otherwise, append a new row at the end.
    """
    logger.info("upsert_opd_row_in_sheet called for OPD %s", opd_id)

    client = _get_client()
    ws = _get_opd_worksheet(client)

    row = _build_row(row_data)
    col_a = ws.col_values(1)

    for i, existing_id in enumerate(col_a):
        if i == 0:
            continue
        if existing_id == opd_id:
            sheet_row = i + 1
            end_col = _col_letter(len(HEADERS) - 1)
            ws.update(
                range_name=f"A{sheet_row}:{end_col}{sheet_row}",
                values=[row]
            )
            logger.info("Updated existing row %d for OPD %s", sheet_row, opd_id)
            return

    next_row = max(len(col_a) + 1, 2)
    end_col = _col_letter(len(HEADERS) - 1)
    ws.update(range_name=f"A{next_row}:{end_col}{next_row}", values=[row])
    logger.info("Appended new row at %d for OPD %s", next_row, opd_id)


# ─────────────────────────────────────────────
# PUBLIC API — CALENDAR NOTES
# ─────────────────────────────────────────────
def upsert_calendar_note_to_sheet(note_date, note_text):
    """
    Write or update a calendar note in the calendar_notes tab.
    If a row with the same date already exists, update it.
    If not, append a new row.
    """
    logger.info("upsert_calendar_note_to_sheet called for date %s", note_date)

    date_str = note_date.strftime("%Y-%m-%d") if hasattr(note_date, "strftime") else str(note_date)
    text_str = note_text if note_text else ""

    client = _get_client()
    ws = _get_calendar_worksheet(client)

    # Check if date already exists in column A
    all_dates = ws.col_values(1)  # includes header

    for row_index, existing_date in enumerate(all_dates):
        if row_index == 0:
            continue  # skip header
        if existing_date == date_str:
            # Update existing row
            sheet_row = row_index + 1
            ws.update(range_name=f"A{sheet_row}:B{sheet_row}", values=[[date_str, text_str]])
            logger.info("Updated calendar note at row %d for date %s", sheet_row, date_str)
            return

    # Append new row
    next_row = max(len(all_dates) + 1, 2)
    ws.update(range_name=f"A{next_row}:B{next_row}", values=[[date_str, text_str]])
    logger.info("Appended calendar note at row %d for date %s", next_row, date_str)


def update_opd_row_in_sheet(opd_id, row_data):
    """
    Update an existing OPD row in Google Sheets.
    Finds row by OPD ID (column A) and updates its values.
    Logs warning if OPD ID is not found in the sheet.
    """
    logger.info("update_opd_row_in_sheet called for OPD %s", opd_id)

    client = _get_client()
    ws = _get_opd_worksheet(client)

    row = _build_row(row_data)
    records = ws.get_all_values()

    for i, existing_row in enumerate(records):
        if i == 0:
            continue
        if existing_row and existing_row[0] == opd_id:
            sheet_row = i + 1
            end_col = _col_letter(len(HEADERS) - 1)
            ws.update(
                range_name=f"A{sheet_row}:{end_col}{sheet_row}",
                values=[row]
            )
            logger.info("Updated row %d for OPD %s", sheet_row, opd_id)
            return

    logger.warning("OPD %s not found in sheet, cannot update", opd_id)