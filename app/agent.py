#!/usr/bin/env python3
"""
agent.py – WSS Software Agent (server side).

Security finding demonstrated:
  Phase A (AUTH_MODE=none):  accepts any properly-formed message regardless
                             of sender identity.
  Phase B (AUTH_MODE=token): rejects messages whose token doesn't match
                             the expected SCHEDULE_TOKEN env var.

Environment variables (set via /opt/p2p-demo/agent.env and the systemd unit):
  AUTH_MODE       - "none" | "token"  (default: none)
  SCHEDULE_TOKEN  - shared secret used in token mode
  WSS_PORT        - port to listen on              (default: 8443)
  CERT_PATH       - path to TLS server certificate (default: certs/server.crt)
  KEY_PATH        - path to TLS server private key (default: certs/server.key)
  STATE_DIR       - directory for plc_state.json   (default: /var/lib/p2p-demo)
  LOG_DIR         - directory for agent.log         (default: /var/log/p2p-demo)
"""

import asyncio
import json
import os
import ssl
import sys

import websockets

# Append the app directory to path so common.py is importable when run
# directly or as a systemd service.
sys.path.insert(0, os.path.dirname(__file__))
from common import setup_logger, validate_message, utc_now

# ─── Configuration from environment ──────────────────────────────────────────

AUTH_MODE       = os.environ.get("AUTH_MODE", "none").lower()
SCHEDULE_TOKEN  = os.environ.get("SCHEDULE_TOKEN", "")
WSS_PORT        = int(os.environ.get("WSS_PORT", "8443"))
CERT_PATH       = os.environ.get("CERT_PATH", "/opt/p2p-demo/certs/server.crt")
KEY_PATH        = os.environ.get("KEY_PATH",  "/opt/p2p-demo/certs/server.key")
STATE_DIR       = os.environ.get("STATE_DIR", "/var/lib/p2p-demo")
LOG_DIR         = os.environ.get("LOG_DIR",   "/var/log/p2p-demo")

LOG_FILE   = os.path.join(LOG_DIR,  "agent.log")
STATE_FILE = os.path.join(STATE_DIR, "plc_state.json")

# ─── Logger ───────────────────────────────────────────────────────────────────

log = setup_logger("agent", LOG_FILE)

# ─── Simulated PLC state ──────────────────────────────────────────────────────

def update_plc_state(electrolyzer_enable: bool, source: str, schedule_id: str) -> None:
    """Write the current simulated PLC state to disk."""
    os.makedirs(STATE_DIR, exist_ok=True)
    state = {
        "timestamp": utc_now(),
        "plc_state": "RUNNING" if electrolyzer_enable else "IDLE",
        "electrolyzer_enable": electrolyzer_enable,
        "last_source": source,
        "last_schedule_id": schedule_id,
    }
    with open(STATE_FILE, "w") as f:
        json.dump(state, f, indent=2)
    log.info(
        "PLC state updated → %s (electrolyzer_enable=%s, source=%s, schedule_id=%s)",
        state["plc_state"],
        electrolyzer_enable,
        source,
        schedule_id,
    )

# ─── Message handler ─────────────────────────────────────────────────────────

async def handle_message(websocket) -> None:
    """
    Handle a single incoming WSS connection.
    Reads messages until the connection closes.
    """
    # Extract the remote IP for logging.
    try:
        sender_ip = websocket.remote_address[0]
    except Exception:
        sender_ip = "unknown"

    log.info("New connection from %s", sender_ip)

    async for raw_message in websocket:
        # ── Parse JSON ──────────────────────────────────────────────────────
        try:
            data = json.loads(raw_message)
        except json.JSONDecodeError as exc:
            log.warning("REJECTED [%s] – invalid JSON: %s", sender_ip, exc)
            await websocket.send(json.dumps({"status": "error", "reason": "invalid JSON"}))
            continue

        source      = data.get("source", "unknown")
        schedule_id = data.get("schedule_id", "unknown")

        log.info(
            "Received message from %s | source=%s | schedule_id=%s | electrolyzer_enable=%s",
            sender_ip, source, schedule_id, data.get("electrolyzer_enable"),
        )

        # ── Light schema validation ──────────────────────────────────────────
        valid, reason = validate_message(data)
        if not valid:
            log.warning(
                "REJECTED [%s] source=%s – schema error: %s",
                sender_ip, source, reason,
            )
            await websocket.send(json.dumps({"status": "error", "reason": reason}))
            continue

        # ── Auth check ───────────────────────────────────────────────────────
        if AUTH_MODE == "token":
            provided_token = data.get("token", "")
            if provided_token != SCHEDULE_TOKEN:
                log.warning(
                    "REJECTED [%s] source=%s schedule_id=%s – "
                    "AUTH_MODE=token: missing or invalid token",
                    sender_ip, source, schedule_id,
                )
                await websocket.send(
                    json.dumps({"status": "rejected", "reason": "invalid or missing token"})
                )
                continue
            log.info("Token validated OK for source=%s", source)
        else:
            # AUTH_MODE=none – the vulnerability: we accept everyone.
            log.warning(
                "AUTH_MODE=none – accepting message from %s (source=%s) "
                "WITHOUT any authentication. This is the vulnerability!",
                sender_ip, source,
            )

        # ── Accept the message ───────────────────────────────────────────────
        electrolyzer_enable = data["electrolyzer_enable"]
        log.info(
            "ACCEPTED [%s] source=%s schedule_id=%s electrolyzer_enable=%s",
            sender_ip, source, schedule_id, electrolyzer_enable,
        )
        update_plc_state(electrolyzer_enable, source, schedule_id)
        await websocket.send(json.dumps({"status": "accepted", "schedule_id": schedule_id}))

    log.info("Connection closed from %s", sender_ip)

# ─── Main ─────────────────────────────────────────────────────────────────────

async def main() -> None:
    # Build TLS context – server presents its certificate to clients.
    ssl_ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ssl_ctx.load_cert_chain(certfile=CERT_PATH, keyfile=KEY_PATH)

    log.info("=" * 60)
    log.info("Software Agent starting")
    log.info("  AUTH_MODE : %s", AUTH_MODE)
    log.info("  WSS port  : %d", WSS_PORT)
    log.info("  CERT_PATH : %s", CERT_PATH)
    log.info("  STATE_FILE: %s", STATE_FILE)
    if AUTH_MODE == "none":
        log.warning("  *** AUTH_MODE=none – NO client authentication! ***")
        log.warning("  *** Any client that can reach this port can send commands. ***")
    log.info("=" * 60)

    async with websockets.serve(handle_message, "0.0.0.0", WSS_PORT, ssl=ssl_ctx):
        log.info("WSS server listening on wss://0.0.0.0:%d", WSS_PORT)
        await asyncio.Future()  # run forever


if __name__ == "__main__":
    asyncio.run(main())
