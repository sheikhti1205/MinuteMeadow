#!/usr/bin/env bash
# Runs the Android integration suite on the CI emulator.
#
# android-emulator-runner executes its `script` input one line at a time, so
# the workflow passes a single command into this file. The time bound and the
# filtered device capture keep a stalled tool or app hand-off from reaching the
# job limit without evidence.
set -uo pipefail

cd "$(dirname "$0")/.." || { echo 'cannot enter the repository root' >&2; exit 1; }

serial="${ANDROID_SERIAL:-emulator-5554}"
bound="${INTEGRATION_BOUND:-12m}"
device_log="${RUNNER_TEMP:-/tmp}/device-test.log"
relevant_log="${RUNNER_TEMP:-/tmp}/device-relevant.log"

adb=adb
if ! command -v adb >/dev/null 2>&1; then
  adb=/usr/local/lib/android/sdk/platform-tools/adb
fi

logcat_pid=
stop_logcat() {
  if [ -n "${logcat_pid}" ]; then
    kill "${logcat_pid}" 2>/dev/null || true
    wait "${logcat_pid}" 2>/dev/null || true
    logcat_pid=
  fi
}
trap stop_logcat EXIT

echo "phase: emulator ready at $(date -u +%H:%M:%S)"
"${adb}" -s "${serial}" shell getprop sys.boot_completed

: > "${device_log}"
"${adb}" -s "${serial}" logcat -v time \
  -s flutter:I AndroidRuntime:E DEBUG:E ActivityManager:I >"${device_log}" 2>&1 &
logcat_pid=$!

echo "phase: flutter test starting at $(date -u +%H:%M:%S), bounded to ${bound}"
timeout --signal=INT --kill-after=60s "${bound}" \
  flutter test integration_test -d "${serial}" --reporter expanded
code=$?

stop_logcat
echo "phase: flutter test ended at $(date -u +%H:%M:%S) with exit ${code}"

if [ "${code}" -eq 124 ] || [ "${code}" -eq 137 ]; then
  echo "::error::flutter test was still running after ${bound} and was stopped so the stall is reported instead of the job limit"
fi

if [ "${code}" -ne 0 ]; then
  echo "::group::device log (test, launch and crash lines)"
  captured=$(wc -l < "${device_log}" 2>/dev/null || echo 0)
  echo "captured device lines: ${captured}"
  grep -E '(Start proc|Displayed|has died|AndroidRuntime|FATAL|beginning of crash|flutter)' \
    "${device_log}" >"${relevant_log}" 2>/dev/null || true
  if [ -s "${relevant_log}" ]; then
    tail -n 200 "${relevant_log}"
  else
    echo 'no test, launch or crash lines were logged'
  fi
  echo "::endgroup::"
fi

exit "${code}"
