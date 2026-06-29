from sqlalchemy import Column, Integer, String, DateTime, Text
from datetime import datetime
from backend.database.db import Base

class SyncQueue(Base):
    __tablename__ = "sync_queue"

    id = Column(Integer, primary_key=True, index=True)

    # OPD or IMAGE
    entity_type = Column(String(20), nullable=False)

    # opd_id or image_id
    entity_id = Column(String(100), nullable=False)

    status = Column(String(20), default="PENDING")  
    retry_count = Column(Integer, default=0)
    last_error = Column(Text, nullable=True)

    created_at = Column(DateTime, default=datetime.utcnow)
    last_attempt = Column(DateTime, nullable=True)
