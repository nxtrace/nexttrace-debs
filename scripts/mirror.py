#!/usr/bin/env python3

import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from types import SimpleNamespace
from urllib.parse import quote

from release import (
    KEY_FINGERPRINT, METADATA, download_assets, gh, package_fields, package_names,
    require, sha256, verify,
)


# Keep InRelease last. Clients using By-Hash can still fetch either generation.
MUTABLE = ("Packages", "Release", "Release.gpg", "nexttrace-archive-keyring.gpg",
           "nexttrace-archive-keyring.asc", "InRelease")
REVALIDATE = "no-cache"
IMMUTABLE = "public, max-age=7776000, immutable"


def s3(operation, *args):
    return subprocess.run(
        ["aws", "--no-cli-pager", "--output", "json", "--region", "auto", "--endpoint-url", os.environ["APT_R2_ENDPOINT"],
         "s3api", operation, *args],
        capture_output=True, text=True,
    )


def result(response):
    require(response.returncode == 0, response.stderr.strip())
    return json.loads(response.stdout or "{}")


def put_once(bucket, key, path, cache):
    digest = sha256(path)
    content_md5 = base64.b64encode(hashlib.md5(path.read_bytes(), usedforsecurity=False).digest()).decode()
    response = s3("put-object", "--bucket", bucket, "--key", key, "--body", str(path),
                  "--if-none-match", "*", "--metadata", f"sha256={digest}", "--cache-control", cache,
                  "--content-md5", content_md5)
    if response.returncode == 0:
        return
    if "(PreconditionFailed)" not in response.stderr and "(412)" not in response.stderr:
        result(response)
    existing = result(s3("head-object", "--bucket", bucket, "--key", key))
    require(existing["ContentLength"] == path.stat().st_size, f"Immutable object conflicts: {key}")
    stored_digest = existing.get("Metadata", {}).get("sha256")
    if stored_digest is None:
        # The Wrangler bootstrap cannot attach S3 user metadata.
        with tempfile.TemporaryDirectory() as directory:
            saved = Path(directory) / "object"
            result(s3("get-object", "--bucket", bucket, "--key", key, str(saved)))
            stored_digest = sha256(saved)
    require(stored_digest == digest, f"Immutable object conflicts: {key}")


def activate(bucket, tag):
    require(re.fullmatch(r"(?:debian-)?v[0-9]+(?:\.[0-9]+){2,}(?:-r[1-9][0-9]*)?", tag),
            f"Invalid snapshot tag: {tag}")
    prefix = f"snapshots/{tag}"
    for name in MUTABLE:
        result(s3("head-object", "--bucket", bucket, "--key", f"{prefix}/{name}"))
    for name in MUTABLE:
        source = quote(f"{bucket}/{prefix}/{name}")
        result(s3("copy-object", "--bucket", bucket, "--key", name, "--copy-source", source))


def sync(bucket, output):
    latest = gh("releases/latest")
    require(latest["draft"] is False and latest["prerelease"] is False, "Expected a published stable release")
    tag = latest["tag_name"]
    download_assets(latest, METADATA, output)
    index = output / "Packages"
    packages = index.read_bytes()
    versions = {fields["Version"] for fields in package_fields(packages)}
    names = package_names(packages)
    require(len(versions) == 1 and len(names) == 33, "Expected 33 packages from one stable version")
    download_assets(latest, names, output)
    verify(SimpleNamespace(output=output, names=names, fingerprint=KEY_FINGERPRINT), allow_legacy_release=True)

    for name in sorted(names):
        put_once(bucket, name, output / name, IMMUTABLE)
    for algorithm in ("SHA256", "SHA512"):
        digest = hashlib.new(algorithm.lower(), packages).hexdigest()
        put_once(bucket, f"by-hash/{algorithm}/{digest}", index, IMMUTABLE)
    for name in MUTABLE:
        put_once(bucket, f"snapshots/{tag}/{name}", output / name, REVALIDATE)
    activate(bucket, tag)
    print(f"APT mirror serving {tag} ({next(iter(versions))})")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--activate", metavar="TAG", help="Restore a retained snapshot")
    args = parser.parse_args()
    bucket = os.environ["APT_R2_BUCKET"]
    if args.activate:
        activate(bucket, args.activate)
    else:
        with tempfile.TemporaryDirectory() as directory:
            sync(bucket, Path(directory))


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        sys.exit(str(error))
