#!/usr/bin/env python3
"""Fills lib/config/firebase_options.dart from google-services.json.

Usage: python3 tool/import_google_services.py path/to/google-services.json

Refuses files from any project other than aduchat-c4ee6, or without the
Android app com.aduchat.chat_adunka.
"""
import json
import re
import sys

PROJECT = "aduchat-c4ee6"
PACKAGE = "com.aduchat.chat_adunka"
TARGET = "lib/config/firebase_options.dart"

data = json.load(open(sys.argv[1]))
info = data["project_info"]
if info.get("project_id") != PROJECT:
    sys.exit(f"Wrong project: this file is for '{info.get('project_id')}', not '{PROJECT}'.")
client = next((c for c in data.get("client", [])
               if c["client_info"]["android_client_info"]["package_name"] == PACKAGE), None)
if client is None:
    sys.exit(f"No Android app '{PACKAGE}' in this file. Register it in Firebase first.")

values = {
    "apiKey": client["api_key"][0]["current_key"],
    "appId": client["client_info"]["mobilesdk_app_id"],
    "messagingSenderId": info["project_number"],
    "storageBucket": info.get("storage_bucket", ""),
}
assert re.fullmatch(r"AIza[0-9A-Za-z_\-]{35}", values["apiKey"]), "unexpected API key format"
assert re.fullmatch(r"1:\d+:android:[0-9a-f]+", values["appId"]), "unexpected app id format"
assert values["appId"].split(":")[1] == values["messagingSenderId"], "app id / project number mismatch"

src = open(TARGET).read()
for k, v in values.items():
    src, n = re.subn(rf"(static const String {k} = )'[^']*';", rf"\g<1>'{v}';", src)
    assert n == 1, k
open(TARGET, "w").write(src)
print(f"Updated {TARGET} for project {PROJECT} (app {values['appId']}).")
