#!/usr/bin/env python3
"""Fetch Grok weekly usage and print compact JSON for the shell service.

Reads the OAuth access token from ~/.grok/auth.json (Grok CLI / Grok Build).
Access tokens last about 6 hours. When one is near expiry or rejected, this
script refreshes it with the stored refresh token (the same OIDC grant Grok
uses on startup) and writes the new session back to auth.json. Never prints
tokens.

Unified Cursor + Grok billing is served from grok.com (`/rest/grok/credits`),
the same GetGrokCreditsConfig payload Grok Build's `/usage` uses. The older
cli-chat-proxy `?format=credits` path can HTTP 500 while this endpoint works.

On networks where IPv6 is broken, prefer_ipv4() reorders getaddrinfo for urllib.
"""

from __future__ import annotations

import argparse
import base64
import fcntl
import json
import os
import shutil
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path

DEFAULT_ENDPOINT = "https://grok.com/rest/grok/credits"
LEGACY_PROXY_ENDPOINT = "https://cli-chat-proxy.grok.com/v1/billing?format=credits"
DEFAULT_AUTH = os.path.expanduser("~/.grok/auth.json")
DEFAULT_VERSION_FILE = os.path.expanduser("~/.grok/version.json")
# Same buffer Grok uses (GROK_AUTH_EARLY_INVALIDATION_SECS) before it refreshes.
EARLY_REFRESH_SECONDS = 300
AUTH_LOCK_TIMEOUT_SECONDS = 20.0

PRODUCT_LABELS = {
    "PRODUCT_CURSOR": "Cursor",
    "PRODUCT_GROK_CHAT": "Grok chat",
    "PRODUCT_GROK_BUILD": "Grok Build",
}


def expand_path(path: str) -> Path:
    return Path(os.path.expanduser(path)).expanduser().resolve()


def emit(payload: dict) -> int:
    print(json.dumps(payload, separators=(",", ":")))
    return 0


def fail(checked_at: int, error: str) -> int:
    return emit({"ok": False, "error": error, "checked_at": checked_at})


@contextmanager
def prefer_ipv4():
    orig = socket.getaddrinfo

    def _ipv4_first(*args, **kwargs):
        infos = orig(*args, **kwargs)
        v4 = [i for i in infos if i[0] == socket.AF_INET]
        return v4 or infos

    socket.getaddrinfo = _ipv4_first  # type: ignore[assignment]
    try:
        yield
    finally:
        socket.getaddrinfo = orig


