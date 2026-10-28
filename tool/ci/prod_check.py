#!/usr/bin/env python3
"""Live check of the production backend (Firebase project aduchat-c4ee6).

Creates three temporary email accounts (A, B, outsider C) and checks with
the same REST endpoints the apps use that:
  - email registration works,
  - the published security rules are the current version,
  - A and B can create profiles and exchange messages in a chat,
  - C cannot read their chat or their private data,
  - the 2026-10-27 protections are live (no outsider posts, no forged
    admin events, no directory dump, no username squatting),
then deletes every document and all three accounts again. Real users'
data is never read. Credentials come from the environment and are never
printed.
"""
import json, os, secrets, sys, time, urllib.error, urllib.request

KEY = os.environ.get("FIREBASE_API_KEY", "").strip()
PROJECT = "aduchat-c4ee6"
DB = f"https://firestore.googleapis.com/v1/projects/{PROJECT}/databases/(default)/documents"
ID = "https://identitytoolkit.googleapis.com/v1"
results, cleanup = [], []


def call(method, url, body=None, token=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", "Bearer " + token)
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read() or b"{}")
        except Exception:
            return e.code, {}


def check(name, ok, detail=""):
    results.append((name, ok))
    print(f"{'PASS' if ok else 'FAIL'}  {name}" + (f"  ({detail})" if detail and not ok else ""))
    return ok


def err(body):
    return (body.get("error") or {}).get("message", "")[:160] if isinstance(body, dict) else ""


def fields(d):
    out = {}
    for k, v in d.items():
        if isinstance(v, bool):
            out[k] = {"booleanValue": v}
        elif isinstance(v, int):
            out[k] = {"integerValue": str(v)}
        elif isinstance(v, list):
            out[k] = {"arrayValue": {"values": [{"stringValue": x} for x in v]}}
        else:
            out[k] = {"stringValue": v}
    return {"fields": out}


def write(token, path, data, server_time=()):
    w = {"update": {"name": f"projects/{PROJECT}/databases/(default)/documents/{path}", **fields(data)},
         "currentDocument": {"exists": False}}
    if server_time:
        w["updateTransforms"] = [{"fieldPath": f, "setToServerValue": "REQUEST_TIME"} for f in server_time]
    return call("POST", f"{DB}:commit", {"writes": [w]}, token)


def delete(token, path):
    return call("DELETE", f"{DB}/{path}", token=token)


def account(tag):
    email = f"aduchat-ci-{tag}-{secrets.token_hex(4)}@example.com"
    s, b = call("POST", f"{ID}/accounts:signUp?key={KEY}",
                {"email": email, "password": secrets.token_urlsafe(16), "returnSecureToken": True})
    if s != 200:
        return None, None, err(b)
    cleanup.append(("account", b["idToken"]))
    return b["localId"], b["idToken"], ""


