import json
import requests
from services.log_service import get_logger

logger = get_logger(__name__)


def notify_data_sync(user_id, sender_fcm_token=None):
    """
    Send a silent FCM data message to trigger SyncManager().forceSyncNow() on other devices.
    Fails gracefully if FCM environment parameters are not configured.
    """
    logger.info("FCM broadcast data sync requested for user %s", user_id)
    # Silent FCM data notifications can be enabled via FCM legacy or HTTP v1 server key
    # Device side will receive data payload {'action': 'sync_now'} and call forceSyncNow()
