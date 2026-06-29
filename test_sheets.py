from datetime import datetime

from backend.desktop_google.sheets_service import append_row_to_sheet

append_row_to_sheet(
    opd_id="OPD-TEST-001",
    patient_id="P0001",
    patient_name="Test Patient",
    mobile="9999999999",
    gender="Female",
    dob="2000-01-01",
    age=25,
    blood_group="O+",
    address="Pune",
    visit_date=datetime.now(),
    opd_type="Regular",
    charge_type="Paid",
    diagnosis="Google Integration Test",
    symptoms="Testing",
    clinical_notes="Testing Google Sheets integration",
    panchakarma_notes="NA",
    medicines="Paracetamol",
    consultation_fee=100,
    medicine_fee=50,
    panchakarma_fee=0,
    total_fee=150,
    discount_type="None",
    discount_value=0,
    payment_mode="Cash",
    next_visit_date="2026-07-01",
    followup_status="Pending",
    image_links=[
        "https://drive.google.com/file/d/11yoa-OpwiUZ1FPmzJrjs9kFGc9PdQijV/view"
    ]
)

print("GOOGLE SHEETS TEST SUCCESS")