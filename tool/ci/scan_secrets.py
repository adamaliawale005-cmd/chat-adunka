#!/usr/bin/env python3
"""Fails if credentials appear in tracked files (keys, keystores, tokens)."""
import re
import subprocess
import sys

PATTERNS = {
    "Google API key": re.compile(r"AIza[0-9A-Za-z_\-]{35}"),
    "Private key block": re.compile(r"-----BEGIN (RSA |EC |OPENSSH |)PRIVATE KEY-----"),
    "Service account JSON": re.compile(r'"type"\s*:\s*"service_account"'),
    "GitHub token": re.compile(r"gh[pousr]_[0-9A-Za-z]{36}"),
    "FCM server key": re.compile(r"AAAA[0-9A-Za-z_\-]{7}:[0-9A-Za-z_\-]{140}"),
}
# Firebase client config is public (it ships inside every APK); its API key
# may live in this one file. Real secrets are still blocked everywhere.
PUBLIC_FIREBASE_CONFIG = "lib/config/firebase_options.dart"
FORBIDDEN_FILES = re.compile(r"(^|/)(google-services\.json|GoogleService-Info\.plist|key\.properties|.*\.jks|.*\.keystore|service-account.*\.json)$")

files = subprocess.run(["git", "ls-files"], capture_output=True, text=True, check=True).stdout.split()
problems = []
for f in files:
    if FORBIDDEN_FILES.search(f):
        problems.append(f"{f}: credential file must not be committed")
        continue
    if f.endswith((".png", ".jpg", ".jar", ".ttf", ".webp")):
        continue
    try:
        text = open(f, encoding="utf-8", errors="ignore").read()
    except OSError:
        continue
    for name, pat in PATTERNS.items():
        if name == "Google API key" and f == PUBLIC_FIREBASE_CONFIG:
            continue
        if pat.search(text) and f != "tool/ci/scan_secrets.py":
            problems.append(f"{f}: possible {name}")
if problems:
    print("Credential scan FAILED:")
    print("\n".join(problems))
    sys.exit(1)
print(f"Credential scan passed ({len(files)} tracked files).")
