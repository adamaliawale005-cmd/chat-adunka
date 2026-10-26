#!/usr/bin/env python3
"""Browser smoke test for the AduChat web app (used by CI).

Opens the site in headless Chromium, waits for Flutter's first frame,
turns on the accessibility tree so screen text can be read, and checks
that the app reached its sign-in screen connected to the official
Firebase project. Saves a screenshot and the browser console to ci-logs/.

  web_smoke.py --serve build/web --base /chat-adunka/   (local build)
  web_smoke.py --url https://example.github.io/chat-adunka/
"""
import argparse, functools, http.server, os, shutil, socketserver, sys, tempfile, threading, time

from playwright.sync_api import sync_playwright

ap = argparse.ArgumentParser()
ap.add_argument("--serve")
ap.add_argument("--base", default="/")
ap.add_argument("--url")
a = ap.parse_args()
os.makedirs("ci-logs", exist_ok=True)

url = a.url
if a.serve:
    # Serve the build under the same sub-path GitHub Pages uses.
    root = tempfile.mkdtemp()
    shutil.copytree(a.serve, os.path.join(root, a.base.strip("/")) if a.base.strip("/") else root,
                    dirs_exist_ok=True)
    handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=root)
    handler.log_message = lambda *x: None
    srv = socketserver.TCPServer(("127.0.0.1", 0), handler)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    url = f"http://127.0.0.1:{srv.server_address[1]}{a.base}"

tag = "web-live" if a.url else "web-local"
console, errors = [], []
ok = True
with sync_playwright() as p:
    b = p.chromium.launch()
    page = b.new_page(viewport={"width": 412, "height": 860}, locale="en-US")
    page.on("console", lambda m: console.append(f"[{m.type}] {m.text}"))
    page.on("pageerror", lambda e: errors.append(str(e)))
    resp = page.goto(url, wait_until="load", timeout=90000)
    print("HTTP", resp.status if resp else "?", url)
    if resp and resp.url.startswith("http://") and a.url:
        print("WARN: not served over HTTPS")
    try:
        page.wait_for_function("!document.getElementById('loading')", timeout=120000)
        print("PASS first frame drawn")
    except Exception:
        ok = False
        print("FAIL Flutter did not draw its first frame")
    time.sleep(6)
    # Ask Flutter to build the accessibility tree so text is readable.
    page.evaluate("""() => { const p = document.querySelector('flt-semantics-placeholder');
                             if (p) p.click(); }""")
    time.sleep(3)
    text = page.evaluate("() => document.body.innerText || ''")
    labels = page.evaluate("""() => Array.from(document.querySelectorAll('[aria-label]'))
                                 .map(e => e.getAttribute('aria-label')).join(' | ')""")
    page.screenshot(path=f"ci-logs/{tag}.png")
    b.close()

screen = (text + " " + labels)
open(f"ci-logs/{tag}-console.txt", "w").write("\n".join(console + ["--- page errors ---"] + errors))
open(f"ci-logs/{tag}-screen.txt", "w").write(screen)
fb = [c for c in console if "AduChat: Firebase project" in c]
print("Console:", fb[-1] if fb else "no Firebase start line")
if not any("aduchat-c4ee6" in c for c in fb):
    ok = False
    print("FAIL app did not report the official Firebase project aduchat-c4ee6")
if any("not configured" in c.lower() for c in fb):
    ok = False
if errors:
    print("Page errors:", *errors[:10], sep="\n  ")
    ok = False
words = [w for w in ("AduChat", "Email", "Sign in", "Create account", "Password") if w.lower() in screen.lower()]
print("Screen words found:", words)
if len(words) < 2:
    ok = False
    print("FAIL sign-in screen text not found; screen text:", screen[:500])
print("RESULT", "PASS" if ok else "FAIL")
print(f"::{'notice' if ok else 'error'} title=Web smoke ({tag})::{'PASS' if ok else 'FAIL'} {url} words={words}")
sys.exit(0 if ok else 1)
