from dataclasses import dataclass
from datetime import datetime

@dataclass
class UIDRecord:
    id: int | None
    uid_value: str
    tag: str = ""
    status: str = "pending"
    created_at: datetime = datetime.now()
