#!/usr/bin/env python3
"""Fetch Codex rate-limit usage and print compact JSON for the shell service.

Reads tokens from the local Codex auth file (default ~/.codex/auth.json).
Never prints the access token.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path


DEFAULT_ENDPOINT = "https://chatgpt.com/backend-api/wham/usage"
DEFAULT_AUTH = os.path.expanduser("~/.codex/auth.json")
USER_AGENT = "inir-codex-usage/1.0"


def expand_path(path: str) -> Path:
    return Path(os.path.expanduser(path)).expanduser().resolve()


def load_auth(auth_file: Path) -> tuple[str, str | None]:
    try:
        raw = auth_file.read_text(encoding="utf-8")
    except OSError as exc:
        raise SystemExit(json.dumps({
            "ok": False,
            "error": f"could not read auth file: {exc}",
            "checked_at": int(time.time()),
        })) from exc

    try:
        auth = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise SystemExit(json.dumps({
            "ok": False,
            "error": f"auth file is not valid JSON: {exc}",
            "checked_at": int(time.time()),
        })) from exc

    tokens = auth.get("tokens") if isinstance(auth, dict) else None
    if not isinstance(tokens, dict):
        tokens = {}

    token = tokens.get("access_token")
    account_id = tokens.get("account_id")
    if not isinstance(token, str) or not token:
        raise SystemExit(json.dumps({
            "ok": False,
            "error": "missing access token",
            "checked_at": int(time.time()),
        }))

    account = account_id if isinstance(account_id, str) and account_id else None
    return token, account


def window_status(window: object, checked_at: int) -> dict | None:
    if not isinstance(window, dict):
        return None

    used = window.get("used_percent")
    try:
        used_f = float(used) if used is not None else None
    except (TypeError, ValueError):
        used_f = None

    remaining = None
    if used_f is not None:
        remaining = max(0.0, min(100.0, 100.0 - used_f))

    reset_at = window.get("reset_at")
    try:
        reset_at_i = int(reset_at) if reset_at is not None else None
    except (TypeError, ValueError):
        reset_at_i = None

    reset_after = window.get("reset_after_seconds")
    try:
        reset_after_i = int(reset_after) if reset_after is not None else None
    except (TypeError, ValueError):
        reset_after_i = None

    if reset_at_i is None and reset_after_i is not None:
        reset_at_i = checked_at + reset_after_i

    limit_window = window.get("limit_window_seconds")
    try:
        limit_window_i = int(limit_window) if limit_window is not None else None
    except (TypeError, ValueError):
        limit_window_i = None

    return {
        "used_percent": used_f,
        "remaining_percent": remaining,
        "reset_at": reset_at_i,
        "reset_after_seconds": reset_after_i,
        "limit_window_seconds": limit_window_i,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Fetch Codex usage JSON")
    parser.add_argument("--auth-file", default=DEFAULT_AUTH)
    parser.add_argument("--endpoint", default=DEFAULT_ENDPOINT)
    parser.add_argument("--timeout", type=float, default=30.0)
    args = parser.parse_args()

    checked_at = int(time.time())
    token, account_id = load_auth(expand_path(args.auth_file))

    headers = {
        "Authorization": f"Bearer {token}",
        "Accept": "application/json",
        "User-Agent": USER_AGENT,
    }
    if account_id:
        headers["chatgpt-account-id"] = account_id

    req = urllib.request.Request(args.endpoint, headers=headers, method="GET")
    try:
        with urllib.request.urlopen(req, timeout=args.timeout) as resp:
            body = resp.read().decode("utf-8", errors="replace")
            status = getattr(resp, "status", 200)
    except urllib.error.HTTPError as exc:
        detail = ""
        try:
            detail = exc.read().decode("utf-8", errors="replace")[:200]
        except Exception:
            pass
        print(json.dumps({
            "ok": False,
            "error": f"HTTP {exc.code}" + (f": {detail}" if detail else ""),
            "checked_at": checked_at,
        }))
        return 0
    except Exception as exc:
        print(json.dumps({
            "ok": False,
            "error": f"{type(exc).__name__}: {exc}",
            "checked_at": checked_at,
        }))
        return 0

    try:
        data = json.loads(body)
    except json.JSONDecodeError as exc:
        print(json.dumps({
            "ok": False,
            "error": f"response is not valid JSON: {exc}",
            "checked_at": checked_at,
        }))
        return 0

    if not isinstance(data, dict):
        print(json.dumps({
            "ok": False,
            "error": "response is not a JSON object",
            "checked_at": checked_at,
        }))
        return 0

    rate_limit = data.get("rate_limit") if isinstance(data.get("rate_limit"), dict) else {}
    payload = {
        "ok": True,
        "checked_at": checked_at,
        "email": data.get("email"),
        "plan_type": data.get("plan_type"),
        "allowed": rate_limit.get("allowed"),
        "limit_reached": rate_limit.get("limit_reached"),
        "five_hour": window_status(rate_limit.get("primary_window"), checked_at),
        "weekly": window_status(rate_limit.get("secondary_window"), checked_at),
        "http_status": status,
    }
    print(json.dumps(payload, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
