#!/usr/bin/env python3
"""Create, check and package zbox extensions without executing extension code."""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import tempfile
import zipfile

REPO = Path(__file__).resolve().parent.parent
IGNORED = {".git", ".build", ".swiftpm", ".sdk", "__pycache__", ".DS_Store"}


def relative_path(value):
    if (not value or value.startswith("/") or "\\" in value or "\0" in value
            or any(part in ("", ".", "..") for part in value.split("/"))):
        raise ValueError("Entry must be a package-relative path")
    return Path(value)


def files(root):
    for base, directories, names in os.walk(root, followlinks=False):
        directories[:] = [name for name in directories if name not in IGNORED]
        for name in directories + names:
            path = Path(base) / name
            if path.is_symlink():
                raise ValueError("Packages cannot contain symbolic links")
        for name in names:
            if name not in IGNORED:
                path = Path(base) / name
                if not stat.S_ISREG(path.stat().st_mode):
                    raise ValueError("Packages can contain only regular files")
                yield path


def validate(root):
    manifest = json.loads((root / "manifest.json").read_text(encoding="utf-8"))
    if (manifest.get("schemaVersion") != 1 or
            not re.fullmatch(r"[a-z0-9-]+(?:\.[a-z0-9-]+)+", manifest.get("id", "")) or
            not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", manifest.get("version", "")) or
            not manifest.get("name")):
        raise ValueError("Invalid package identity, version or schemaVersion")
    commands = manifest.get("commands", [])
    if not 1 <= len(commands) <= 100 or len({c["id"] for c in commands}) != len(commands):
        raise ValueError("Commands must have unique IDs (1–100 commands)")
    entries = list(files(root))
    if len(entries) > 4096 or sum(p.stat().st_size for p in entries) > 128 * 1024 * 1024:
        raise ValueError("Package exceeds the file count or size limit")
    for command in commands:
        if not re.fullmatch(r"[A-Za-z0-9_-]+", command["id"]) or command.get("mode") not in ("task", "interactive"):
            raise ValueError("Invalid command identity or mode")
        if command["mode"] == "interactive" and command.get("protocolVersion") != 1:
            raise ValueError("Interactive commands require protocolVersion 1")
        entry = root / relative_path(command["entry"])
        if entry not in entries:
            raise ValueError("A command entry is missing; build native executables before packaging")
        if not command.get("interpreter") and not os.access(entry, os.X_OK):
            raise ValueError("A native entry must be executable")
    return manifest


def initialize(args):
    if args.output.exists():
        raise ValueError("The output directory already exists")
    template = {"shell": "hello-task", "python": "python-text", "swift": "swift-text"}[args.language]
    shutil.copytree(REPO / "examples/extensions" / template, args.output,
                    ignore=shutil.ignore_patterns(*IGNORED))
    manifest_path = args.output / "manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    manifest["id"] = args.id
    manifest["name"] = args.name or args.id
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    if args.language == "python":
        shutil.copy2(REPO / "SDK/python/zbox_sdk.py", args.output / "zbox_sdk.py")
    if args.language == "swift":
        sdk = args.output / ".sdk/ZboxExtensionKit"
        shutil.copytree(REPO / "Packages/ZboxExtensionKit", sdk, ignore=shutil.ignore_patterns(*IGNORED))
        package = args.output / "Package.swift"
        package.write_text(package.read_text().replace("../../../Packages/ZboxExtensionKit", ".sdk/ZboxExtensionKit"))
    print("Created extension project. Edit its manifest and commands before sharing.")


def pack(args):
    if args.output.exists():
        raise ValueError("The output file already exists")
    with tempfile.TemporaryDirectory(prefix="zbox-extension-") as directory:
        root = Path(directory)
        for path in files(args.source):
            relative = path.relative_to(args.source)
            # Build sources are not runtime resources of the Swift template.
            if (args.source / "Package.swift").exists() and (relative.parts[0] == "Sources" or relative.name in ("Package.swift", "Package.resolved")):
                continue
            target = root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, target)
        if args.python_sdk:
            shutil.copy2(REPO / "SDK/python/zbox_sdk.py", root / "zbox_sdk.py")
        if args.binary:
            manifest = json.loads((root / "manifest.json").read_text(encoding="utf-8"))
            native = {c["entry"] for c in manifest["commands"] if not c.get("interpreter")}
            if len(native) != 1:
                raise ValueError("--binary requires exactly one distinct native entry")
            target = root / relative_path(native.pop())
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(args.binary, target)
            manifest["architectures"] = subprocess.check_output(["/usr/bin/lipo", "-archs", str(args.binary)], text=True).split()
            (root / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        validate(root)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(args.output, "x", compression=zipfile.ZIP_DEFLATED, allowZip64=False) as archive:
            for path in files(root):
                archive.write(path, path.relative_to(root))
    print("Created package:", args.output)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    create = commands.add_parser("init")
    create.add_argument("--language", choices=("shell", "python", "swift"), required=True)
    create.add_argument("--id", required=True)
    create.add_argument("--name")
    create.add_argument("output", type=Path)
    check = commands.add_parser("validate")
    check.add_argument("source", type=Path)
    build = commands.add_parser("pack")
    build.add_argument("source", type=Path)
    build.add_argument("output", type=Path)
    build.add_argument("--python-sdk", action="store_true")
    build.add_argument("--binary", type=Path)
    args = parser.parse_args()
    try:
        if args.command == "init":
            if not re.fullmatch(r"[a-z0-9-]+(?:\.[a-z0-9-]+)+", args.id):
                raise ValueError("Use a reverse-domain extension ID")
            initialize(args)
        elif args.command == "validate":
            validate(args.source)
            print("Static package checks passed. The host also checks runtime compatibility at installation.")
        else:
            pack(args)
    except (ValueError, OSError, KeyError, TypeError, subprocess.CalledProcessError) as error:
        parser.exit(1, str(error) + "\n")


if __name__ == "__main__":
    main()