def grok_version() -> str:
    try:
        data = json.loads(Path(DEFAULT_VERSION_FILE).read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return "1.0.60"
    version = data.get("version") if isinstance(data, dict) else None
    return version if isinstance(version, str) and version else "1.0.60"


def _read_auth_document(auth_file: Path) -> dict:
    try:
        raw = auth_file.read_text(encoding="utf-8")
    except OSError as exc:
        raise ValueError(f"could not read auth file: {exc}") from exc

    try:
        data = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise ValueError(f"auth file is not valid JSON: {exc}") from exc

    if not isinstance(data, dict) or not data:
        raise ValueError("no OAuth entries in auth file")
    return data


def _select_entry(data: dict) -> tuple[str, dict]:
    found: tuple[str, dict] | None = None
    for key, value in data.items():
        if isinstance(value, dict) and isinstance(value.get("key"), str) and value.get("key"):
            found = (str(key), value)
            if str(key).startswith("https://auth.x.ai"):
                break
    if found is None:
        raise ValueError("missing access token")
    return found


def _creds(entry: dict) -> tuple[str, str, str]:
    token = entry.get("key")
    if not isinstance(token, str) or not token:
        raise ValueError("missing access token")
    email = entry.get("email") if isinstance(entry.get("email"), str) else ""
    user_id = entry.get("user_id") if isinstance(entry.get("user_id"), str) else ""
    if not user_id:
        user_id = entry.get("principal_id") if isinstance(entry.get("principal_id"), str) else ""
    return token, email, user_id


def _jwt_times(token: str) -> tuple[int | None, int | None]:
    try:
        payload = token.split(".", 2)[1]
        payload += "=" * (-len(payload) % 4)
        claims = json.loads(base64.urlsafe_b64decode(payload))
    except (IndexError, ValueError, json.JSONDecodeError, UnicodeError):
        return None, None
    if not isinstance(claims, dict):
        return None, None

    def _unix(value: object) -> int | None:
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            return None
        return int(value)

    return _unix(claims.get("exp")), _unix(claims.get("iat"))


def _entry_expiry(entry: dict) -> float | None:
    raw = entry.get("expires_at")
    if isinstance(raw, str) and raw:
        try:
            return datetime.fromisoformat(raw.replace("Z", "+00:00")).timestamp()
        except ValueError:
            pass
    token = entry.get("key")
    if isinstance(token, str) and token:
        exp, _iat = _jwt_times(token)
        if exp is not None:
            return float(exp)
    return None


def _seconds_left(entry: dict) -> float | None:
    exp = _entry_expiry(entry)
    if exp is None:
        return None
    return exp - time.time()


def _needs_refresh(entry: dict) -> bool:
    left = _seconds_left(entry)
    return left is not None and left <= EARLY_REFRESH_SECONDS


def _expired(entry: dict) -> bool:
    left = _seconds_left(entry)
    return left is not None and left <= 0


def _session_owner_alive(auth_file: Path) -> bool:
    """True when the Grok process that last locked auth.json is still running.

    While it is alive it refreshes the session itself. Refreshing from here at
    the same time would rotate the refresh token out from under that process.
    """
    lock_path = auth_file.with_name(auth_file.name + ".lock")
    try:
        raw = lock_path.read_text(encoding="utf-8").strip()
    except OSError:
        return False
    pid_text = raw.split(":", 1)[0]
    if not pid_text.isdigit():
        return False
    pid = int(pid_text)
    if pid <= 0 or pid == os.getpid():
        return False
    try:
        os.kill(pid, 0)
    except OSError:
        return False
    try:
        comm = Path(f"/proc/{pid}/comm").read_text(encoding="utf-8").strip()
    except OSError:
        return True
    return "grok" in comm


def _rfc3339(dt: datetime) -> str:
    utc = dt.astimezone(timezone.utc)
    return utc.strftime("%Y-%m-%dT%H:%M:%S.") + f"{utc.microsecond:06d}000Z"


def _oauth_error(status: int, body: str) -> str:
    code = ""
    description = ""
    try:
        data = json.loads(body)
    except json.JSONDecodeError:
        data = None
    if isinstance(data, dict):
        if isinstance(data.get("error"), str):
            code = data["error"]
        if isinstance(data.get("error_description"), str):
            description = data["error_description"][:160]
    if code == "invalid_grant":
        return (
            "Grok refresh token is no longer valid. Run `grok login` once; "
            "after that, usage can refresh the session on its own."
        )
    if code:
        extra = f" ({description})" if description else ""
        return f"token refresh failed: {code}{extra}"
    return f"token refresh failed: HTTP {status}"


def _refresh_request(entry: dict, timeout: float) -> dict:
    refresh = entry.get("refresh_token")
    client_id = entry.get("oidc_client_id")
    issuer = entry.get("oidc_issuer") if isinstance(entry.get("oidc_issuer"), str) else ""
    if not isinstance(refresh, str) or not refresh:
        raise ValueError("auth file has no refresh token. Run `grok login` once.")
    if not isinstance(client_id, str) or not client_id:
        raise ValueError("auth file has no OIDC client id. Run `grok login` once.")
    if not issuer:
        issuer = "https://auth.x.ai"
    url = issuer.rstrip("/") + "/oauth2/token"
    form = urllib.parse.urlencode({
        "grant_type": "refresh_token",
        "refresh_token": refresh,
        "client_id": client_id,
    }).encode()
    req = urllib.request.Request(
        url,
        data=form,
        method="POST",
        headers={
            "Accept": "application/json",
            "Content-Type": "application/x-www-form-urlencoded",
            "User-Agent": f"grok-cli/{grok_version()}",
        },
    )
    try:
        with prefer_ipv4(), urllib.request.urlopen(req, timeout=timeout) as resp:
            body = resp.read().decode("utf-8", errors="replace")
    except urllib.error.HTTPError as exc:
        detail = ""
        try:
            detail = exc.read().decode("utf-8", errors="replace")[:500]
        except Exception:
            pass
        raise ValueError(_oauth_error(exc.code, detail)) from exc
    except ValueError:
        raise
    except Exception as exc:
        raise ValueError(f"token refresh failed: {type(exc).__name__}") from exc

    try:
        payload = json.loads(body)
    except json.JSONDecodeError as exc:
        raise ValueError("token refresh returned invalid JSON") from exc
    if not isinstance(payload, dict) or not isinstance(payload.get("access_token"), str) or not payload.get("access_token"):
        raise ValueError("token refresh returned no access token")
    return payload


def _apply_refresh(entry: dict, payload: dict) -> dict:
    updated = dict(entry)
    access = payload["access_token"]
    updated["key"] = access
    rotated = payload.get("refresh_token")
    if isinstance(rotated, str) and rotated:
        updated["refresh_token"] = rotated

    now = datetime.now(timezone.utc)
    jwt_exp, jwt_iat = _jwt_times(access)
    issued = datetime.fromtimestamp(jwt_iat, timezone.utc) if jwt_iat else now
    expires_in = payload.get("expires_in")
    if jwt_exp:
        exp_dt = datetime.fromtimestamp(jwt_exp, timezone.utc)
    elif isinstance(expires_in, (int, float)) and not isinstance(expires_in, bool) and expires_in > 0:
        exp_dt = datetime.fromtimestamp(now.timestamp() + float(expires_in), timezone.utc)
    else:
        exp_dt = datetime.fromtimestamp(now.timestamp() + 6 * 3600, timezone.utc)
    updated["create_time"] = _rfc3339(issued)
    updated["expires_at"] = _rfc3339(exp_dt)
    return updated


def _atomic_write(path: Path, text: str) -> None:
    tmp = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    try:
        blob = text.encode("utf-8")
        view = memoryview(blob)
        while view:
            written = os.write(fd, view)
            if written <= 0:
                raise OSError(f"short write to {tmp}")
            view = view[written:]
        os.fsync(fd)
    except Exception:
        os.close(fd)
        tmp.unlink(missing_ok=True)
        raise
    os.close(fd)
    os.chmod(tmp, 0o600)
    try:
        os.replace(tmp, path)
    except Exception:
        tmp.unlink(missing_ok=True)
        raise
    dir_fd = os.open(path.parent, os.O_RDONLY)
    try:
        os.fsync(dir_fd)
    finally:
        os.close(dir_fd)
    os.chmod(path, 0o600)


@contextmanager
def _auth_file_lock(auth_file: Path, timeout: float):
    """Exclusive lock on auth.json.lock, matching Grok's refresh critical section."""
    lock_path = auth_file.with_name(auth_file.name + ".lock")
    fd = os.open(lock_path, os.O_CREAT | os.O_RDWR, 0o644)
    acquired = False
    deadline = time.monotonic() + timeout
    try:
        while True:
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                acquired = True
                break
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    raise TimeoutError("timed out waiting for auth.json.lock") from None
                time.sleep(0.2)
        os.ftruncate(fd, 0)
        os.lseek(fd, 0, os.SEEK_SET)
        os.write(fd, f"{os.getpid()}:{int(time.time())}".encode())
        yield
    finally:
        if acquired:
            try:
                fcntl.flock(fd, fcntl.LOCK_UN)
            except OSError:
                pass
        os.close(fd)


class AuthPersistError(ValueError):
    """Refresh succeeded at the IdP, but auth.json was not updated."""


def _usable_without_refresh(entry: dict) -> bool:
    left = _seconds_left(entry)
    return left is None or left > 0


def ensure_access_token(
    auth_file: Path,
    *,
    force: bool = False,
    rejected_token: str | None = None,
    timeout: float = AUTH_LOCK_TIMEOUT_SECONDS,
) -> tuple[str, str, str, bool]:
    """Return access token, email, user id, and whether a new token was stored.

    Refreshes only inside the auth file lock, and only when the token is inside
    the early-refresh window, already expired, or was just rejected. If Grok
    refreshed the file first, the new disk token is used as-is.
    """
    data = _read_auth_document(auth_file)
    _key, entry = _select_entry(data)
    if not force and not _needs_refresh(entry):
        return (*_creds(entry), False)

    # A running Grok owns this session and will refresh it. Only take over when
    # the access token is already expired and Grok has not written a new one.
    if not force and _session_owner_alive(auth_file) and not _expired(entry):
        return (*_creds(entry), False)
    if not force and _session_owner_alive(auth_file) and _expired(entry):
        deadline = time.monotonic() + min(15.0, timeout)
        while time.monotonic() < deadline:
            time.sleep(0.5)
            data = _read_auth_document(auth_file)
            _key, entry = _select_entry(data)
            if not _expired(entry):
                return (*_creds(entry), False)

    try:
        with _auth_file_lock(auth_file, timeout):
            data = _read_auth_document(auth_file)
            key, entry = _select_entry(data)
            if force and rejected_token and entry.get("key") != rejected_token and not _needs_refresh(entry):
                return (*_creds(entry), False)
            if not force and not _needs_refresh(entry):
                return (*_creds(entry), False)
            payload = _refresh_request(entry, timeout=min(timeout, 20.0))
            updated = _apply_refresh(entry, payload)
            data[key] = updated
            try:
                _atomic_write(auth_file, json.dumps(data, indent=2, ensure_ascii=False) + "\n")
            except OSError as exc:
                raise AuthPersistError(f"refreshed the Grok token but could not save auth.json: {exc}") from exc
    except AuthPersistError:
        raise
    except TimeoutError as exc:
        if not force and _usable_without_refresh(entry):
            print("Grok auth lock is busy; using the current access token", file=sys.stderr)
            return (*_creds(entry), False)
        raise ValueError("auth.json is locked by Grok; could not refresh the access token") from exc
    except ValueError:
        if not force and _usable_without_refresh(entry):
            print("Grok token refresh failed; using the current access token", file=sys.stderr)
            return (*_creds(entry), False)
        raise

    token, email, user_id = _creds(updated)
    left = _seconds_left(updated)
    if left is not None:
        print(f"refreshed Grok access token (expires in {left / 3600:.1f}h)", file=sys.stderr)
    else:
        print("refreshed Grok access token", file=sys.stderr)
    return token, email, user_id, True


def load_auth(auth_file: Path) -> tuple[str, str, str]:
    data = _read_auth_document(auth_file)
    _key, entry = _select_entry(data)
    return _creds(entry)


def client_headers(token: str, email: str, user_id: str) -> dict[str, str]:
    # Matches xai-grok-shell billing.rs (grok.com / cli-chat-proxy).
    version = grok_version()
    headers = {
        "Authorization": f"Bearer {token}",
        "X-XAI-Token-Auth": "xai-grok-cli",
        "Accept": "application/json",
        "User-Agent": f"grok-cli/{version}",
        "x-grok-client-version": version,
        "x-grok-client-identifier": "grok-shell",
        "x-grok-client-mode": "shell",
    }
    if user_id:
        headers["x-userid"] = user_id
    if email:
        headers["x-email"] = email
    return headers


def humanize_enum(value: object) -> str:
    if not isinstance(value, str) or not value:
        return ""
    text = value
    for prefix in ("USAGE_PERIOD_TYPE_", "TOP_UP_METHOD_", "PRODUCT_"):
        if text.startswith(prefix):
            text = text[len(prefix):]
            break
    words = text.replace("_", " ").strip().lower()
    if not words:
        return ""
    return words[:1].upper() + words[1:]


def product_label(raw: object) -> str:
    if not isinstance(raw, str) or not raw:
        return ""
    return PRODUCT_LABELS.get(raw, humanize_enum(raw) or raw)


def parse_timestamp(value: object) -> tuple[int | None, str]:
    if not isinstance(value, str) or not value:
        return None, ""
    try:
        dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None, value
    return int(dt.timestamp()), dt.astimezone().strftime("%Y-%m-%d %H:%M %Z")


def number_or_none(value: object) -> float | None:
    if isinstance(value, bool) or value is None:
        return None
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, str):
        try:
            return float(value)
        except ValueError:
            return None
    return None


