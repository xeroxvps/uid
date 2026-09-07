"""Queue service foundation for background processing."""

from collections import deque

_jobs = deque()


def add_job(job):
    _jobs.append(job)


def get_job():
    if _jobs:
        return _jobs.popleft()
    return None


def size():
    return len(_jobs)
