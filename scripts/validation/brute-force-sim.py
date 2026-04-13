#!/usr/bin/env python3
"""
brute-force-sim.py — Simulate MC-02: brute-force login to trigger alert-failed-logins

Sends ≥5 failed POST /user/login requests within a 5-minute window using an
intentionally wrong password, then waits for the Azure Monitor alert to fire.

Usage:
    python3 brute-force-sim.py [--url URL] [--username USERNAME] [--attempts N]

The alert rule `alert-failed-logins` fires when Log Analytics sees ≥5 failed
logins in a 5-minute window. Allow 5–10 minutes after this script completes
before checking Azure Monitor for the fired alert.
"""
import argparse
import time
import sys

try:
    import requests
    from bs4 import BeautifulSoup
except ImportError:
    print("ERROR: requires 'requests' and 'beautifulsoup4'")
    print("  pip install requests beautifulsoup4")
    sys.exit(1)

DEFAULT_URL = "https://ca-gitea.wittydune-da50dd5c.norwayeast.azurecontainerapps.io"


def get_csrf_token(session: requests.Session, url: str) -> str:
    """Fetch the login page and extract the _csrf hidden input value."""
    resp = session.get(f"{url}/user/login", timeout=15, allow_redirects=True)
    resp.raise_for_status()
    soup = BeautifulSoup(resp.text, "html.parser")
    token_input = soup.find("input", {"name": "_csrf"})
    if not token_input:
        raise ValueError("Could not find _csrf token on login page")
    return token_input["value"]


def attempt_login(session: requests.Session, url: str, username: str, password: str) -> int:
    """POST to /user/login and return HTTP status code."""
    token = get_csrf_token(session, url)
    resp = session.post(
        f"{url}/user/login",
        data={"_csrf": token, "user_name": username, "password": password},
        timeout=15,
        allow_redirects=False,
    )
    return resp.status_code


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--url", default=DEFAULT_URL, help="Gitea base URL")
    parser.add_argument("--username", default="gitea-admin", help="Username to test against")
    parser.add_argument("--attempts", type=int, default=7, help="Number of failed attempts to send (default: 7)")
    parser.add_argument("--delay", type=float, default=1.0, help="Seconds between attempts (default: 1.0)")
    args = parser.parse_args()

    print("=== MC-02: Brute-Force Login Simulation ===")
    print(f"Target  : {args.url}")
    print(f"Username: {args.username}")
    print(f"Attempts: {args.attempts} (using wrong password on each)")
    print("")
    print("NOTE: This uses an intentionally incorrect password.")
    print("      No valid credentials are tested or required.")
    print("")

    session = requests.Session()
    # Disable cert warnings for dev/test only
    session.verify = True

    success_count = 0
    for i in range(1, args.attempts + 1):
        wrong_password = f"INVALID_PASSWORD_FOR_TEST_{i}"
        try:
            code = attempt_login(session, args.url, args.username, wrong_password)
            # 200 on POST = login page re-rendered (invalid credentials)
            # 302 to /user/login = also invalid credentials (some Gitea versions)
            status = "FAILED_LOGIN (expected)" if code in (200, 302) else f"UNEXPECTED {code}"
            print(f"  Attempt {i:2d}/{args.attempts}: HTTP {code} — {status}")
            success_count += 1
        except Exception as exc:
            print(f"  Attempt {i:2d}/{args.attempts}: ERROR — {exc}")

        if i < args.attempts:
            time.sleep(args.delay)

    print("")
    print(f"=== Done: {success_count}/{args.attempts} requests sent ===")
    print("")
    print("Next steps:")
    print("  1. Wait ~5 minutes for Log Analytics to ingest the logs")
    print("  2. Check Azure Monitor: Alerts → alert-failed-logins")
    print("  3. Or run the KQL query in law-gitea-sec:")
    print("     ContainerAppConsoleLogs_CL")
    print("     | where ContainerAppName_s == \"ca-gitea\"")
    print("     | where Log_s contains \"Failed\" and Log_s contains \"login\"")
    print("     | summarize FailedAttempts = count() by bin(TimeGenerated, 5m)")
    print("     | where FailedAttempts >= 5")


if __name__ == "__main__":
    main()
