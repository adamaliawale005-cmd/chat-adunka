#!/usr/bin/env python3
"""Validates Firebase settings from GitHub secrets and writes the
--dart-define file used by the build. Values are never printed."""
import json
import os
import re
import sys

EXPECTED_PROJECT = json.load(open(".firebaserc"))["projects"]["default"]
out_path = sys.argv[1]

keys = {
    "FIREBASE_API_KEY": r"^AIza[0-9A-Za-z_\-]{35}$",
    "FIREBASE_APP_ID": r"^1:\d+:android:[0-9a-f]+$",
    "FIREBASE_MESSAGING_SENDER_ID": r"^\d+$",
    "FIREBASE_PROJECT_ID": r"^[a-z0-9\-]+$",
}
optional = ["FIREBASE_STORAGE_BUCKET", "TURN_URLS", "TURN_USERNAME", "TURN_CREDENTIAL"]
flags = {"STORAGE_ENABLED": "false", "EMAIL_AUTH_ENABLED": "true", "PHONE_AUTH_ENABLED": "true"}

values, missing, invalid = {}, [], []
for k, pattern in keys.items():
    v = os.environ.get(k, "").strip()
    values[k] = v
    if not v:
        missing.append(k)
    elif not re.match(pattern, v):
        invalid.append(k)
for k in optional:
    values[k] = os.environ.get(k, "").strip()
for k, default in flags.items():
    v = os.environ.get(k, "").strip().lower()
    values[k] = v if v in ("true", "false") else default

with open(out_path, "w") as f:
    json.dump(values, f)

def note(level, title, msg):
    print(f"::{level} title={title}::{msg}")

if missing:
    note("warning", "Firebase not configured",
         "Missing secrets: " + ", ".join(missing) + ". The APK will open the setup screen.")
elif invalid:
    note("error", "Firebase settings look wrong",
         "These secrets do not have the expected format: " + ", ".join(invalid))
    sys.exit(1)
else:
    if values["FIREBASE_PROJECT_ID"] != EXPECTED_PROJECT:
        note("warning", "Firebase project",
             f"FIREBASE_PROJECT_ID is not {EXPECTED_PROJECT} (the project in .firebaserc).")
    note("notice", "Firebase configured", f"Project {values['FIREBASE_PROJECT_ID']}")
turn = "configured" if values["TURN_URLS"] else "not configured (STUN only)"
note("notice", "Features",
     f"Storage enabled: {values['STORAGE_ENABLED']}; email sign-in: {values['EMAIL_AUTH_ENABLED']}; "
     f"phone sign-in: {values['PHONE_AUTH_ENABLED']}; TURN relay: {turn}")
