#!/usr/bin/env python3
"""Resolve the build identity shared by the app, Android and GitHub Actions.

The pubspec supplies the public semantic version and the starting build
number. GitHub's run number supplies the monotonic part of the Android version
code. Installable Android previews accept only the first run attempt, because a
re-run would repeat an older run number; a re-run is rejected and the operator
is asked to dispatch a new Android build. Validation and web re-runs remain
supported.
"""

from __future__ import annotations

import os
import re
import sys
from pathlib import Path

MAX_VERSION_CODE = 2_100_000_000
ATTEMPT_WIDTH = 100

_PUBSPEC_VERSION = re.compile(r"(?m)^version:\s*([^\s#]+)")
_VERSION = re.compile(
    r"^(?P<major>\d{1,3})\."
    r"(?P<minor>\d{1,3})\."
    r"(?P<patch>\d{1,3})"
    r"(?:\+(?P<build>[1-9]\d*))?$"
)
_POSITIVE_INT = re.compile(r"[1-9]\d*")
_SHA = re.compile(r"[0-9a-f]{40}")


class VersionError(ValueError):
    """A build version input is not safe to publish."""


def fail(message: str) -> None:
    print(f"::error::{message}", file=sys.stderr)
    raise SystemExit(1)


def parse_pubspec(text: str) -> tuple[str, int]:
    line = _PUBSPEC_VERSION.search(text)
    if line is None:
        raise VersionError("pubspec.yaml has no top-level version entry.")

    raw = line.group(1).strip("'\"")
    match = _VERSION.fullmatch(raw)
    if match is None:
        raise VersionError(
            "pubspec.yaml version must be MAJOR.MINOR.PATCH or "
            "MAJOR.MINOR.PATCH+BUILD, for example 0.1.0+1."
        )

    version = "{major}.{minor}.{patch}".format(**match.groupdict())
    build = int(match.group("build") or "1")
    if build >= MAX_VERSION_CODE:
        raise VersionError(
            f"The pubspec build number must be below {MAX_VERSION_CODE}."
        )
    return version, build


def read_pubspec(path: Path) -> tuple[str, int]:
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as error:
        raise VersionError(f"Could not read {path}: {error}") from error
    return parse_pubspec(text)


def parse_positive_int(raw: str, name: str) -> int:
    if _POSITIVE_INT.fullmatch(raw) is None:
        raise VersionError(f"{name} must be a positive integer, got {raw!r}.")
    return int(raw)


def positive_environment(name: str) -> int:
    return parse_positive_int(os.environ.get(name, ""), name)


def check_android_preview_attempt(run_attempt: int, android_preview: bool) -> None:
    if android_preview and run_attempt > 1:
        raise VersionError(
            "Android preview builds cannot be re-run; dispatch a new Android build "
            "so the version code advances."
        )


def version_code_for(base_build: int, run_number: int, run_attempt: int) -> int:
    if base_build < 1:
        raise VersionError("The pubspec build number must be positive.")
    if run_number < 1:
        raise VersionError("The run number must be positive.")
    if run_attempt < 1 or run_attempt >= ATTEMPT_WIDTH:
        raise VersionError(
            f"Run attempt must be between 1 and {ATTEMPT_WIDTH - 1}, "
            f"got {run_attempt}."
        )

    version_code = base_build + (run_number - 1) * ATTEMPT_WIDTH + run_attempt
    if version_code > MAX_VERSION_CODE:
        raise VersionError(
            f"Version code {version_code} exceeds the Android maximum "
            f"{MAX_VERSION_CODE}."
        )
    if version_code <= base_build:
        raise VersionError(
            "The resolved version code would not increase the pubspec build."
        )
    return version_code


def make_version_id(
    version: str,
    version_code: int,
    run_number: int,
    run_attempt: int,
    sha: str,
) -> str:
    if _SHA.fullmatch(sha) is None:
        raise VersionError("GITHUB_SHA must be a full 40-character commit SHA.")

    version_id = f"{version}+{version_code}.r{run_number}a{run_attempt}.{sha}"
    if len(version_id) > 100:
        raise VersionError(
            "The version identifier is longer than Android's 100 character limit."
        )
    return version_id


def resolve_version(
    version: str,
    base_build: int,
    run_number: int,
    run_attempt: int,
    sha: str,
    android_preview: bool,
) -> tuple[int, str]:
    check_android_preview_attempt(run_attempt, android_preview)
    version_code = version_code_for(base_build, run_number, run_attempt)
    version_id = make_version_id(
        version,
        version_code,
        run_number,
        run_attempt,
        sha,
    )
    return version_code, version_id


def append_environment_file(name: str, values: list[tuple[str, str]]) -> None:
    path = os.environ.get(name)
    if not path:
        return
    with open(path, "a", encoding="utf-8", newline="\n") as handle:
        for key, value in values:
            handle.write(f"{key}={value}\n")


def append_summary(
    version_id: str,
    version: str,
    version_code: int,
    base_build: int,
    run_number: int,
    run_attempt: int,
    sha: str,
) -> None:
    path = os.environ.get("GITHUB_STEP_SUMMARY")
    if not path:
        return
    with open(path, "a", encoding="utf-8", newline="\n") as handle:
        handle.write(f"### Build version `{version_id}`\n\n")
        handle.write("| Field | Value |\n| --- | --- |\n")
        handle.write(f"| Version | `{version}` |\n")
        handle.write(f"| Version code | `{version_code}` |\n")
        handle.write(f"| Pubspec build | `{base_build}` |\n")
        handle.write(f"| Run | `{run_number}` attempt `{run_attempt}` |\n")
        handle.write(f"| Commit | `{sha}` |\n")
        handle.write(
            "\nVersion code = pubspec build + (run - 1) * 100 + attempt.\n"
            "Android previews require attempt 1; validation and web re-runs are allowed.\n"
        )


def main() -> None:
    android_preview = os.environ.get("ANDROID_PREVIEW", "").strip().lower() == "true"
    try:
        version, base_build = read_pubspec(Path("pubspec.yaml"))
        run_number = positive_environment("GITHUB_RUN_NUMBER")
        run_attempt = positive_environment("GITHUB_RUN_ATTEMPT")
        sha = os.environ.get("GITHUB_SHA", "")
        version_code, version_id = resolve_version(
            version,
            base_build,
            run_number,
            run_attempt,
            sha,
            android_preview,
        )
    except VersionError as error:
        fail(str(error))

    append_environment_file(
        "GITHUB_OUTPUT",
        [
            ("version", version),
            ("version_code", str(version_code)),
            ("version_id", version_id),
        ],
    )
    append_environment_file(
        "GITHUB_ENV",
        [
            ("VERSION_NAME", version),
            ("VERSION_CODE", str(version_code)),
            ("VERSION_ID", version_id),
        ],
    )
    append_summary(
        version_id,
        version,
        version_code,
        base_build,
        run_number,
        run_attempt,
        sha,
    )
    print(f"Build version {version_id} (version code {version_code}).")


if __name__ == "__main__":
    main()