def main():
    if not KEY:
        print("::warning title=Production check::FIREBASE_API_KEY not available; skipped.")
        return 0
    a, ta, e = account("a")
    if not check("Email registration on the live project", a is not None, e):
        if "OPERATION_NOT_ALLOWED" in e:
            print("::error title=Email sign-in disabled::Enable Email/Password in Firebase console > Authentication > Sign-in method.")
        return 1
    b, tb, _ = account("b")
    c, tc, _ = account("c")
    check("Second and third accounts registered", bool(b and c))

    s, body = call("GET", f"{DB}/rulesVersion/2026-10-27", token=ta)
    rules_current = s in (200, 404)
    check("Published security rules are current", rules_current,
          f"HTTP {s}: publish firestore.rules (firebase deploy --only firestore:rules)")

    for uid, tok, name in ((a, ta, "CI Test A"), (b, tb, "CI Test B")):
        s, body = write(tok, f"users/{uid}", {"uid": uid, "displayName": name,
                                              "displayNameLower": name.lower()}, ("createdAt", "updatedAt"))
        cleanup.append(("doc", tok, f"users/{uid}"))
        check(f"Profile created ({name})", s == 200, f"HTTP {s} {err(body)}")

    s, body = call("GET", f"{DB}/users/{a}", token=tb)
    check("B can see A's public profile", s == 200, f"HTTP {s}")
    s, body = call("GET", f"{DB}/users/{a}/private/account", token=tc)
    check("Outsider cannot read A's private data", s == 403, f"HTTP {s}")

    # A group chat is used because admins may delete it completely
    # afterwards (direct chats are kept by design).
    chat = "ci" + secrets.token_hex(8)
    s, body = write(ta, f"chats/{chat}", {"type": "group", "name": "CI check", "createdBy": a,
                                          "members": [a, b], "admins": [a]}, ("createdAt", "updatedAt"))
    check("A creates a chat with B", s == 200, f"HTTP {s} {err(body)}")
    cleanup.append(("doc", ta, f"chats/{chat}"))

    msgs = []
    for tok, uid, text in ((ta, a, "Salaan from A"), (tb, b, "مرحبا from B")):
        mid = secrets.token_hex(8)
        s, body = write(tok, f"chats/{chat}/messages/{mid}",
                        {"senderId": uid, "type": "text", "text": text, "readBy": []},
                        ("createdAt", "clientCreatedAt"))
        msgs.append(mid)
        cleanup.append(("doc", ta, f"chats/{chat}/messages/{mid}"))
        check(f"Message sent by {'A' if uid == a else 'B'}", s == 200, f"HTTP {s} {err(body)}")

    time.sleep(1)
    for tok, who, want in ((tb, "B", "Salaan from A"), (ta, "A", "مرحبا from B")):
        s, body = call("GET", f"{DB}/chats/{chat}/messages?pageSize=10", token=tok)
        texts = [d["fields"].get("text", {}).get("stringValue") for d in body.get("documents", [])] if s == 200 else []
        check(f"{who} receives the other's message", want in texts, f"HTTP {s}")

    s, _ = call("GET", f"{DB}/chats/{chat}/messages?pageSize=10", token=tc)
    check("Outsider cannot read the conversation", s == 403, f"HTTP {s}")
    s, _ = call("GET", f"{DB}/chats/{chat}", token=tc)
    check("Outsider cannot read the chat", s == 403, f"HTTP {s}")

    # Protections added with the 2026-10-27 rules. Every write below must be
    # refused, so nothing is stored and nothing needs cleaning up.
    s, body = write(tc, f"chats/{chat}/messages/{secrets.token_hex(8)}",
                    {"senderId": c, "type": "text", "text": "intruder", "readBy": []},
                    ("createdAt", "clientCreatedAt"))
    check("Outsider cannot post into the group", s == 403, f"HTTP {s}")
    forged = secrets.token_hex(8)
    s, body = write(tb, f"chats/{chat}/messages/{forged}",
                    {"senderId": b, "type": "system", "text": f"admin_added:{b}", "readBy": []},
                    ("createdAt", "clientCreatedAt"))
    if s == 200:  # older rules: remove it again
        cleanup.append(("doc", ta, f"chats/{chat}/messages/{forged}"))
    check("A member cannot forge an admin event", s == 403, f"HTTP {s}")
    # Only with the new rules: older rules would answer this query with real
    # users' directory entries, and this check never reads real users' data.
    if rules_current:
        s, body = call("POST", f"{DB}:runQuery",
                       {"structuredQuery": {"from": [{"collectionId": "directory"}]}}, tc)
        check("The user directory cannot be downloaded in one query", s == 403, f"HTTP {s}")
    squat = f"ci{secrets.token_hex(6)}"
    s, body = write(tc, f"usernames/{squat}", {"uid": c}, ("createdAt",))
    if s == 200:  # older rules: release it again
        cleanup.append(("doc", tc, f"usernames/{squat}"))
    check("Usernames cannot be reserved without a profile", s == 403, f"HTTP {s}")
    return 0


code = 1
try:
    code = main()
finally:
    # Remove messages first, then chat and profiles, then the accounts.
    docs = [x for x in cleanup if x[0] == "doc"]
    docs.sort(key=lambda x: (0 if "/messages/" in x[2] else 1 if x[2].startswith("chats/") else 2))
    left = 0
    for _, tok, path in docs:
        s, _ = delete(tok, path)
        left += s not in (200, 404)
    for kind, tok, *_ in cleanup:
        if kind == "account":
            s, _ = call("POST", f"{ID}/accounts:delete?key={KEY}", {"idToken": tok})
            left += s != 200
    check("Test data and test accounts deleted", left == 0, f"{left} items not deleted")

failed = [n for n, ok in results if not ok]
summary = f"{len(results) - len(failed)}/{len(results)} passed" + (f"; failed: {'; '.join(failed)}" if failed else "")
print(f"::{'notice' if not failed else 'error'} title=Production backend check::{summary}")
sys.exit(1 if failed or code else 0)
