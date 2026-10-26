#!/usr/bin/env python3
"""Validates Firebase settings from GitHub secrets and writes the
--dart-define file used by the build.

Secret values are never printed. Problems are described by their shape
only (for example "this is a Web app id"), so they can be fixed safely.
"""
import json
import os
import re
import sys
import urllib.request

EXPECTED_PROJECT = json.load(open(".firebaserc"))["projects"]["default"]
# Other Firebase project names that were used during setup by mistake.
KNOWN_OTHER_PROJECTS = ["chat-aduunka", "chat-adunka"]


def describe(v: str) -> str:
    """Describes a value without revealing it (GitHub masks secrets anyway)."""
    if v == EXPECTED_PROJECT:
        return f"the project id '{EXPECTED_PROJECT}'"
    if v.rstrip(".") == EXPECTED_PROJECT:
        return f"the project id '{EXPECTED_PROJECT}' followed by extra characters"
    for o in KNOWN_OTHER_PROJECTS:
        if v == o:
            return f"the id of the other project '{o}'"
    for o in KNOWN_OTHER_PROJECTS:
        if o in v:
            return f"a value from the other project '{o}'"
    if re.fullmatch(r"1:\d+:[a-z]+:[0-9a-f]+", v):
        return "an app id"
    if re.fullmatch(r"\d+", v):
        return "a number (looks like a project number)"
    if v.startswith("AIza"):
        return "an API key"
    if v.startswith("{") or "project_info" in v:
        return "JSON text (paste only the single value, not the file)"
    return f"an unrecognised value of {len(v)} characters"


def api_key_project(key: str):
    """Asks Google which Firebase project an API key belongs to (read-only)."""
    url = "https://www.googleapis.com/identitytoolkit/v3/relyingparty/getProjectConfig?key=" + key
    try:
        with urllib.request.urlopen(url, timeout=20) as r:
            data = json.load(r)
            # Default authorized domains are <project-id>.firebaseapp.com / .web.app,
            # which reveal the project id behind the number.
            for d in data.get("authorizedDomains", []):
                mm = re.fullmatch(r"([a-z0-9\-]+)\.(firebaseapp\.com|web\.app)", d)
                if mm:
                    return mm.group(1), None
            return data.get("projectId"), None
    except urllib.error.HTTPError as e:
        try:
            msg = json.load(e).get("error", {}).get("message", "")
        except Exception:
            msg = ""
        return None, f"HTTP {e.code} {msg}".strip()
    except Exception as e:  # network problems should not hide other checks
        return None, type(e).__name__
out_path = sys.argv[1]


def note(level, title, msg):
    print(f"::{level} title={title}::{msg}")


def clean(v: str) -> str:
    # People often paste values with quotes, a trailing comma or spaces.
    v = v.strip().strip(",").strip()
    if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
        v = v[1:-1].strip()
    return v


required = ["FIREBASE_API_KEY", "FIREBASE_APP_ID", "FIREBASE_MESSAGING_SENDER_ID", "FIREBASE_PROJECT_ID"]
optional = ["FIREBASE_STORAGE_BUCKET", "FIREBASE_WEB_APP_ID", "TURN_URLS", "TURN_USERNAME", "TURN_CREDENTIAL"]
flags = {"STORAGE_ENABLED": "false", "EMAIL_AUTH_ENABLED": "true", "PHONE_AUTH_ENABLED": "true"}

values = {k: clean(os.environ.get(k, "")) for k in required + optional}
for k, default in flags.items():
    v = os.environ.get(k, "").strip().lower()
    values[k] = v if v in ("true", "false") else default

with open(out_path, "w") as f:
    json.dump(values, f)


def official_web_config():
    """Public Firebase web config of the official project (not secret: it is
    served to every browser). Used to find the project's API key, number and
    app id when the GitHub secrets are wrong."""
    for host in (f"{EXPECTED_PROJECT}.firebaseapp.com", f"{EXPECTED_PROJECT}.web.app"):
        try:
            with urllib.request.urlopen(f"https://{host}/__/firebase/init.json", timeout=20) as r:
                return json.load(r), host
        except Exception as e:
            last = f"{host}: {type(e).__name__} {getattr(e, 'code', '')}"
    return None, last


web, where = official_web_config()
os.makedirs("ci-logs", exist_ok=True)
with open("ci-logs/official-web-config.json", "w") as f:
    json.dump({"source": where, "config": web}, f, indent=2)
if web:
    note("notice", "Official project", f"Read the public web config of '{EXPECTED_PROJECT}' from {where}.")
else:
    note("warning", "Official project", f"Could not read the public web config ({where}).")


missing = [k for k in required if not values[k]]
errors = []


def official_in_code():
    """Values committed in lib/config/firebase_options.dart, if filled in."""
    src = open("lib/config/firebase_options.dart").read()
    def get(name):
        mm = re.search(rf"static const String {name} = '([^']*)';", src)
        return mm.group(1) if mm else ""
    return {k: get(k) for k in ("projectId", "apiKey", "appId", "messagingSenderId")}


