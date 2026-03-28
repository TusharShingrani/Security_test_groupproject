#!/usr/bin/env python3
"""
twin.py – Digital Twin WSS client.

Sends a legitimate schedule message every 10 seconds to the Software Agent.

Environment variables (set via /opt/p2p-demo/twin.env and the systemd unit):
  AGENT_HOST    - hostname/IP of the Software Agent  (default: 10.0.1.20)
  WSS_PORT      - WSS port of the Software Agent     (default: 8443)
  CA_CERT_PATH  - path to the trusted server CA cert (default: certs/server.crt)
  AUTH_MODE     - "none" | "token"                   (default: none)
  SCHEDULE_TOKEN- shared secret used in token mode
  LOG_DIR       - directory for twin.log             (default: /var/log/p2p-demo)
"""

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

AGENT_HOST     = os.environ.get("AGENT_HOST", "10.0.1.20")
WSS_PORT       = int(os.environ.get("WSS_PORT", "8443"))
CA_CERT_PATH   = os.environ.get("CA_CERT_PATH", "/opt/p2p-demo/certs/server.crt")
AUTH_MODE      = os.environ.get("AUTH_MODE", "none").lower()
SCHEDULE_TOKEN = os.environ.get("SCHEDULE_TOKEN", "")
LOG_DIR        = os.environ.get("LOG_DIR", "/var/log/p2p-demo")

LOG_FILE       = os.path.join(LOG_DIR, "twin.log")
SEND_INTERVAL  = 10  # seconds between legitimate schedule messages

# ─── Logger ───────────────────────────────────────────────────────────────────

log = setup_logger("digital-twin", LOG_FILE)

# ─── Main loop ───────────────────────────────────────────────────────────────

async def main() -> None:
    uri = f"wss://{AGENT_HOST}:{WSS_PORT}"

    # Build TLS context – verify the server certificate using our trusted CA.
    ssl_ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    ssl_ctx.load_verify_locations(CA_CERT_PATH)
    # The self-signed cert's CN is "agent-vm" but we connect by IP; disable
    # hostname check while still verifying the cert chain.
    ssl_ctx.check_hostname = False

    log.info("=" * 60)
    log.info("Digital Twin starting")
    log.info("  Agent URI  : %s", uri)
    log.info("  CA cert    : %s", CA_CERT_PATH)
    log.info("  AUTH_MODE  : %s", AUTH_MODE)
    log.info("  Send every : %ds", SEND_INTERVAL)
    log.info("=" * 60)

    while True:
        try:
            log.info("Connecting to agent at %s …", uri)
            async with websockets.connect(uri, ssl=ssl_ctx) as ws:
                log.info("Connected. Starting to send schedule messages.")
                while True:
                    schedule_id = str(uuid.uuid4())
                    token = SCHEDULE_TOKEN if AUTH_MODE == "token" else None

                    message = build_schedule_message(
                        source="digital-twin",
                        schedule_id=schedule_id,
                        electrolyzer_enable=True,
                        token=token,
                    )

                    log.info("Sending schedule message schedule_id=%s", schedule_id)
                    await ws.send(message)

                    # Wait for acknowledgement
                    response_raw = await asyncio.wait_for(ws.recv(), timeout=10)
                    response = json.loads(response_raw)
                    log.info("Agent response: %s", response)

                    await asyncio.sleep(SEND_INTERVAL)

        except (websockets.exceptions.ConnectionClosed, OSError, asyncio.TimeoutError) as exc:
            log.warning("Connection error: %s – retrying in 5s …", exc)
            await asyncio.sleep(5)
        except Exception as exc:
            log.error("Unexpected error: %s – retrying in 5s …", exc)
            await asyncio.sleep(5)


if __name__ == "__main__":
    asyncio.run(main())
