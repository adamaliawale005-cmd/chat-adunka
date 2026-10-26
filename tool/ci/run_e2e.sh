#!/usr/bin/env bash
# Runs the end-to-end app test on the Android emulator (called by CI).
set -o pipefail
mkdir -p ci-logs
adb logcat -c || true
flutter test integration_test/app_flow_test.dart \
  --dart-define=USE_FIREBASE_EMULATOR=true -r expanded 2>&1 | tee ci-logs/e2e.log
code=$?
adb logcat -d -t 3000 > ci-logs/logcat.txt 2>/dev/null || true
grep "E2E STEP PASS" ci-logs/e2e.log > ci-logs/e2e-steps.txt || true
exit $code
