#!/usr/bin/env python3
from app.main import app_state


def main() -> None:
    app_state.cleanup_expired_jobs()


if __name__ == "__main__":
    main()
