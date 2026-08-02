#!/usr/bin/env python3
"""Fetch DeepSeek account balance and print compact JSON for the shell service.

Reads the API key from --api-key, else --api-key-file (default
~/.deepseek/api_key), else the DEEPSEEK_API_KEY environment variable.
Never prints the API key.
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


DEFAULT_ENDPOINT = "https://api.deepseek.com/user/balance"
DEFAULT_KEY_FILE = os.path.expanduser("~/.deepseek/api_key")
USER_AGENT = "inir-deepseek-balance/1.0"


def expand_path(path: str) -> Path:
    return Path(os.path.expanduser(path)).expanduser().resolve()


def error_payload(message: str, checked_at: int) -> None:
    print(json.dumps({"ok": False, "error": message, "checked_at": checked_at}))
    sys.exit(0)


def load_api_key(args: argparse.Namespace) -> str:
    if args.api_key:
        return args.api_key

    if args.api_key_file:
        try:
            raw = expand_path(args.api_key_file).read_text(encoding="utf-8").strip()
        except OSError:
            raw = ""
        if raw:
            return raw

    env_key = os.environ.get("DEEPSEEK_API_KEY")
    if env_key:
        return env_key

    error_payload(
        "no API key found (set --api-key, --api-key-file, or DEEPSEEK_API_KEY)",
        int(time.time()),
    )
    return ""  # unreachable


def main() -> int:
    parser = argparse.ArgumentParser(description="Fetch DeepSeek balance JSON")
    parser.add_argument("--api-key", default="")
    parser.add_argument("--api-key-file", default="")
    parser.add_argument("--endpoint", default=DEFAULT_ENDPOINT)
    parser.add_argument("--timeout", type=float, default=30.0)
    args = parser.parse_args()

    checked_at = int(time.time())
    api_key = load_api_key(args)

    headers = {
        "Authorization": f"Bearer {api_key}",
        "Accept": "application/json",
        "User-Agent": USER_AGENT,
    }

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
        error_payload(f"HTTP {exc.code}" + (f": {detail}" if detail else ""), checked_at)
    except Exception as exc:
        error_payload(f"{type(exc).__name__}: {exc}", checked_at)

    try:
        data = json.loads(body)
    except json.JSONDecodeError as exc:
        error_payload(f"response is not valid JSON: {exc}", checked_at)

    if not isinstance(data, dict):
        error_payload("response is not a JSON object", checked_at)

    balance_infos = data.get("balance_infos") if isinstance(data.get("balance_infos"), list) else []
    clean_infos = []
    for info in balance_infos:
        if not isinstance(info, dict):
            continue
        clean_infos.append({
            "currency": str(info.get("currency", "")),
            "total_balance": str(info.get("total_balance", "")),
            "granted_balance": str(info.get("granted_balance", "")),
            "topped_up_balance": str(info.get("topped_up_balance", "")),
        })

    payload = {
        "ok": True,
        "checked_at": checked_at,
        "is_available": bool(data.get("is_available")),
        "balance_infos": clean_infos,
        "http_status": status,
    }
    print(json.dumps(payload, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
