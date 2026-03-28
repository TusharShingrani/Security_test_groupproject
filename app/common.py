"""
common.py – shared helpers for the WSS PoC.
Loaded by agent.py, twin.py and attacker.py.
"""

import json
import logging
import os
from datetime import datetime, timezone


# ─── Logging helper ──────────────────────────────────────────────────────────

def setup_logger(name: str, log_file: str, level: int = logging.INFO) -> logging.Logger:
    """Create a logger that writes to both a file and stdout."""
    log_dir = os.path.dirname(log_file)
    os.makedirs(log_dir, exist_ok=True)

    formatter = logging.Formatter(
        fmt="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
        datefmt="%Y-%m-%dT%H:%M:%S%z",
    )

    file_handler = logging.FileHandler(log_file)
    file_handler.setFormatter(formatter)

    stream_handler = logging.StreamHandler()
    stream_handler.setFormatter(formatter)

    logger = logging.getLogger(name)
    logger.setLevel(level)
    logger.addHandler(file_handler)
    logger.addHandler(stream_handler)
    return logger


# ─── Message schema ──────────────────────────────────────────────────────────

REQUIRED_FIELDS = {"source", "schedule_id", "start_time", "stop_time", "electrolyzer_enable"}


def validate_message(data: dict) -> tuple[bool, str]:
    """
    Light schema check.
    Returns (True, "") when valid, or (False, reason) when invalid.
    """
    missing = REQUIRED_FIELDS - data.keys()
    if missing:
        return False, f"missing fields: {sorted(missing)}"
    if not isinstance(data["electrolyzer_enable"], bool):
        return False, "electrolyzer_enable must be a boolean"
    return True, ""


def utc_now() -> str:
    """Return current UTC timestamp as ISO-8601 string."""
    return datetime.now(tz=timezone.utc).isoformat()


def build_schedule_message(
    source: str,
    schedule_id: str,
    electrolyzer_enable: bool,
    token: str | None = None,
) -> str:
    """Build a JSON schedule message string."""
    msg = {
        "source": source,
        "schedule_id": schedule_id,
        "start_time": utc_now(),
        "stop_time": utc_now(),
        "electrolyzer_enable": electrolyzer_enable,
    }
    if token is not None:
        msg["token"] = token
    return json.dumps(msg)
