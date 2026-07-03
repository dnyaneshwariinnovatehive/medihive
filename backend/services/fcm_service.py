import os
import json
import logging
import requests
from database import get_db

logger = logging.getLogger(__name__)

FCM_SERVER_KEY = os.environ.get('FCM_SERVER_KEY', '')


def send_push_notification(token: str, title: str, body: str, data: dict = None):
    if not FCM_SERVER_KEY:
        logger.warning("FCM_SERVER_KEY not configured; skipping push notification")
        return False

    headers = {
        "Authorization": f"key={FCM_SERVER_KEY}",
        "Content-Type": "application/json",
    }

    message = {
        "to": token,
        "notification": {
            "title": title,
            "body": body,
            "sound": "default",
        },
        "data": {k: str(v) for k, v in (data or {}).items()},
        "priority": "high",
    }

    try:
        resp = requests.post(
            "https://fcm.googleapis.com/fcm/send",
            headers=headers,
            data=json.dumps(message),
            timeout=10,
        )
        result = resp.json()
        if result.get("success", 0) == 1:
            return True
        if "InvalidRegistration" in str(result) or "NotRegistered" in str(result):
            _remove_token(token)
        logger.error(f"FCM send failed: {result}")
        return False
    except Exception as e:
        logger.error(f"FCM request error: {e}")
        return False


def send_push_to_all_users(title: str, body: str, data: dict = None):
    db = get_db()
    rows = db.execute(
        "SELECT fcm_token FROM fcm_tokens WHERE fcm_token IS NOT NULL AND fcm_token != ''"
    ).fetchall()
    db.close()
    sent = 0
    for row in rows:
        if send_push_notification(row["fcm_token"], title, body, data):
            sent += 1
    logger.info("FCM: sent %d/%d notifications", sent, len(rows))
    return sent


def save_fcm_token(token: str, user_id: str = None):
    db = get_db()
    existing = db.execute(
        "SELECT id FROM fcm_tokens WHERE fcm_token = %s", (token,)
    ).fetchone()
    if existing:
        db.execute(
            "UPDATE fcm_tokens SET updated_at = NOW(), user_id = COALESCE(%s, user_id) WHERE fcm_token = %s",
            (user_id, token),
        )
    else:
        db.execute(
            "INSERT INTO fcm_tokens (fcm_token, user_id, created_at, updated_at) VALUES (%s, %s, NOW(), NOW())",
            (token, user_id),
        )
    db.commit()
    db.close()


def _remove_token(token: str):
    try:
        db = get_db()
        db.execute("DELETE FROM fcm_tokens WHERE fcm_token = %s", (token,))
        db.commit()
        db.close()
        logger.info("Removed stale FCM token from database")
    except Exception as e:
        logger.error("Failed to remove stale FCM token: %s", e)