def nested_val(node: object) -> float | None:
    if isinstance(node, dict):
        return number_or_none(node.get("val"))
    return number_or_none(node)


def http_get(url: str, headers: dict[str, str], timeout: float) -> tuple[int | None, str, str | None]:
    curl = shutil.which("curl")
    if curl:
        return _http_get_curl(curl, url, headers, timeout)
    return _http_get_urllib(url, headers, timeout)


def _http_get_curl(curl: str, url: str, headers: dict[str, str], timeout: float) -> tuple[int | None, str, str | None]:
    cmd = [curl, "-sS", "--http2", "--ipv4", "-m", str(max(1, int(timeout))), "-w", "\n%{http_code}"]
    for key, value in headers.items():
        cmd.extend(["-H", f"{key}: {value}"])
    cmd.append(url)
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout + 5, check=False)
    except subprocess.TimeoutExpired:
        return None, "", "request timed out"
    raw = proc.stdout or ""
    body, sep, code_s = raw.rpartition("\n")
    if not sep:
        detail = (proc.stderr or "").strip()
        return None, "", detail or "curl produced no output"
    try:
        code = int(code_s.strip())
    except ValueError:
        return None, raw, "curl status parse failed"
    if code >= 400:
        return code, body, f"HTTP {code}: {body.strip()[:200]}"
    if proc.returncode != 0 and code == 0:
        return None, body, (proc.stderr or "").strip() or f"curl exit {proc.returncode}"
    return code, body, None


