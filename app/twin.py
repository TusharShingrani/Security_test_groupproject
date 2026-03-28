#!/usr/bin/env python3
"""
twin.py - Digital Twin WSS client.
Sends electrolyzer_enable=true every 10 seconds.

Env vars (from twin.env):
  AGENT_HOST, WSS_PORT, CA_CERT_PATH, AUTH_MODE, SCHEDULE_TOKEN, LOG_DIR
"""

import asyncio
import json
import logging
import os
import ssl
import sys

import websockets

# ── Config ─────────────────────────────────────────────────────────────────

AGENT_HOST     = os.environ.get("AGENT_HOST",    "10.0.1.20")
WSS_PORT       = int(os.environ.get("WSS_PORT",  "8443"))
CA_CERT_PATH   = os.environ.get("CA_CERT_PATH",  "/opt/p2p-demo/certs/server.crt")
AUTH_MODE      = os.environ.get("AUTH_MODE",     "none").lower()
SCHEDULE_TOKEN = os.environ.get("SCHEDULE_TOKEN", "")
LOG_DIR        = os.environ.get("LOG_DIR",        "/var/log/p2p-demo")

LOG_FILE      = os.path.join(LOG_DIR, "twin.log")
SEND_INTERVAL = 10  # seconds

# ── Logging ────────────────────────────────────────────────────────────────

os.makedirs(LOG_DIR, exist_ok=True)
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%S",
    handlers=[
        logging.FileHandler(LOG_FILE),
        logging.StreamHandler(sys.stdout),
    ],
)
log = logging.getLogger("twin")


# ── Main loop ────────────────────────────────────────────────────────────────

async def main() -> None:
    uri = f"wss://{AGENT_HOST}:{WSS_PORT}"

    ssl_ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    ssl_ctx.load_verify_locations(CA_CERT_PATH)
    ssl_ctx.check_hostname = False  # self-signed cert uses IP SAN

    log.info("Digital Twin starting -> %s  AUTH_MODE=%s", uri, AUTH_MODE)

    while True:
        try:
            async with websockets.connect(uri, ssl=ssl_ctx) as ws:
                log.info("Connected to agent.")
                while True:
                    msg = {
                        "source": "digital-twin",
                        "electrolyzer_enable": True,
                    }
                    if AUTH_MODE == "token":
                        msg["token"] = SCHEDULE_TOKEN

                    await ws.send(json.dumps(msg))
                    log.info("Sent: %s", msg)

                    resp = json.loads(await asyncio.wait_for(ws.recv(), timeout=10))
                    log.info("Response: %s", resp)

                    await asyncio.sleep(SEND_INTERVAL)

        except (websockets.exceptions.ConnectionClosed, OSError, asyncio.TimeoutError) as exc:
            log.warning("Connection lost: %s - retrying in 5s", exc)
            await asyncio.sleep(5)


if __name__ == "__main__":
    asyncio.run(main())
