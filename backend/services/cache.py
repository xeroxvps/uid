"""Cache service foundation for Xerox UID v2."""

_cache = {}


def get(key: str):
    return _cache.get(key)


def set(key: str, value):
    _cache[key] = value


def clear():
    _cache.clear()
