from backend.database.db import engine
from backend.utils.hashing import hash_password
from backend.utils.hashing import verify_password
import random
from datetime import datetime, timedelta
from backend.database.db import SessionLocal
from backend.models.user import User
from backend.models.clinic_settings import ClinicSettings
from backend.utils.email_sender import send_email

def create_default_doctor():
    """
    Create default doctor user if not exists
    """
    with engine.begin() as conn:
        result = conn.exec_driver_sql(
            "SELECT id FROM users WHERE username = 'admin'"
        ).fetchone()

        if result:
            print("Default doctor already exists")
            return

        password_hash = hash_password("admin123")

        conn.exec_driver_sql(
            """
            INSERT INTO users (username, password_hash, email)
            VALUES (?, ?, ?)
            """,
            ("admin", password_hash, "doctor@clinic.local")
        )

        print("Default doctor created (username: admin)")


def verify_login(username: str, password: str) -> bool:
    """
    Verify doctor login credentials
    """
    with engine.begin() as conn:
        result = conn.exec_driver_sql(
            """
            SELECT password_hash
            FROM users
            WHERE username = ?
            """,
            (username,)
        ).fetchone()

        if not result:
            return False

        stored_hash = result[0]
        return verify_password(password, stored_hash)
    
def send_otp_email(email):
    db = SessionLocal()
    try:
        user = db.query(User).filter(User.email == email).first()
        if not user:
            return {"message": "Email not registered"}, 404

        settings = db.query(ClinicSettings).first()
        if not settings or not settings.smtp_email:
            return {"message": "SMTP not configured"}, 400

        # 🔹 Generate 6-digit OTP
        otp = str(random.randint(100000, 999999))

        # 🔹 Set expiry 5 minutes
        user.reset_otp = otp
        user.otp_expiry = datetime.utcnow() + timedelta(minutes=5)
        db.commit()

        subject = "MediHive Password Reset OTP"
        body = f"Your OTP is: {otp}\n\nThis OTP will expire in 5 minutes."

        success, message = send_email(
            settings.smtp_email,
            settings.smtp_password,
            settings.smtp_server,
            settings.smtp_port,
            email,
            subject,
            body
        )

        if not success:
            return {"message": message}, 500

        return {"success": True, "message": "OTP sent successfully"}, 200

    except Exception as e:
        db.rollback()
        return {"message": str(e)}, 500

    finally:
        db.close()    

def reset_password(email, otp, new_password):
    db = SessionLocal()
    try:
        user = db.query(User).filter(User.email == email).first()
        if not user:
            return {"message": "Email not registered"}, 404

        if not user.reset_otp:
            return {"message": "No OTP requested"}, 400

        if user.reset_otp != otp:
            return {"message": "Invalid OTP"}, 400

        if not user.otp_expiry or user.otp_expiry < datetime.utcnow():
            return {"message": "OTP expired"}, 400

        # 🔹 Update password
        user.password_hash = hash_password(new_password)

        # 🔹 Clear OTP
        user.reset_otp = None
        user.otp_expiry = None

        db.commit()

        return {"success": True, "message": "Password reset successful"}, 200

    except Exception as e:
        db.rollback()
        return {"message": str(e)}, 500

    finally:
        db.close()        