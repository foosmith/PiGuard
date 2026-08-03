#!/usr/bin/env python3
"""Report App Store Connect build + review status for PiGuard.

Needs an App Store Connect API key. See docs/app-store-submission.md.

    export ASC_KEY_ID=XXXXXXXXXX
    export ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
    ./mac/scripts/asc-status.py

Reads the private key from ~/.appstoreconnect/private_keys/AuthKey_$ASC_KEY_ID.p8
(override with ASC_KEY_PATH). Uses only the stdlib plus the openssl binary, so there
is nothing to pip install.
"""

import base64
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

BUNDLE_ID = "com.foosmith.PiGuard"
API = "https://api.appstoreconnect.apple.com/v1"


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def der_to_raw(der: bytes) -> bytes:
    """Convert an ECDSA DER signature to the raw 64-byte R||S form a JWS needs."""
    if der[0] != 0x30:
        raise ValueError("not a DER sequence")
    # Skip SEQUENCE tag and its length (short or long form).
    i = 2 if der[1] < 0x80 else 3 + (der[1] & 0x7F) - 1

    def read_int(pos):
        if der[pos] != 0x02:
            raise ValueError("expected DER INTEGER")
        length = der[pos + 1]
        val = der[pos + 2 : pos + 2 + length]
        return val.lstrip(b"\x00").rjust(32, b"\x00"), pos + 2 + length

    r, i = read_int(i)
    s, _ = read_int(i)
    return r + s


def make_token(key_id: str, issuer_id: str, key_path: str) -> str:
    header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    now = int(time.time())
    payload = {
        "iss": issuer_id,
        "iat": now,
        "exp": now + 1200,  # Apple rejects anything over 20 minutes
        "aud": "appstoreconnect-v1",
    }
    signing_input = f"{b64url(json.dumps(header).encode())}.{b64url(json.dumps(payload).encode())}"
    try:
        der = subprocess.run(
            ["openssl", "dgst", "-sha256", "-sign", key_path],
            input=signing_input.encode(),
            capture_output=True,
            check=True,
        ).stdout
    except subprocess.CalledProcessError as exc:
        sys.exit(f"openssl failed to sign with {key_path}:\n{exc.stderr.decode()}")
    return f"{signing_input}.{b64url(der_to_raw(der))}"


def get(path: str, token: str):
    req = urllib.request.Request(
        f"{API}/{path}", headers={"Authorization": f"Bearer {token}"}
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.load(resp)
    except urllib.error.HTTPError as exc:
        body = exc.read().decode(errors="replace")
        if exc.code == 401:
            sys.exit("401 Unauthorized — check ASC_KEY_ID, ASC_ISSUER_ID, and the .p8 file.")
        sys.exit(f"HTTP {exc.code} on {path}:\n{body}")


def main() -> None:
    key_id = os.environ.get("ASC_KEY_ID")
    issuer_id = os.environ.get("ASC_ISSUER_ID")
    if not key_id or not issuer_id:
        sys.exit("Set ASC_KEY_ID and ASC_ISSUER_ID. See docs/app-store-submission.md.")
    key_path = os.environ.get(
        "ASC_KEY_PATH",
        os.path.expanduser(f"~/.appstoreconnect/private_keys/AuthKey_{key_id}.p8"),
    )
    if not os.path.exists(key_path):
        sys.exit(f"Private key not found: {key_path}")

    token = make_token(key_id, issuer_id, key_path)

    apps = get(f"apps?filter[bundleId]={BUNDLE_ID}", token)["data"]
    if not apps:
        sys.exit(f"No app record found for {BUNDLE_ID} on this account.")
    app = apps[0]
    app_id = app["id"]
    print(f"{app['attributes'].get('name', '?')}  ({BUNDLE_ID})\n")

    print("Versions")
    versions = get(f"apps/{app_id}/appStoreVersions?limit=5", token)["data"]
    if not versions:
        print("  (none)")
    for ver in versions:
        attrs = ver["attributes"]
        # Apple renamed appStoreState -> appVersionState; tolerate either.
        state = attrs.get("appVersionState") or attrs.get("appStoreState") or "?"
        created = (attrs.get("createdDate") or "")[:10]
        print(f"  {attrs.get('versionString', '?'):<10} {state:<28} created {created}")

    print("\nBuilds")
    builds = get(f"builds?filter[app]={app_id}&limit=5", token)["data"]
    if not builds:
        print("  (none)")
    for build in builds:
        attrs = build["attributes"]
        uploaded = (attrs.get("uploadedDate") or "")[:10]
        expired = " EXPIRED" if attrs.get("expired") else ""
        print(
            f"  build {attrs.get('version', '?'):<6} "
            f"{attrs.get('processingState', '?'):<12} uploaded {uploaded}{expired}"
        )


if __name__ == "__main__":
    main()
