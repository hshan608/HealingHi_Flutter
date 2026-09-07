"""Read-only Supabase probe and optional Healthchecks.io dead-man signal.

Python 3.10+, standard library only. Never logs URLs, keys or response bodies.
"""

import argparse
import http.client
import json
import os
import re
import socket
import time
import urllib.error
import urllib.request


class ProbeError(Exception):
    def __init__(self, message, retryable=False):
        super().__init__(message)
        self.retryable = retryable


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        # Do not forward API keys to redirect targets.
        return None


def fetch(url, headers, limit=262144):
    request = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.build_opener(NoRedirect).open(request, timeout=30) as response:
            body = response.read(limit + 1)
            if len(body) > limit:
                raise ProbeError("Response exceeds the health-check size limit.")
            return response.status, body
    except urllib.error.HTTPError as error:
        status = error.code
        error.close()
        if status in (401, 403):
            hint = "Check the project's API key and quotes read permissions."
        elif status in (400, 404):
            hint = "Check SUPABASE_URL and Data API access to public.quotes."
        elif 300 <= status < 400:
            hint = "Redirect refused; use the project's direct URL."
        else:
            hint = "Check project status and service availability."
        raise ProbeError(
            f"HTTP {status}. {hint}", status == 429 or 500 <= status < 600
        ) from None
    except urllib.error.URLError as error:
        if isinstance(error.reason, socket.gaierror):
            raise ProbeError(
                "DNS lookup failed. Verify SUPABASE_URL and project status in "
                "Supabase Dashboard. Resume a paused project there; REST requests "
                "cannot resume it.", True
            ) from None
        raise ProbeError("Connection failed. Check project and network status.", True) from None
    except (TimeoutError, OSError, http.client.HTTPException):
        raise ProbeError("Connection timed out or failed.", True) from None


def retry(operation):
    for attempt in range(1, 5):
        try:
            return operation()
        except ProbeError as error:
            if not error.retryable or attempt == 4:
                raise
            print(f"Attempt {attempt}/4 failed; retrying in 10 seconds.")
            time.sleep(10)


def check_database():
    base_url = os.environ.get("SUPABASE_URL", "").strip().rstrip("/")
    key = (os.environ.get("SUPABASE_ANON_KEY") or os.environ.get("SUPABASE_KEY", "")).strip()
    if not re.fullmatch(r"https://[a-z0-9]+\.supabase\.co", base_url):
        raise ProbeError("Set SUPABASE_URL to https://<project-ref>.supabase.co.")
    if not key or not key.isascii() or any(char.isspace() for char in key):
        raise ProbeError("Set SUPABASE_ANON_KEY (or legacy SUPABASE_KEY) to a valid API key.")
    headers = {"apikey": key, "Accept": "application/json", "Cache-Control": "no-cache"}
    if not key.startswith("sb_publishable_"):
        headers["Authorization"] = f"Bearer {key}"

    def probe():
        # No dependency on id versus idx. Empty tables/RLS results still query the DB.
        status, body = fetch(f"{base_url}/rest/v1/quotes?select=*&limit=1", headers)
        if status != 200:
            raise ProbeError(f"Expected a database response, received HTTP {status}.")
        try:
            rows = json.loads(body)
        except (ValueError, UnicodeError):
            raise ProbeError("Database response is not valid JSON.") from None
        if not isinstance(rows, list) or len(rows) > 1 or any(not isinstance(row, dict) for row in rows):
            raise ProbeError("Database response is not a quotes row list.")

    retry(probe)
    return "Supabase database query succeeded (HTTP 200, valid row list)."


def report_heartbeat(success):
    url = os.environ.get("KEEPALIVE_HEARTBEAT_URL", "").strip()
    if not url:
        emit("External missed-run monitoring is NOT configured. Set KEEPALIVE_HEARTBEAT_URL.", "warning")
        return
    if not re.fullmatch(r"https://hc-ping\.com/[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}", url):
        raise ProbeError("KEEPALIVE_HEARTBEAT_URL must be a Healthchecks.io UUID ping URL.")

    def signal():
        status, body = fetch(url if success else url + "/fail", {}, limit=1024)
        # HTTP 200 can carry an error message for an invalid Healthchecks check.
        if status != 200 or body.strip() != b"OK":
            raise ProbeError("External monitor did not acknowledge the signal.")

    try:
        retry(signal)
    except ProbeError:
        raise ProbeError("External monitoring signal failed; verify the check and network.") from None
    emit("External monitor acknowledged " + ("success." if success else "failure."))


def emit(message, level=None):
    print(f"::{level}::{message}" if level else message)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as output:
            output.write(message + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("check", "report", "run"), nargs="?", default="check")
    args = parser.parse_args()
    if args.mode == "report":
        # Absent/unexpected job results must never send a success ping.
        result = os.environ.get("KEEPALIVE_RESULT", "")
        if result not in ("success", "failure", "cancelled", "skipped"):
            emit("Missing or invalid KEEPALIVE_RESULT.", "error")
            return 1
        try:
            report_heartbeat(result == "success")
        except ProbeError as error:
            emit(str(error), "error")
            return 1
        return 0

    success = True
    try:
        emit(check_database())
    except ProbeError as error:
        emit(str(error), "error")
        success = False
    if args.mode == "run":
        try:
            report_heartbeat(success)
        except ProbeError as error:
            emit(str(error), "error")
            success = False
    return 0 if success else 1


if __name__ == "__main__":
    raise SystemExit(main())
