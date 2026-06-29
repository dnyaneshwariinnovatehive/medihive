from datetime import datetime
from backend.desktop_google.drive_service import upload_images_to_drive


class TestImage:
    def __init__(self, path):
        self.file_path = path


test_image = TestImage(
    r"D:\MediHive-Flutter\test_images\sample.png"
)

urls = upload_images_to_drive(
    opd_id="OPD-TEST-001",
    image_records=[test_image],
    visit_date=datetime.now()
)

print("\nUPLOAD SUCCESS")
print(urls)