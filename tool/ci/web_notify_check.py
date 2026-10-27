#!/usr/bin/env python3
"""Real-browser test of AduChat web notifications (used by CI).

Two temporary accounts on the live project aduchat-c4ee6:
  A signs in to the web app in headless Chromium (notifications allowed),
  B sends messages through the same REST API the apps use.
Checks:
  1. A is on the Settings tab, page in front: an in-app banner appears.
  2. The tab title shows the unread count, e.g. "(1) AduChat".
  3. Tapping "Open" on the banner opens the right chat.
  4. Page in the background: a system notification is shown (service worker).
  5. Opening the link a tapped notification uses (?open=chat:<id>) opens
     the chat.
All test documents and both accounts are deleted afterwards. Screenshots
and the accessibility text go to ci-logs/ for review.

  web_notify_check.py --serve build/web --base /chat-adunka/
"""
import argparse, functools, http.server, json, os, re, secrets, shutil, socketserver
import sys, tempfile, threading, time, urllib.error, urllib.request

from playwright.sync_api import sync_playwright

KEY = os.environ.get("FIREBASE_API_KEY", "").strip()
PROJECT = "aduchat-c4ee6"
DB = f"https://firestore.googleapis.com/v1/projects/{PROJECT}/databases/(default)/documents"
ID = "https://identitytoolkit.googleapis.com/v1"
results, docs, accounts = [], [], []
os.makedirs("ci-logs", exist_ok=True)


def call(method, url, body=None, token=None):
    req = urllib.request.Request(url, data=json.dumps(body).encode() if body is not None else None,
                                 method=method)
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


def val(v):
    if isinstance(v, bool):
        return {"booleanValue": v}
    if isinstance(v, int):
        return {"integerValue": str(v)}
    if isinstance(v, list):
        return {"arrayValue": {"values": [val(x) for x in v]}}
    if isinstance(v, dict):
        return {"mapValue": {"fields": {k: val(x) for k, x in v.items()}}}
    return {"stringValue": v}


def write(path, data, server_time=(), create=True, mask=None):
    w = {"update": {"name": f"projects/{PROJECT}/databases/(default)/documents/{path}",
                    "fields": {k: val(v) for k, v in data.items()}}}
    if create:
        w["currentDocument"] = {"exists": False}
    if mask is not None:
        w["updateMask"] = {"fieldPaths": mask}
    if server_time:
        w["updateTransforms"] = [{"fieldPath": f, "setToServerValue": "REQUEST_TIME"} for f in server_time]
    return w


def commit(token, writes):
    s, b = call("POST", f"{DB}:commit", {"writes": writes}, token)
    if s != 200:
        raise RuntimeError(f"write refused: HTTP {s} {(b.get('error') or {}).get('message', '')[:200]}")


def check(name, ok, detail=""):
    results.append((name, bool(ok)))
    print(f"{'PASS' if ok else 'FAIL'}  {name}" + (f"  ({detail})" if detail and not ok else ""), flush=True)
    return ok


def account(tag):
    email = f"aduchat-ci-web-{tag}-{secrets.token_hex(4)}@example.com"
    pw = secrets.token_urlsafe(16)
    s, b = call("POST", f"{ID}/accounts:signUp?key={KEY}",
                {"email": email, "password": pw, "returnSecureToken": True})
    if s != 200:
        raise RuntimeError(f"sign-up failed: {(b.get('error') or {}).get('message', '')}")
    accounts.append(b["idToken"])
    return b["localId"], b["idToken"], email, pw


def serve(folder, base):
    root = tempfile.mkdtemp()
    shutil.copytree(folder, os.path.join(root, base.strip("/")), dirs_exist_ok=True)
    h = functools.partial(http.server.SimpleHTTPRequestHandler, directory=root)
    h.log_message = lambda *a: None
    srv = socketserver.ThreadingTCPServer(("127.0.0.1", 0), h)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    return f"http://127.0.0.1:{srv.server_address[1]}{base}"


