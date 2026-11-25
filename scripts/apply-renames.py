#!/usr/bin/env python3
"""Apply (or only check) the text replacements listed in renames.txt.

Usage: apply-renames.py RENAMES_FILE SOURCE_DIR [--check] [--prefix P] [--app-name N] [--camera-name N]

--check only verifies that every "text to find" is present; it changes nothing.
Exits 1 and lists the problems if any line doesn't match.
"""
import argparse
import pathlib
import sys


def load_rules(path):
    rules = []
    for lineno, raw in enumerate(pathlib.Path(path).read_text().splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = [p.strip() for p in line.split(" | ")]
        if len(parts) != 3:
            sys.exit(f"{path}:{lineno}: expected 'file | find | replace'")
        rules.append((lineno, *parts))
    return rules


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("renames")
    ap.add_argument("source")
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--prefix", default="com.obs4k.obs-studio")
    ap.add_argument("--app-name", default="OBS Studio 4K")
    ap.add_argument("--camera-name", default="OBS Virtual Camera 4K")
    args = ap.parse_args()

    values = {"@PREFIX@": args.prefix, "@APP_NAME@": args.app_name, "@CAMERA_NAME@": args.camera_name}
    src = pathlib.Path(args.source)
    problems = []
    # Group by file so each file is read and written once, in rule order.
    by_file = {}
    for rule in load_rules(args.renames):
        by_file.setdefault(rule[1], []).append(rule)

    for rel, rules in by_file.items():
        path = src / rel
        if not path.is_file():
            problems.append(f"missing file: {rel}")
            continue
        text = path.read_text()
        for lineno, _, find, replace in rules:
            for key, val in values.items():
                replace = replace.replace(key, val)
            count = text.count(find)
            if count == 0:
                problems.append(f"renames.txt line {lineno}: '{find}' not found in {rel}")
                continue
            text = text.replace(find, replace)
            if not args.check:
                print(f"  {rel}: {count}x '{find}' -> '{replace}'")
        if not args.check:
            path.write_text(text)

    if problems:
        print("Rename problems:", *problems, sep="\n  ", file=sys.stderr)
        sys.exit(1)
    if args.check:
        print("All renames match.")


if __name__ == "__main__":
    main()
