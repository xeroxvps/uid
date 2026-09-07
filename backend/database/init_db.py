"""Database initialization for Xerox UID v2."""

from .connection import init_connection


def initialize_database():
    return init_connection()


if __name__ == "__main__":
    print(initialize_database())
