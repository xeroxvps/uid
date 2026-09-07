import os

APP_NAME = "Xerox UID v2"
DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///./xerox_uid.db")
ENVIRONMENT = os.getenv("ENVIRONMENT", "development")
