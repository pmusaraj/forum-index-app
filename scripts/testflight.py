#!/usr/bin/env python3
"""Configure private App Store Connect credentials and upload an existing archive."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile
import uuid

REPO = Path(__file__).resolve().parent.parent
PRIVATE_DIR = Path.home() / "Library/Application Support/Forum Index/App Store Connect"


def private_write(path, data):
    # Create with private permissions before writing any credentials.
    fd, temporary = tempfile.mkstemp(dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(data)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def configure(args):
    if not re.fullmatch(r"[A-Z0-9]{10}", args.key_id):
        raise ValueError("Expected a 10-character App Store Connect key ID.")
    issuer_id = str(uuid.UUID(args.issuer_id))
    source = Path(args.key_path).expanduser().resolve(strict=True)
    # Validate without printing or logging the key material.
    check = subprocess.run(["openssl", "pkey", "-in", str(source), "-noout"],
                           stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if check.returncode:
        raise ValueError("The key file is not a readable, unencrypted private key.")
    PRIVATE_DIR.mkdir(parents=True, exist_ok=True, mode=0o700)
    PRIVATE_DIR.chmod(0o700)
    key_path = PRIVATE_DIR / f"AuthKey_{args.key_id}.p8"
    private_write(key_path, source.read_bytes())
    config = {"key_id": args.key_id, "issuer_id": issuer_id, "key_path": str(key_path)}
    private_write(PRIVATE_DIR / "credentials.json", json.dumps(config, indent=2).encode() + b"\n")
    print("Saved private credentials outside the repository. The original key file is unchanged.")


def credentials():
    config_path = PRIVATE_DIR / "credentials.json"
    for path in (PRIVATE_DIR, config_path):
        if path.stat().st_uid != os.getuid() or path.stat().st_mode & 0o077:
            raise ValueError("Credential directory and config must be accessible only to your user.")
    config = json.loads(config_path.read_text())
    key_path = Path(config["key_path"])
    if not key_path.is_absolute() or not key_path.is_file():
        raise ValueError("The configured private key file is missing.")
    if key_path.stat().st_uid != os.getuid() or key_path.stat().st_mode & 0o077:
        raise ValueError("The private key must be accessible only to your user.")
    return ["-authenticationKeyPath", str(key_path), "-authenticationKeyID", config["key_id"],
            "-authenticationKeyIssuerID", config["issuer_id"]]


def upload(args):
    authentication = credentials()
    archive = Path(args.archive).expanduser().resolve(strict=True)
    with (archive / "Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    if info.get("ApplicationProperties", {}).get("CFBundleIdentifier") != "com.musaraj.forumindex":
        raise ValueError("Expected a signed Forum Index iOS archive.")
    with (REPO / "Config/ExportOptions-AppStore.plist").open("rb") as stream:
        options = plistlib.load(stream)
    identities = subprocess.run(["security", "find-identity", "-v", "-p", "codesigning"],
                                capture_output=True, text=True)
    identity_pattern = r'"(?:Apple|iPhone|iOS) Distribution: [^"\n]+ \(' + re.escape(options["teamID"]) + r'\)"'
    if identities.returncode or not re.search(identity_pattern, identities.stdout):
        raise ValueError("No valid local Apple Distribution identity for this team. In Xcode Settings → "
                         "Accounts → your team → Manage Certificates, create Apple Distribution, "
                         "or import an existing certificate with its private key.")
    options["destination"] = "export" if args.export_only else "upload"
    # Xcode distribution logs can contain IDs and key paths: keep them outside Git too.
    with tempfile.TemporaryDirectory(prefix="forum-index-export-") as temporary:
        export_options = Path(temporary) / "ExportOptions.plist"
        export_options.write_bytes(plistlib.dumps(options))
        log_dir = PRIVATE_DIR / "logs"
        log_dir.mkdir(exist_ok=True, mode=0o700)
        fd, log_path = tempfile.mkstemp(prefix="export-", suffix=".log", dir=log_dir)
        command = ["xcodebuild", "-exportArchive", "-archivePath", str(archive),
                   "-exportPath", str(REPO / "build" / (archive.stem + "-export")),
                   "-exportOptionsPlist", str(export_options), "-allowProvisioningUpdates", *authentication]
        print("Exporting archive…" if args.export_only else "Uploading archive to TestFlight…", flush=True)
        with os.fdopen(fd, "w") as log:
            result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT)
        if result.returncode:
            raise ValueError(f"Xcode export failed. See the private log: {log_path}")
    print("Export succeeded." if args.export_only else "Upload succeeded; Apple will process the build.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    setup = commands.add_parser("configure", help="Copy a key and save its IDs in private local storage")
    setup.add_argument("--key-id", required=True)
    setup.add_argument("--issuer-id", required=True)
    setup.add_argument("--key-path", required=True)
    send = commands.add_parser("upload", help="Upload a signed iOS archive using the saved key")
    send.add_argument("archive")
    send.add_argument("--export-only", action="store_true", help="Export locally without uploading")
    commands.add_parser("check", help="Check local configuration and permissions; does not contact Apple")
    args = parser.parse_args()
    try:
        if args.command == "configure":
            configure(args)
        elif args.command == "upload":
            upload(args)
        else:
            credentials()
            print("Private credential configuration is ready. Apple access has not been verified.")
    except (OSError, ValueError, KeyError, plistlib.InvalidFileException) as error:
        parser.exit(1, f"{error}\n")


if __name__ == "__main__":
    main()
