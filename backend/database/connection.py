"""Database connection layer for Xerox UID v2."""

import os
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent
DATABASE_URL = os.getenv("DATABASE_URL", f"sqlite:///{BASE_DIR / 'xerox_uid.db'}")


def get_database_url():
    return DATABASE_URL


def init_connection():
    return {
        "database": DATABASE_URL,
        "status": "ready"
    }