def fetch_subscription_tier(token: str, email: str, user_id: str, timeout: float) -> str:
    url = "https://grok.com/rest/subscriptions"
    status, body, error = http_get(url, client_headers(token, email, user_id), timeout)
    if error is not None or status is None or status < 200 or status >= 300 or not body:
        return ""
    try:
        data = json.loads(body)
    except json.JSONDecodeError:
        return ""
    if not isinstance(data, dict):
        return ""
    dominant = data.get("dominantPlan")
    if isinstance(dominant, dict):
        plan = dominant.get("plan")
        if isinstance(plan, str) and plan:
            return plan[:1].upper() + plan[1:]
    subs = data.get("subscriptions")
    if isinstance(subs, list) and subs:
        first = subs[0]
        if isinstance(first, dict):
            tier = first.get("tier")
            if isinstance(tier, str) and tier:
                return humanize_enum(tier.replace("SUBSCRIPTION_TIER_", ""))
    return ""


def usage_payload(config: dict, checked_at: int, *, tier: str) -> dict:
    period = config.get("currentPeriod") if isinstance(config.get("currentPeriod"), dict) else {}
    used = number_or_none(config.get("creditUsagePercent"))
    remaining = None if used is None else max(0.0, min(100.0, 100.0 - used))

    products = []
    raw_products = config.get("productUsage")
    if isinstance(raw_products, list):
        for item in raw_products:
            if not isinstance(item, dict):
                continue
            raw_name = item.get("product") if isinstance(item.get("product"), str) else ""
            products.append({
                "product": product_label(raw_name),
                "usage_percent": number_or_none(item.get("usagePercent")),
            })

    period_end_at, period_end = parse_timestamp(period.get("end"))
    _, period_start = parse_timestamp(period.get("start"))
    _, billing_start = parse_timestamp(config.get("billingPeriodStart"))
    billing_end_at, billing_end = parse_timestamp(config.get("billingPeriodEnd"))
    return {
        "ok": True,
        "stale": False,
        "error": "",
        "checked_at": checked_at,
        "subscription_tier": tier,
        "period_type": humanize_enum(period.get("type")),
        "period_start": period_start,
        "period_end": period_end,
        "period_end_at": period_end_at,
        "used_percent": used,
        "remaining_percent": remaining,
        "products": products,
        "unified_billing": bool(config.get("isUnifiedBillingUser")),
        "prepaid_balance": nested_val(config.get("prepaidBalance")),
        "on_demand_cap": nested_val(config.get("onDemandCap")),
        "top_up_method": humanize_enum(config.get("topUpMethod")),
        "billing_period_start": billing_start,
        "billing_period_end": billing_end,
        "billing_period_end_at": billing_end_at,
    }


