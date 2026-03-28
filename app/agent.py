#!/usr/bin/env python3
"""
agent.py - WSS Software Agent server.

Demonstrates the security finding:
  AUTH_MODE=none  -> accepts ANY sender (vulnerability)
  AUTH_MODE=token -> requires matching token (fix)

Env vars (from agent.env):
  AUTH_MODE, SCHEDULE_TOKEN, WSS_PORT, CERT_PATH, KEY_PATH,
  STATE_DIR, LOG_DIR
"""

import asyncio
import json
import logging
import os
import ssl
import sys
from datetime import datetime, timezone

import websockets

# ── Config ──────────────────────────────────────────────────────────────────

AUTH_MODE      = os.environ.get("AUTH_MODE", "none").lower()
SCHEDULE_TOKEN = os.environ.get("SCHEDULE_TOKEN", "")
WSS_PORT       = int(os.environ.get("WSS_PORT", "8443"))
CERT_PATH      = os.environ.get("CERT_PATH", "/opt/p2p-demo/certs/server.crt")
KEY_PATH       = os.environ.get("KEY_PATH",  "/opt/p2p-demo/certs/server.key")
STATE_DIR      = os.environ.get("STATE_DIR", "/var/lib/p2p-demo")
LOG_DIR        = os.environ.get("LOG_DIR",   "/var/log/p2p-demo")

LOG_FILE   = os.path.join(LOG_DIR, "agent.log")
STATE_FILE = os.path.join(STATE_DIR, "plc_state.json")

# ── Logging ─────────────────────────────────────────────────────────────────

os.makedirs(LOG_DIR, exist_ok=True)
os.makedirs(STATE_DIR, exist_ok=True)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%S",
    handlers=[
        logging.FileHandler(LOG_FILE),
        logging.StreamHandler(sys.stdout),
    ],
)
log = logging.getLogger("agent")


# ── PLC state simulation ─────────────────────────────────────────────────────

def update_plc_state(electrolyzer_enable: bool, source: str) -> None:
    state = {
        "timestamp": datetime.now(tz=timezone.utc).isoformat(),
        "plc_state": "RUNNING" if electrolyzer_enable else "IDLE",
        "electrolyzer_enable": electrolyzer_enable,
        "last_source": source,
    }
    with open(STATE_FILE, "w") as f:
        json.dump(state, f, indent=2)
    log.info("PLC state -> %s (source=%s)", state["plc_state"], source)


# ── Message handler ───────────────────────────────────────────────────────────

async def handle(websocket) -> None:
    try:
        sender_ip = websocket.remote_address[0]
    except Exception:
        sender_ip = "unknown"

    log.info("Connection from %s", sender_ip)

    async for raw in websocket:
        # Parse
        try:
            data = json.loads(raw)
        except json.JSONDecodeError:
            log.warning("REJECTED [%s] invalid JSON", sender_ip)
            await websocket.send(json.dumps({"status": "error", "reason": "invalid JSON"}))
            continue

        source  = data.get("source", "unknown")
        enabled = data.get("electrolyzer_enable")

        # Schema check
        if not isinstance(enabled, bool):
            log.warning("REJECTED [%s] source=%s missing/invalid electrolyzer_enable", sender_ip, source)
            await websocket.send(json.dumps({"status": "error", "reason": "electrolyzer_enable must be bool"}))
            continue

        # Auth check
        if AUTH_MODE == "token":
            provided = data.get("token", "")
            if provided != SCHEDULE_TOKEN:
                log.warning(
                    "REJECTED [%s] source=%s -- AUTH_MODE=token: invalid/missing token",
                    sender_ip, source,
                )
                await websocket.send(json.dumps({"status": "rejected", "reason": "invalid or missing token"}))
                continue
            log.info("Token OK for source=%s", source)
        else:
            # AUTH_MODE=none: THIS IS THE VULNERABILITY BEING DEMONSTRATED
            log.warning(
                "AUTH_MODE=none: accepting from %s (source=%s) with NO authentication",
                sender_ip, source,
            )

        # Accept
        log.info("ACCEPTED [%s] source=%s electrolyzer_enable=%s", sender_ip, source, enabled)
        update_plc_state(enabled, source)
        await websocket.send(json.dumps({"status": "accepted"}))

    log.info("Disconnected: %s", sender_ip)


# ── Main ──────────────────────────────────────────────────────────────────────

async def main() -> None:
    ssl_ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ssl_ctx.load_cert_chain(certfile=CERT_PATH, keyfile=KEY_PATH)

    log.info("=" * 55)
    log.info("Software Agent starting")
    log.info("  AUTH_MODE : %s", AUTH_MODE)
    log.info("  Port      : %d", WSS_PORT)
    if AUTH_MODE == "none":
        log.warning("  *** NO client authentication - vulnerability active ***")
    log.info("=" * 55)

    async with websockets.serve(handle, "0.0.0.0", WSS_PORT, ssl=ssl_ctx):
        log.info("Listening on wss://0.0.0.0:%d", WSS_PORT)
        await asyncio.Future()


if __name__ == "__main__":
    asyncio.run(main())
