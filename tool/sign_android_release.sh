#!/usr/bin/env bash
# Signs the unsigned Flutter release APK with the Android SDK build tools.
#
# The release variant is compiled without a signing configuration, so Gradle
# never receives a credential. This script aligns and signs the single APK the
# build produced, then verifies the signature, certificate, package, version
# and 16 KB page alignment before reporting the artifact. The keystore is
# written owner-only inside the runner's temporary directory and removed as
# soon as signing finishes. Credentials are read from the environment by name
# and are never printed or passed on a command line.
#
# Usage: sign_android_release.sh [build-outputs-dir] [signed-output-dir]
#
# Required environment:
#   MINUTEMEADOW_ANDROID_KEYSTORE_B64     base64 PKCS12 keystore (secret)
#   MINUTEMEADOW_ANDROID_STORE_PASSWORD   store and key password (secret)
#   MINUTEMEADOW_ANDROID_CERT_SHA256      expected signer certificate digest
#   EXPECTED_PACKAGE                      Android application id
#   EXPECTED_VERSION_CODE                 Android version code
#   EXPECTED_VERSION_NAME                 Android version name
set -euo pipefail

outputs_dir="${1:-build/app/outputs}"
# Keep the signed artifact inside the workspace, where artifact upload looks
# first; build/ is ignored by git.
signed_dir="${2:-${outputs_dir}/signed}"
key_alias="minutemeadow"

fail() {
  printf '::error::%s\n' "$*" >&2
  exit 1
}

# The decoded key must be owner-only, and must not outlive this script.
umask 077
work=""
cleanup() {
  if [ -n "$work" ] && [ -d "$work" ]; then
    rm -rf -- "$work"
  fi
}
trap cleanup EXIT

normalise_sha256() {
  printf '%s' "$1" | tr -d ' :' | tr '[:upper:]' '[:lower:]'
}

# Returns success when the dotted version $1 is at least $2.
version_at_least() {
  if [ "$1" = "$2" ]; then
    return 0
  fi
  [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n 1)" = "$1" ]
}

for name in \
  MINUTEMEADOW_ANDROID_KEYSTORE_B64 \
  MINUTEMEADOW_ANDROID_STORE_PASSWORD \
  MINUTEMEADOW_ANDROID_CERT_SHA256 \
  EXPECTED_PACKAGE \
  EXPECTED_VERSION_CODE \
  EXPECTED_VERSION_NAME; do
  if [ -z "${!name:-}" ]; then
    fail "${name} is empty; the android-signing environment must provide it."
  fi
done

expected_cert="$(normalise_sha256 "$MINUTEMEADOW_ANDROID_CERT_SHA256")"
if [ "${#expected_cert}" -ne 64 ] || printf '%s' "$expected_cert" | grep -q '[^0-9a-f]'; then
  fail "MINUTEMEADOW_ANDROID_CERT_SHA256 must be the 64 hexadecimal characters of the signer certificate SHA-256 digest."
fi

sdk_root="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-/usr/local/lib/android/sdk}}"
if [ ! -d "$sdk_root/build-tools" ]; then
  fail "No Android SDK build-tools under ${sdk_root}; set ANDROID_SDK_ROOT to the SDK that holds build-tools."
fi

