"""UID API foundation for Xerox UID v2."""


def health():
    return {"status": "ok", "module": "uid"}


def add_uid(uid_value: str):
    return {
        "uid": uid_value,
        "status": "pending"
    }
