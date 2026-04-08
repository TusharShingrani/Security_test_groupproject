#!/usr/bin/env python3
import asyncio
import json
import logging
import os

import websockets
from websockets.exceptions import ConnectionClosed

LISTEN_HOST = os.getenv("LISTEN_HOST", "0.0.0.0")
LISTEN_PORT = int(os.getenv("LISTEN_PORT", "8443"))

# Final destination host
UPSTREAM_HOST = os.getenv("UPSTREAM_HOST", "10.0.1.20")
UPSTREAM_PORT = int(os.getenv("UPSTREAM_PORT", "8443"))

LOG_DIR = os.getenv("LOG_DIR", "/var/log/p2p-proxy")
LOG_FILE = os.path.join(LOG_DIR, "proxy.log")

os.makedirs(LOG_DIR, exist_ok=True)
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%S",
    handlers=[
        logging.FileHandler(LOG_FILE),
        logging.StreamHandler(),
    ],
)
log = logging.getLogger("ws-proxy")


def transform_message(obj):
    """
    Flip electrolyzer_enable if present and boolean.
    """
    if isinstance(obj, dict) and "electrolyzer_enable" in obj:
        val = obj["electrolyzer_enable"]
        if isinstance(val, bool):
            obj = dict(obj)
            obj["electrolyzer_enable"] = not val
    return obj


async def handle_client(client_ws):
    upstream_uri = f"ws://{UPSTREAM_HOST}:{UPSTREAM_PORT}"

    log.info("Client connected from %s", client_ws.remote_address)

    try:
        async with websockets.connect(upstream_uri) as upstream_ws:
            log.info("Connected to upstream %s", upstream_uri)

            async def client_to_upstream():
                async for message in client_ws:
                    log.info("RECV  client -> proxy: %s", message)

                    try:
                        data = json.loads(message)
                        modified = transform_message(data)
                        out_msg = json.dumps(modified)
                    except json.JSONDecodeError:
                        out_msg = message

                    log.info("MOD   proxy  -> upstream: %s", out_msg)
                    await upstream_ws.send(out_msg)

            async def upstream_to_client():
                async for message in upstream_ws:
                    log.info("RECV  upstream -> proxy: %s", message)
                    log.info("SEND  proxy    -> client: %s", message)
                    await client_ws.send(message)

            t1 = asyncio.create_task(client_to_upstream())
            t2 = asyncio.create_task(upstream_to_client())

            done, pending = await asyncio.wait(
                {t1, t2},
                return_when=asyncio.FIRST_EXCEPTION,
            )

            for task in pending:
                task.cancel()

    except ConnectionClosed as exc:
        log.warning("Connection closed: %s", exc)
    except Exception as exc:
        log.exception("Proxy error: %s", exc)
    finally:
        log.info("Client disconnected")


async def main():
    async with websockets.serve(
        handle_client,
        LISTEN_HOST,
        LISTEN_PORT,
        ping_interval=20,
        ping_timeout=20,
    ):
        log.info("Listening on ws://%s:%d", LISTEN_HOST, LISTEN_PORT)
        await asyncio.Future()


if __name__ == "__main__":
    asyncio.run(main())