code_cfg = official_in_code()
if code_cfg["apiKey"] and code_cfg["appId"] and code_cfg["messagingSenderId"]:
    # The app ignores the secrets in this case; validate the committed values.
    os.environ["FIREBASE_SOURCE"] = "code"
    values["FIREBASE_API_KEY"] = code_cfg["apiKey"]
    values["FIREBASE_APP_ID"] = code_cfg["appId"]
    values["FIREBASE_MESSAGING_SENDER_ID"] = code_cfg["messagingSenderId"]
    values["FIREBASE_PROJECT_ID"] = code_cfg["projectId"]
    missing = []
    note("notice", "Firebase source",
         "Using the official values committed in lib/config/firebase_options.dart; GitHub secrets are ignored.")

if missing:
    note("warning", "Firebase not configured",
         "Missing secrets: " + ", ".join(missing) + ". The APK will open the setup screen.")
else:
    api_key = values["FIREBASE_API_KEY"]
    app_id = values["FIREBASE_APP_ID"]
    sender = values["FIREBASE_MESSAGING_SENDER_ID"]
    project = values["FIREBASE_PROJECT_ID"]

    if not re.fullmatch(r"AIza[0-9A-Za-z_\-]{35}", api_key):
        errors.append("FIREBASE_API_KEY is not an Android API key (should start with AIza and be 39 characters; "
                      "use client[0].api_key[0].current_key from google-services.json).")

    m = re.fullmatch(r"1:(\d+):([a-z]+):([0-9a-f]+)", app_id)
    if not m:
        shape = re.sub(r"[0-9]", "9", app_id)[:60]
        errors.append("FIREBASE_APP_ID has the wrong format. Expected 1:<project number>:android:<hex>, "
                      f"but it contains {describe(app_id)} (shaped like '{shape}', {len(app_id)} characters). Use "
                      "client[0].client_info.mobilesdk_app_id from google-services.json.")
    else:
        number, platform, _ = m.groups()
        if platform != "android":
            errors.append(f"FIREBASE_APP_ID is the id of a {platform.upper()} app. Use the Android app "
                          "(package com.aduchat.chat_adunka) id from google-services.json.")
        if number != sender:
            errors.append("FIREBASE_APP_ID and FIREBASE_MESSAGING_SENDER_ID belong to different Firebase "
                          "projects (the project numbers do not match). Copy both from the same google-services.json.")

    if re.fullmatch(r"AIza[0-9A-Za-z_\-]{35}", api_key):
        key_project, problem = api_key_project(api_key)
        if key_project is None:
            note("warning", "Firebase API key", f"Could not ask Google which project the API key belongs to ({problem}).")
        elif key_project == EXPECTED_PROJECT:
            note("notice", "Firebase API key", f"Verified online: the API key belongs to '{EXPECTED_PROJECT}'.")
        elif key_project in KNOWN_OTHER_PROJECTS:
            errors.append(f"FIREBASE_API_KEY belongs to the other project '{key_project}', not '{EXPECTED_PROJECT}'.")
        elif re.fullmatch(r"\d+", str(key_project)):
            # Google reports the project NUMBER; compare it with the other values.
            key_number = str(key_project)
            app_number = m.group(1) if m else None
            same_sender = key_number == sender
            same_app = app_number is not None and key_number == app_number
            note("notice", "Firebase API key",
                 "Verified online. The API key's project number "
                 + ("matches" if same_sender else "does NOT match") + " FIREBASE_MESSAGING_SENDER_ID and "
                 + ("matches" if same_app else "does NOT match") + " the number inside FIREBASE_APP_ID.")
            if not same_sender:
                errors.append("FIREBASE_API_KEY and FIREBASE_MESSAGING_SENDER_ID come from different Firebase projects.")
            if app_number is not None and not same_app:
                errors.append("FIREBASE_API_KEY and FIREBASE_APP_ID come from different Firebase projects.")
        elif key_project != EXPECTED_PROJECT:
            errors.append(f"FIREBASE_API_KEY belongs to {describe(key_project)}, not '{EXPECTED_PROJECT}'.")
        else:
            note("notice", "Firebase API key", f"Verified online: the API key belongs to '{EXPECTED_PROJECT}'.")

    if not re.fullmatch(r"\d{6,20}", sender):
        errors.append("FIREBASE_MESSAGING_SENDER_ID should be the project number (digits only), "
                      "project_info.project_number in google-services.json.")

    if not re.fullmatch(r"[a-z0-9\-]{4,40}", project):
        errors.append("FIREBASE_PROJECT_ID has the wrong format; use project_info.project_id.")
    elif project != EXPECTED_PROJECT:
        errors.append(f"FIREBASE_PROJECT_ID contains {describe(project)}, not '{EXPECTED_PROJECT}'. The app would use a different Firebase "
                      "project than the one in .firebaserc, where AduChat's rules are published, and every "
                      "write would be refused with permission-denied. Fix the secret, or change .firebaserc if "
                      "you really moved to another project.")

    if errors:
        for e in errors:
            note("error", "Firebase settings", e)
        print("Firebase configuration check FAILED:\n- " + "\n- ".join(errors))
        sys.exit(1)
    note("notice", "Firebase configured",
         f"Project {project}; Android app id and sender id belong to the same project.")

turn = "configured" if values["TURN_URLS"] else "not configured (STUN only)"
note("notice", "Features",
     f"Storage enabled: {values['STORAGE_ENABLED']}; email sign-in: {values['EMAIL_AUTH_ENABLED']}; "
     f"phone sign-in: {values['PHONE_AUTH_ENABLED']}; TURN relay: {turn}")