def _http_get_urllib(url: str, headers: dict[str, str], timeout: float) -> tuple[int | None, str, str | None]:
    req = urllib.request.Request(url, headers=headers, method="GET")
    try:
        with prefer_ipv4(), urllib.request.urlopen(req, timeout=timeout) as resp:
            body = resp.read().decode("utf-8", errors="replace")
            status = getattr(resp, "status", 200)
            return status, body, None
    except urllib.error.HTTPError as exc:
        detail = ""
        try:
            detail = exc.read().decode("utf-8", errors="replace")[:200]
        except Exception:
            pass
        return exc.code, detail, f"HTTP {exc.code}" + (f": {detail}" if detail else "")
    except Exception as exc:
        return None, "", f"{type(exc).__name__}: {exc}"


def parse_billing_response(body: str, checked_at: int, tier: str) -> dict | None:
    try:
        data = json.loads(body)
    except json.JSONDecodeError as exc:
        return {"ok": False, "error": f"response is not valid JSON: {exc}", "checked_at": checked_at}

    if not isinstance(data, dict):
        return {"ok": False, "error": "response is not a JSON object", "checked_at": checked_at}

    config = data.get("config") if isinstance(data.get("config"), dict) else {}
    if number_or_none(config.get("creditUsagePercent")) is None:
        return {
            "ok": False,
            "error": "billing response has no weekly credit usage",
            "checked_at": checked_at,
        }

    return usage_payload(config, checked_at, tier=tier)