def main(url):
    a_uid, a_tok, a_email, a_pw = account("a")
    b_uid, b_tok, _, _ = account("b")
    for uid, tok, name in ((a_uid, a_tok, "CI Web A"), (b_uid, b_tok, "CI Test B")):
        commit(tok, [write(f"users/{uid}", {"uid": uid, "displayName": name,
                                            "displayNameLower": name.lower()}, ("createdAt", "updatedAt"))])
        docs.append((tok, f"users/{uid}"))
        docs.append((tok, f"users/{uid}/private/account"))
    chat = "ciweb" + secrets.token_hex(6)
    group_name = "CI web check"
    commit(b_tok, [write(f"chats/{chat}", {"type": "group", "name": group_name, "createdBy": b_uid,
                                           "members": [a_uid, b_uid], "admins": [b_uid]},
                         ("createdAt", "updatedAt"))])
    docs.append((b_tok, f"chats/{chat}"))
    unread = {"n": 0}

    def send(text):
        mid = secrets.token_hex(8)
        unread["n"] += 1
        commit(b_tok, [
            write(f"chats/{chat}/messages/{mid}",
                  {"senderId": b_uid, "type": "text", "text": text, "readBy": []},
                  ("createdAt", "clientCreatedAt")),
            write(f"chats/{chat}", {"lastMessage": text, "lastMessageType": "text",
                                    "lastSenderId": b_uid, "lastMessageId": mid,
                                    "unread": {a_uid: unread["n"], b_uid: 0}},
                  ("lastMessageAt", "updatedAt"), create=False,
                  mask=["lastMessage", "lastMessageType", "lastSenderId", "lastMessageId", "unread"]),
        ])
        docs.insert(0, (b_tok, f"chats/{chat}/messages/{mid}"))

    with sync_playwright() as p:
        browser = p.chromium.launch()
        origin = re.match(r"https?://[^/]+", url).group(0)
        ctx = browser.new_context(viewport={"width": 412, "height": 860}, locale="en-US")
        ctx.grant_permissions(["notifications"], origin=origin)
        page = ctx.new_page()
        console = []
        page.on("console", lambda m: console.append(f"[{m.type}] {m.text}"))
        page.on("pageerror", lambda e: console.append(f"[pageerror] {e}"))

        def semantics():
            page.evaluate("""() => { const p = document.querySelector('flt-semantics-placeholder');
                                     if (p) p.click(); }""")

        def screen_text():
            return page.evaluate("""() => (document.body.innerText || '') + ' | ' +
                Array.from(document.querySelectorAll('[aria-label]')).map(e => e.getAttribute('aria-label')).join(' | ')""")

        def wait_text(pattern, seconds=30):
            end = time.time() + seconds
            while time.time() < end:
                semantics()
                if re.search(pattern, screen_text(), re.I):
                    return True
                page.wait_for_timeout(500)
            return False

        def tap(name, exact=False):
            semantics()
            loc = page.get_by_role("button", name=name, exact=exact)
            if loc.count() == 0:
                loc = page.get_by_text(name, exact=exact)
            loc.first.click(timeout=15000)

        def type_into(label, text):
            semantics()
            box = page.get_by_role("textbox", name=label)
            box.first.click(timeout=15000)
            page.wait_for_timeout(300)
            page.keyboard.type(text, delay=20)

        def shot(name):
            page.screenshot(path=f"ci-logs/notify-{name}.png")

        def set_visible(visible):
            page.evaluate("""(v) => {
                Object.defineProperty(document, 'visibilityState', {configurable: true, get: () => v ? 'visible' : 'hidden'});
                Object.defineProperty(document, 'hidden', {configurable: true, get: () => !v});
                document.hasFocus = () => v;
                document.dispatchEvent(new Event('visibilitychange'));
            }""", visible)

        try:
            page.goto(url, wait_until="load", timeout=90000)
            page.wait_for_function("!document.getElementById('loading')", timeout=120000)
            check("notification script loaded", page.evaluate("typeof window.aduchatNotify === 'object'"))
            page.wait_for_timeout(2000)
            check("notification service worker registered", page.evaluate(
                "navigator.serviceWorker.getRegistration('notify/').then(r => !!r)"))

            # ---- A signs in through the web UI ----
            tap("Log in")
            page.wait_for_timeout(1000)
            type_into("Email", a_email)
            type_into("Password", a_pw)
            shot("1-login")
            semantics()
            page.get_by_role("button", name="Log in").last.click(timeout=15000)
            ok = check("A signs in on the web app", wait_text(r"\bChats\b.*\bSettings\b|\bSettings\b.*\bChats\b", 60))
            shot("2-home")
            if not ok:
                return
            tap("Settings")
            page.wait_for_timeout(5000)   # listeners primed with the current chats

            # ---- 1-3: page in front ----
            set_visible(True)
            send("Hello from B (visible)")
            check("banner appears for a new message while on Settings",
                  wait_text(r"Hello from B \(visible\)", 30))
            shot("3-banner")
            title = ""
            for _ in range(20):
                title = page.title()
                if title.startswith("("):
                    break
                page.wait_for_timeout(500)
            check("tab title shows unread count", title == "(1) AduChat", f"title={title!r}")
            try:
                tap("Open", exact=True)
                opened = wait_text(re.escape(group_name), 20) and wait_text(r"Hello from B \(visible\)", 5)
            except Exception as e:
                opened = False
                print("open tap failed:", e)
            check("Open on the banner opens the chat", opened)
            shot("4-chat-open")
            page.go_back()
            page.wait_for_timeout(1500)
            semantics()
            try:
                tap("Settings")
            except Exception:
                pass
            page.wait_for_timeout(3000)

            # ---- 4: page in the background ----
            set_visible(False)
            send("Hello from B (background)")
            found = []
            for _ in range(60):
                found = page.evaluate("""() => navigator.serviceWorker.getRegistration('notify/')
                    .then(r => r ? r.getNotifications() : [])
                    .then(list => list.map(n => n.title + ' | ' + n.body + ' | ' + n.tag))""")
                if any("background" in f for f in found):
                    break
                page.wait_for_timeout(500)
            check("system notification while the page is in the background",
                  any(group_name in f and "Hello from B (background)" in f for f in found),
                  f"notifications={found}")
            print("Notifications:", found)
            set_visible(True)

            # ---- 5: link used when a notification is tapped after closing ----
            page.goto(url + "?open=" + "chat:" + chat, wait_until="load")
            page.wait_for_function("!document.getElementById('loading')", timeout=120000)
            check("notification link opens the chat after reload",
                  wait_text(r"Hello from B \(background\)", 60))
            shot("5-deeplink")
        finally:
            open("ci-logs/notify-console.txt", "w").write("\n".join(console))
            try:
                open("ci-logs/notify-screen.txt", "w").write(screen_text())
            except Exception:
                pass
            browser.close()


code = 1
if not KEY:
    print("::warning title=Web notification check::FIREBASE_API_KEY not available; skipped.")
    sys.exit(0)
ap = argparse.ArgumentParser()
ap.add_argument("--serve", required=True)
ap.add_argument("--base", default="/")
args = ap.parse_args()
try:
    main(serve(args.serve, args.base))
except Exception as e:
    check("test ran to completion", False, str(e)[:300])
finally:
    left = 0
    for tok, path in sorted(docs, key=lambda d: 0 if "/messages/" in d[1] else 1 if d[1].startswith("chats/") else 2):
        s, _ = call("DELETE", f"{DB}/{path}", token=tok)
        left += s not in (200, 404)
    for tok in accounts:
        s, _ = call("POST", f"{ID}/accounts:delete?key={KEY}", {"idToken": tok})
        left += s != 200
    check("test data and accounts deleted", left == 0, f"{left} not deleted")

failed = [n for n, ok in results if not ok]
summary = f"{len(results) - len(failed)}/{len(results)} passed" + (f"; failed: {'; '.join(failed)}" if failed else "")
print(f"::{'notice' if not failed else 'error'} title=Web notification check::{summary}")
sys.exit(1 if failed else 0)
