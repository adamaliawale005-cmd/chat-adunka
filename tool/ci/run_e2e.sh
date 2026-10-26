#!/usr/bin/env bash
# Runs the end-to-end app test on the Android emulator (called by CI).
# Progress and failures are also written as GitHub annotations, so they are
# visible even if log upload does not happen.
set -o pipefail
mkdir -p ci-logs
df -h / | tail -1 | sed 's/^/::notice title=Disk before e2e::/'
adb logcat -c || true
# Grant microphone/camera as soon as the test installs the app, so the
# system permission dialog does not block the automated call test.
( for i in $(seq 1 900); do
    adb shell pm grant com.aduchat.chat_adunka android.permission.RECORD_AUDIO 2>/dev/null
    adb shell pm grant com.aduchat.chat_adunka android.permission.CAMERA 2>/dev/null
    sleep 2
  done ) &
GRANTER=$!

timeout 40m flutter test integration_test/app_flow_test.dart \
  --dart-define=USE_FIREBASE_EMULATOR=true -r expanded 2>&1 | tee ci-logs/e2e.log
code=$?
kill $GRANTER 2>/dev/null || true
grep "E2E CALL NOT TESTED" ci-logs/e2e.log | sed 's/.*E2E CALL NOT TESTED: /::warning title=Calls::/' || true

adb logcat -d -t 4000 > ci-logs/logcat.txt 2>/dev/null || true
grep "E2E STEP PASS" ci-logs/e2e.log > ci-logs/e2e-steps.txt || true
steps=$(sed 's/.*E2E STEP PASS: //' ci-logs/e2e-steps.txt | paste -sd ';' -)
echo "::notice title=E2E passed steps::${steps:-none}"
if [ $code -ne 0 ]; then
  python3 - <<'EOF'
import re
log = open("ci-logs/e2e.log", errors="replace").read()
interesting = [l for l in log.splitlines()
               if re.search(r"(EXCEPTION|Exception|Error|Timed out|Expected|Actual|FAILED|failed|══)", l)]
tail = "\n".join(log.splitlines()[-60:])
for title, text in (("E2E failure lines", "\n".join(interesting[-40:])), ("E2E log tail", tail)):
    text = text[-6000:].replace("%", "%25").replace("\r", "").replace("\n", "%0A")
    print(f"::error title={title}::{text}")
try:
    cat = open("ci-logs/logcat.txt", errors="replace").read().splitlines()
    flutter = [l for l in cat if "flutter" in l.lower() or "AndroidRuntime" in l][-40:]
    t = "\n".join(flutter)[-5000:].replace("%", "%25").replace("\n", "%0A")
    print(f"::error title=E2E logcat::{t}")
except Exception:
    pass
EOF
fi
df -h / | tail -1 | sed 's/^/::notice title=Disk after e2e::/'
exit $code
