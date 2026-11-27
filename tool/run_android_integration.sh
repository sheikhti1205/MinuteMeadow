#!/usr/bin/env bash
# Runs the Android integration suite on the CI emulator.
#
# android-emulator-runner executes its `script` input one line at a time, so
# the workflow passes a single command into this file. The suite runs as a
# native instrumented test, so no host VM service is involved, and the time
# bound plus the filtered device capture keep a stall from reaching the job
# limit without evidence.
set -uo pipefail

cd "$(dirname "$0")/.." || { echo 'cannot enter the repository root' >&2; exit 1; }

serial="${ANDROID_SERIAL:-emulator-5554}"
bound="${INTEGRATION_BOUND:-12m}"
target="$(pwd)/integration_test/app_test.dart"
device_log="${RUNNER_TEMP:-/tmp}/device-test.log"
relevant_log="${RUNNER_TEMP:-/tmp}/device-relevant.log"
# The generated Android root build redirects subprojects to <repo>/build/<name>.
results_dir="build/app/outputs/androidTest-results"

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

# Only the current run may supply the JUnit evidence counted below.
rm -rf "${results_dir}"

: > "${device_log}"
"${adb}" -s "${serial}" logcat -v time \
  -s flutter:I AndroidRuntime:E DEBUG:E ActivityManager:I >"${device_log}" 2>&1 &
logcat_pid=$!

echo "phase: connectedDebugAndroidTest starting at $(date -u +%H:%M:%S) for ${target}, bounded to ${bound}"
timeout --signal=INT --kill-after=60s "${bound}" \
  bash android/gradlew -p android :app:connectedDebugAndroidTest \
  -Ptarget="${target}" --console=plain
code=$?

stop_logcat
echo "phase: connectedDebugAndroidTest ended at $(date -u +%H:%M:%S) with exit ${code}"

if [ "${code}" -eq 124 ] || [ "${code}" -eq 137 ]; then
  echo "::error::the instrumented run was still running after ${bound} and was stopped so the stall is reported instead of the job limit"
fi

count_attr() {
  find "${results_dir}" -type f -name '*.xml' -exec grep -ho "$1=\"[0-9]*\"" {} + 2>/dev/null \
    | grep -o '[0-9]*' | awk '{ total += $1 } END { print total + 0 }'
}

tests_run=0
tests_failed=0
tests_errors=0
tests_skipped=0
if [ -d "${results_dir}" ]; then
  tests_run=$(count_attr tests)
  tests_failed=$(count_attr failures)
  tests_errors=$(count_attr errors)
  tests_skipped=$(count_attr skipped)
  echo "phase: instrumented results: ${tests_run} run, ${tests_failed} failed, ${tests_errors} errors, ${tests_skipped} skipped"
else
  echo 'phase: no instrumented result directory was written'
fi

if [ "${code}" -eq 0 ] && [ "${tests_run}" -eq 0 ]; then
  echo "::error::Gradle reported success without a single recorded instrumented test"
  code=3
fi

if [ "${code}" -eq 0 ] && [ "$((tests_failed + tests_errors + tests_skipped))" -ne 0 ]; then
  echo "::error::instrumented results report failures, errors or skips although Gradle exited cleanly"
  code=3
fi

if [ "${code}" -ne 0 ]; then
  echo "::group::device log (test, launch and crash lines)"
  captured=$(wc -l < "${device_log}" 2>/dev/null || echo 0)
  echo "captured device lines: ${captured}"
  grep -E '(app\.companionfocus|AndroidRuntime|FATAL|beginning of crash|flutter)' \
    "${device_log}" 2>/dev/null \
    | sed -E 's#(is listening on )[^ ]+#\1[redacted]#' >"${relevant_log}" || true
  if [ -s "${relevant_log}" ]; then
    tail -n 200 "${relevant_log}"
  else
    echo 'no test, launch or crash lines were logged'
  fi
  echo "::endgroup::"
fi

exit "${code}"