def main() -> int:
    parser = argparse.ArgumentParser(description="Fetch Grok weekly usage JSON")
    parser.add_argument("--auth-file", default=DEFAULT_AUTH)
    parser.add_argument("--endpoint", default=DEFAULT_ENDPOINT)
    parser.add_argument("--timeout", type=float, default=30.0)
    args = parser.parse_args()

    checked_at = int(time.time())
    auth_file = expand_path(args.auth_file)

    def fetch_with(token: str, email: str, user_id: str) -> tuple[dict | None, str, int | None]:
        headers = client_headers(token, email, user_id)
        tier = fetch_subscription_tier(token, email, user_id, min(args.timeout, 15.0))
        endpoints = [args.endpoint.rstrip("/")]
        if endpoints[0] != DEFAULT_ENDPOINT and endpoints[0] != LEGACY_PROXY_ENDPOINT.rstrip("/"):
            pass
        elif endpoints[0] == DEFAULT_ENDPOINT:
            endpoints.append(LEGACY_PROXY_ENDPOINT)
        elif "cli-chat-proxy" in endpoints[0]:
            endpoints.insert(0, DEFAULT_ENDPOINT)

        last_error = "billing request failed"
        last_status: int | None = None
        saw_unauthorized = False
        for url in endpoints:
            status, body, error = http_get(url, headers, args.timeout)
            last_status = status
            live_ok = error is None and status is not None and 200 <= status < 300 and bool(body)
            if not live_ok:
                last_error = error or f"HTTP {status}"
                if status == 401:
                    saw_unauthorized = True
                if "Failed to serialize billing response" in last_error:
                    last_error = (
                        "Grok billing proxy returned HTTP 500 (weekly credits serialization failed)"
                    )
                continue
            result = parse_billing_response(body, checked_at, tier)
            if result is None:
                continue
            if not result.get("ok"):
                last_error = str(result.get("error") or last_error)
                continue
            return result, "", status
        if saw_unauthorized:
            last_status = 401
        return None, last_error, last_status

    try:
        token, email, user_id, refreshed = ensure_access_token(auth_file)
    except ValueError as exc:
        return fail(checked_at, str(exc))

    result, last_error, status = fetch_with(token, email, user_id)
    if result is None and status == 401 and not refreshed:
        try:
            token, email, user_id, _refreshed = ensure_access_token(
                auth_file, force=True, rejected_token=token,
            )
        except ValueError as exc:
            return fail(checked_at, str(exc))
        result, last_error, status = fetch_with(token, email, user_id)

    if result is not None:
        return emit(result)
    return fail(checked_at, last_error)


if __name__ == "__main__":
    sys.exit(main())