tools_dir=""
tools_version=""
for candidate in "$sdk_root"/build-tools/*; do
  if [ ! -d "$candidate" ]; then
    continue
  fi
  if [ ! -x "$candidate/zipalign" ] || [ ! -x "$candidate/apksigner" ] || [ ! -x "$candidate/aapt2" ]; then
    continue
  fi
  candidate_version="$(basename "$candidate")"
  if [ -z "$tools_dir" ] || version_at_least "$candidate_version" "$tools_version"; then
    tools_dir="$candidate"
    tools_version="$candidate_version"
  fi
done
if [ -z "$tools_dir" ]; then
  fail "No Android build-tools directory under ${sdk_root}/build-tools provides zipalign, apksigner and aapt2."
fi
if ! version_at_least "$tools_version" "35.0.0"; then
  fail "Android build-tools ${tools_version} cannot align 16 KB pages; build-tools 35.0.0 or newer is required."
fi
printf 'Using Android build-tools %s from %s\n' "$tools_version" "$tools_dir"

# The Flutter Gradle plugin copies the packageable APK to
# build/app/outputs/flutter-apk/app-release.apk even when it is unsigned.
# Accept that copy and the Gradle release directory, and insist they agree.
candidates=()
for directory in "$outputs_dir/flutter-apk" "$outputs_dir/apk/release"; do
  if [ ! -d "$directory" ]; then
    continue
  fi
  for candidate in "$directory"/app-release*.apk; do
    if [ -f "$candidate" ]; then
      candidates+=("$candidate")
    fi
  done
done
if [ "${#candidates[@]}" -eq 0 ]; then
  fail "No app-release APK under ${outputs_dir}; flutter build apk --release produced no release APK."
fi

input_apk="${candidates[0]}"
input_sha="$(sha256sum "$input_apk" | cut -d ' ' -f 1)"
for candidate in "${candidates[@]}"; do
  candidate_sha="$(sha256sum "$candidate" | cut -d ' ' -f 1)"
  if [ "$candidate_sha" != "$input_sha" ]; then
    fail "${candidate} and ${input_apk} are different release APKs; sign one APK per build."
  fi
  case "$candidate" in
    *-unsigned.apk) input_apk="$candidate" ;;
  esac
done

if "$tools_dir/apksigner" verify "$input_apk" >/dev/null 2>&1; then
  fail "${input_apk} already carries a signature; the release build must stay unsigned until this step."
fi

mkdir -p -- "$signed_dir"
work="$(mktemp -d "${RUNNER_TEMP:-/tmp}/android-signing.XXXXXX")"
aligned_apk="$work/app-release-aligned.apk"
printf 'Aligning %s to 16 KB pages\n' "$input_apk"
"$tools_dir/zipalign" -P 16 -f 4 "$input_apk" "$aligned_apk"
"$tools_dir/zipalign" -c -P 16 4 "$aligned_apk" >/dev/null ||
  fail "zipalign could not confirm 4-byte and 16 KB alignment of the release APK."

keystore="$work/minutemeadow.p12"
if ! printf '%s' "$MINUTEMEADOW_ANDROID_KEYSTORE_B64" | base64 --decode > "$keystore"; then
  fail "MINUTEMEADOW_ANDROID_KEYSTORE_B64 is not valid base64."
fi
if [ ! -s "$keystore" ]; then
  fail "MINUTEMEADOW_ANDROID_KEYSTORE_B64 decoded to an empty file."
fi

signed_apk="$signed_dir/app-release-signed.apk"
rm -f -- "$signed_apk"
"$tools_dir/apksigner" sign \
  --ks "$keystore" \
  --ks-type PKCS12 \
  --ks-key-alias "$key_alias" \
  --ks-pass env:MINUTEMEADOW_ANDROID_STORE_PASSWORD \
  --key-pass env:MINUTEMEADOW_ANDROID_STORE_PASSWORD \
  --out "$signed_apk" \
  "$aligned_apk"

unset MINUTEMEADOW_ANDROID_STORE_PASSWORD MINUTEMEADOW_ANDROID_KEYSTORE_B64
rm -f -- "$keystore"
if [ -e "$keystore" ]; then
  fail "The temporary keystore could not be removed."
fi

# Reprints the verification transcript with certificate subjects removed and
# digest values masked, so an unexpected apksigner format can be diagnosed
# from a public log without republishing certificate identity details.
dump_verification() {
  printf 'apksigner verification output (digests masked):\n' >&2
  printf '%s\n' "${certs:-}" |
    grep -v 'certificate DN:' |
    sed -e 's/\([0-9A-Fa-f]\{2\}:\)\{8,\}[0-9A-Fa-f]\{2\}/<digest>/g' \
        -e 's/[0-9A-Fa-f]\{32,\}/<digest>/g' >&2 || true
}

if ! certs="$("$tools_dir/apksigner" verify --verbose --print-certs "$signed_apk" 2>&1)"; then
  dump_verification
  fail "apksigner could not verify the signed release APK."
fi

# apksigner prints a single signer count in verbose mode, then one certificate
# block per signer. Build-tools 37 labels that block by scheme
# ("V3.0 Signer: certificate SHA-256 digest: ..."), older build-tools label it
# by signer ("Signer #1 certificate SHA-256 digest: ..."). Rotation (v3.1),
# hybrid (v3.2) and source stamp blocks print further certificates and are
# refused rather than guessed at.
declared_signers="$(printf '%s\n' "$certs" | sed -n 's/^Number of signers: *\([0-9][0-9]*\) *$/\1/p')"
declared_count="$(printf '%s\n' "$declared_signers" | grep -c '[0-9]' || true)"
if [ "$declared_count" != "1" ]; then
  dump_verification
  fail "apksigner printed ${declared_count} signer counts instead of one; the verification output is not a format this job can check."
fi
if [ "$declared_signers" != "1" ]; then
  dump_verification
  fail "The release APK declares ${declared_signers} signers; exactly one is expected."
fi

digest_lines="$(printf '%s\n' "$certs" | grep -F 'certificate SHA-256 digest:' || true)"
if [ -z "$digest_lines" ]; then
  dump_verification
  fail "apksigner printed no certificate SHA-256 digest for ${signed_apk}."
fi

eligible_digest=""
eligible_count=0
unexpected_cert_line=""
while IFS= read -r cert_line; do
  if [ -z "$cert_line" ]; then
    continue
  fi
  case "$cert_line" in
    "V3.0 Signer: certificate SHA-256 digest: "*|"V2 Signer: certificate SHA-256 digest: "*|"V1 Signer: certificate SHA-256 digest: "*|"Signer #1 certificate SHA-256 digest: "*)
      eligible_digest="${cert_line#*certificate SHA-256 digest: }"
      eligible_count=$((eligible_count + 1))
      ;;
    *)
      unexpected_cert_line="$cert_line"
      ;;
  esac
done <<< "$digest_lines"

if [ -n "$unexpected_cert_line" ]; then
  dump_verification
  fail "apksigner printed a signer certificate this job does not accept: ${unexpected_cert_line%%certificate SHA-256 digest:*}"
fi
if [ "$eligible_count" != "1" ]; then
  dump_verification
  fail "apksigner printed ${eligible_count} eligible signer certificates; exactly one is expected."
fi

actual_cert="$(normalise_sha256 "$eligible_digest")"
if [ "$actual_cert" != "$expected_cert" ]; then
  dump_verification
  fail "The release APK is signed by certificate ${actual_cert}, not the expected ${expected_cert}."
fi

if ! "$tools_dir/zipalign" -c -P 16 4 "$signed_apk" >/dev/null; then
  fail "Signing moved the release APK out of 4-byte and 16 KB alignment."
fi

if ! badging="$("$tools_dir/aapt2" dump badging "$signed_apk" 2>/dev/null)"; then
  fail "aapt2 could not read the manifest of ${signed_apk}."
fi
package_line="$(printf '%s\n' "$badging" | grep -m 1 '^package: ' || true)"
if [ -z "$package_line" ]; then
  fail "The signed APK has no package identity to verify."
fi
package_name="$(printf '%s\n' "$package_line" | sed -e "s/^package: name='\([^']*\)'.*/\1/")"
version_code="$(printf '%s\n' "$package_line" | sed -e "s/.*versionCode='\([0-9]*\)'.*/\1/")"
version_name="$(printf '%s\n' "$package_line" | sed -e "s/.*versionName='\([^']*\)'.*/\1/")"

if [ "$package_name" != "$EXPECTED_PACKAGE" ]; then
  fail "The signed APK targets ${package_name}, not ${EXPECTED_PACKAGE}."
fi
if [ "$version_code" != "$EXPECTED_VERSION_CODE" ]; then
  fail "The signed APK has version code ${version_code}, not ${EXPECTED_VERSION_CODE}."
fi
if [ "$version_name" != "$EXPECTED_VERSION_NAME" ]; then
  fail "The signed APK has version name ${version_name}, not ${EXPECTED_VERSION_NAME}."
fi

apk_sha256="$(sha256sum "$signed_apk" | cut -d ' ' -f 1)"
printf 'Signed %s\n' "$signed_apk"
printf 'Package %s version %s (%s)\n' "$package_name" "$version_name" "$version_code"
printf 'Signer certificate SHA-256 %s\n' "$actual_cert"
printf 'APK SHA-256 %s\n' "$apk_sha256"

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    printf 'apk_path=%s\n' "$signed_apk"
    printf 'apk_sha256=%s\n' "$apk_sha256"
  } >> "$GITHUB_OUTPUT"
fi
