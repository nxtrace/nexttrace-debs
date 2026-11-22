#!/usr/bin/env python3

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys


UPSTREAM = "nxtrace/NTrace-core"
TAG_PATTERN = r"v[0-9]+(?:\.[0-9]+){2,}(?:-[A-Za-z0-9]+(?:[.-][A-Za-z0-9]+)*)?"
DIGEST_PATTERN = r"sha256:([0-9a-f]{64})"
METADATA = {
    "Packages", "Release", "Release.gpg", "InRelease",
    "nexttrace-archive-keyring.gpg", "nexttrace-archive-keyring.asc",
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def run(*args):
    return subprocess.check_output(args)


def download(url):
    return run("curl", "-fsSL", "--retry", "3", "--retry-delay", "1", url)


def release_fields(tag, revision):
    require(re.fullmatch(TAG_PATTERN, tag), f"Invalid upstream tag: {tag}")
    require(re.fullmatch(r"[1-9][0-9]*", revision), f"Invalid package revision: {revision}")
    release_tag = tag if revision == "1" else f"debian-{tag}-r{revision}"
    return f"{tag[1:]}+{revision}", release_tag


def is_preview(release, tag):
    require(release["tag_name"] == tag and release["draft"] is False
            and isinstance(release["prerelease"], bool), "Invalid upstream release metadata")
    return release["prerelease"] or "-" in tag


def prepare(args):
    version, release_tag = release_fields(args.tag, args.revision)
    release = json.loads(download(f"https://api.github.com/repos/{UPSTREAM}/releases/tags/{args.tag}"))
    skip = is_preview(release, args.tag)
    args.metadata.write_text(json.dumps(release))
    print(f"skip={str(skip).lower()}\nversion={version}\nrelease_tag={release_tag}")


def digests(args):
    release = json.loads(args.metadata.read_bytes())
    require(not is_preview(release, args.tag), f"Skipping upstream prerelease {args.tag}")
    assets = {asset["name"]: asset for asset in release["assets"]}
    for name in args.names:
        asset = assets.get(name, {})
        digest = re.fullmatch(DIGEST_PATTERN, asset.get("digest") or "")
        require(asset.get("state") == "uploaded" and digest, f"Missing upstream asset or SHA-256: {name}")
        print(f"{digest[1]}  {name}")


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def package_fields(packages):
    for stanza in packages.decode().strip().split("\n\n"):
        yield dict(line.split(": ", 1) for line in stanza.splitlines() if not line.startswith((" ", "\t")))


def verify(args):
    output = args.output.resolve()
    require({file.name for file in output.iterdir()} == METADATA | set(args.names),
            "Unexpected files in package output")
    keyring = output / "nexttrace-archive-keyring.gpg"
    armored = output / "nexttrace-archive-keyring.asc"
    require(run("gpg", "--batch", "--no-options", "--dearmor", "--output", "-", armored) == keyring.read_bytes(),
            "Exported public keys differ")
    if args.fingerprint:
        print_keys = run("gpg", "--batch", "--no-options", "--with-colons", "--show-keys", keyring).decode().splitlines()
        fingerprints = [line.split(":")[9] for line in print_keys if line.startswith("fpr:")]
        require(sum(line.startswith("pub:") for line in print_keys) == 1
                and fingerprints and fingerprints[0] == args.fingerprint,
                "Signing key does not match the published APT key")
    release = output / "Release"
    run("gpgv", "--keyring", keyring, output / "Release.gpg", release)
    require(run("gpgv", "--keyring", keyring, "--output", "-", output / "InRelease")
            == release.read_bytes(), "InRelease content differs from Release")
    index = output / "Packages"
    checksums = re.search(r"(?m)^SHA256:\n((?:[ \t]+[^\n]+\n)+)", release.read_text())
    require(checksums and checksums[1].split() == [sha256(index), str(index.stat().st_size), "Packages"],
            "Release does not match Packages")
    seen = set()
    for fields in package_fields(index.read_bytes()):
        name = f"{fields['Package']}_{fields['Version']}_{fields['Architecture']}.deb"
        require(name in args.names and name not in seen and fields["Filename"] == f"./{name}",
                f"Unexpected or duplicate Packages entry: {name}")
        package = output / name
        require(fields["SHA256"] == sha256(package) and int(fields["Size"]) == package.stat().st_size,
                f"Packages checksum or size mismatch: {name}")
        seen.add(name)
    require(seen == set(args.names), "Packages does not list the complete package matrix")


def gh(endpoint, *args):
    repo = os.environ["GITHUB_REPOSITORY"]
    return json.loads(run("gh", "api", f"repos/{repo}/{endpoint}", *args))


def check_publish(args):
    releases = gh("releases?per_page=100", "--paginate", "--slurp")
    for page in releases:
        for release in page:
            if release["tag_name"] == args.tag:
                require(release["draft"] is True and release["target_commitish"] == args.commit,
                        f"Release {args.tag} is public or belongs to another commit")
    ref = f"refs/tags/{args.tag}"
    refs = dict(line.split("\t")[::-1] for line in run("git", "ls-remote", "origin", ref, ref + "^{}")
                .decode().splitlines())
    require(not refs or refs.get(ref + "^{}", refs.get(ref)) == args.commit,
            f"Git tag {args.tag} points to another commit")
    latest = gh("releases/latest")
    index, = [asset for asset in latest["assets"] if asset["name"] == "Packages"]
    packages = download(index["browser_download_url"])
    require(index["digest"] == "sha256:" + hashlib.sha256(packages).hexdigest(),
            "Could not verify the current stable Packages index")
    current, = {fields["Version"] for fields in package_fields(packages)}
    require(subprocess.run(["dpkg", "--compare-versions", args.version, "gt", current]).returncode == 0,
            f"Candidate {args.version} must be newer than current stable {current}")


def publish(args):
    endpoint = f"releases/{args.id}"
    release = gh(endpoint)
    require(release["tag_name"] == args.tag and release["draft"] is True
            and release["prerelease"] is False and release["target_commitish"] == args.commit,
            "Unexpected draft release")
    expected = {file.name: (file.stat().st_size, f"sha256:{sha256(file)}")
                for file in args.output.iterdir()}
    uploaded = {asset["name"]: (asset["size"], asset["digest"])
                for asset in release["assets"] if asset["state"] == "uploaded"}
    require(len(release["assets"]) == len(expected) and uploaded == expected,
            "Draft release assets do not match the verified build")
    published = gh(endpoint, "--method", "PATCH", "-F", "draft=false", "-f", "make_latest=true")
    require(published["draft"] is False and published["tag_name"] == args.tag,
            "Unexpected publish response")


def main():
    parser = argparse.ArgumentParser()
    commands = parser.add_subparsers(required=True)
    for fn, fields in (
        (prepare, ("tag", "revision", "metadata")),
        (digests, ("tag", "metadata", "names")),
        (verify, ("output", "fingerprint", "names")),
        (check_publish, ("tag", "commit", "version")),
        (publish, ("tag", "commit", "id", "output")),
    ):
        command = commands.add_parser(fn.__name__.replace("_", "-"))
        for field in fields:
            if field == "names":
                command.add_argument(field, nargs="+")
            else:
                command.add_argument(field, type=Path if field in {"metadata", "output"} else str)
        command.set_defaults(func=fn)
    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        sys.exit(str(error))
