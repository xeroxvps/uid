"""UID validation service for Xerox UID v2."""


def validate_uid(uid: str) -> dict:
    uid = str(uid).strip()

    if not uid:
        return {
            "valid": False,
            "reason": "empty uid"
        }

    return {
        "valid": True,
        "uid": uid
    }
