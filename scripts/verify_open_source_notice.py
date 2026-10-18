#!/usr/bin/env python3
"""Verify that the notice displayed by the app exactly matches the release notice."""

from pathlib import Path
import json
import sys


CONSTANT_MARKER = "export const THIRD_PARTY_NOTICE_TEXT: string = `"
SUPPORTED_ESCAPES = {
    "`": "`",
    "\\": "\\",
    "n": "\n",
    "r": "\r",
    "t": "\t",
}


def extract_template_literal(source: str) -> str:
    marker_at = source.find(CONSTANT_MARKER)
    if marker_at < 0:
        raise ValueError("THIRD_PARTY_NOTICE_TEXT template literal is missing")
    index = marker_at + len(CONSTANT_MARKER)
    output: list[str] = []
    while index < len(source):
        character = source[index]
        if character == "`":
            return "".join(output)
        if character == "\\":
            index += 1
            if index >= len(source) or source[index] not in SUPPORTED_ESCAPES:
                raise ValueError("THIRD_PARTY_NOTICE_TEXT uses an unsupported escape")
            output.append(SUPPORTED_ESCAPES[source[index]])
        elif character == "$" and index + 1 < len(source) and source[index + 1] == "{":
            raise ValueError("THIRD_PARTY_NOTICE_TEXT must not use interpolation")
        else:
            output.append(character)
        index += 1
    raise ValueError("THIRD_PARTY_NOTICE_TEXT template literal is unterminated")


def main() -> int:
    if len(sys.argv) != 4:
        print("usage: verify_open_source_notice.py ROOT_NOTICE OPEN_SOURCE_TEXTS CORE_LOCK", file=sys.stderr)
        return 2
    root_notice = Path(sys.argv[1]).read_text(encoding="utf-8")
    source = Path(sys.argv[2]).read_text(encoding="utf-8")
    in_app_notice = extract_template_literal(source)
    if in_app_notice != root_notice:
        print("in-app THIRD_PARTY_NOTICE_TEXT differs from THIRD_PARTY_NOTICES.md", file=sys.stderr)
        return 1
    lock = json.loads(Path(sys.argv[3]).read_text(encoding="utf-8"))
    expected_values = (
        lock["sing_box"]["version"],
        lock["sing_box"]["commit"],
        lock["gvisor"]["version"],
        lock["gvisor"]["commit"],
        lock["ohos_go"]["openharmony_port_commit"],
        lock["ohos_go"]["upstream_go_tag"],
        lock["ohos_go"]["upstream_go_commit"],
    )
    if any(value not in root_notice for value in expected_values):
        print("THIRD_PARTY_NOTICES.md does not match third_party/core-lock.json", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, UnicodeError, ValueError, KeyError, TypeError) as error:
        print(f"notice verification failed: {error}", file=sys.stderr)
        raise SystemExit(1)
