import os
import requests
from services.log_service import get_logger

logger = get_logger(__name__)

FCM_SERVER_KEY = os.environ.get('FCM_SERVER_KEY', '')


def notify_data_sync(user_id, sender_fcm_token=None):
    """
    Send a silent FCM data message to trigger SyncManager().forceSyncNow() on other devices.
    Uses FCM topic messaging to avoid database storage of tokens.
    """
    logger.info("FCM broadcast data sync requested for user %s", user_id)
    if not FCM_SERVER_KEY:
        logger.warning("FCM_SERVER_KEY is not configured. FCM broadcast skipped.")
        return

    topic = f"sync_user_{user_id}"
    logger.info("Sending silent sync notification to topic %s", topic)

    headers = {
        'Content-Type': 'application/json',
        'Authorization': f'key={FCM_SERVER_KEY}'
    }
    payload = {
        'to': f'/topics/{topic}',
        'data': {
            'action': 'sync_now',
            'sync': 'true'
        },
        'priority': 'high'
    }

    try:
        res = requests.post('https://fcm.googleapis.com/fcm/send', headers=headers, json=payload, timeout=10)
        logger.info("FCM topic response: status=%d body=%s", res.status_code, res.text)
    except Exception as e:
        logger.error("Failed to send FCM topic broadcast: %s", e)
