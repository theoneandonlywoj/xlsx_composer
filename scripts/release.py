"""Publish one new xlsx_composer version from clean, synchronized main."""

from datetime import datetime, timezone
from http.client import HTTPException
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import signal
import subprocess
import sys
import time
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


ROOT = Path(__file__).resolve().parent.parent
VERSION_PATTERN = r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)"
BUMPS = {"MAJOR": "MAJOR", "MA": "MAJOR", "MINOR": "MINOR", "MI": "MINOR",
         "SMALL": "SMALL", "S": "SMALL"}
RELEASE_FILES = ("VERSION", "README.md", "CHANGELOG.md")


def _require(condition, message):
    if not condition:
        raise ValueError(message)


def _run(*args, env=None):
    return subprocess.run(args, check=True, text=True, stdout=subprocess.PIPE,
                          env=env).stdout.strip()


def _bump_level(value):
    level = BUMPS.get(value.strip().upper())
    _require(level, "Choose MAJOR (MA), MINOR (MI), or SMALL (S, patch).")
    return level


def _hex_metadata(version, timeout):
    """Anonymous public metadata; None means a definite HTTP 404 only."""
    request = Request(f"https://hex.pm/api/packages/xlsx_composer/releases/{version}",
                      headers={"Accept": "application/json",
                               "User-Agent": "xlsx_composer-release/1.0"})
    try:
        with urlopen(request, timeout=timeout) as response:
            _require(response.status == 200, "Unknown Hex HTTP response.")
            metadata = json.loads(response.read())
    except HTTPError as error:
        error.close()
        if error.code == 404:
            return None
        raise ValueError(f"Hex state unknown (HTTP {error.code}); inspect before retrying.") from None
    except (URLError, OSError, HTTPException, ValueError):
        # Do not include transport errors that might contain proxy credentials.
        raise ValueError("Hex state unknown (transport or invalid JSON); inspect before retrying.") from None
    _require(isinstance(metadata, dict) and metadata.get("version") == version and
             isinstance(metadata.get("has_docs"), bool),
             "Hex state unknown (invalid or wrong-version metadata); inspect before retrying.")
    return metadata


def _verify_hex(version):
    """60s application polling budget; sockets have <=10s inactivity timeouts.

    This cannot cancel a server that continuously streams a response body.
    Recheck the budget after consuming the body, before accepting completion.
    """
    deadline = time.monotonic() + 60
    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            break
        try:
            metadata = _hex_metadata(version, min(10, remaining))
        except ValueError:
            metadata = None
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            break
        if metadata is not None and metadata["has_docs"]:
            return
        time.sleep(min(2, remaining))
    raise ValueError(f"Hex completion unverified for {version}: expected version and has_docs=true within 60s.")


def _documents(current, version):
    readme = Path("README.md").read_text()
    marker = f"<!-- release-version: {current} -->"
    dependency = f'{{:xlsx_composer, "~> {current}"}}'
    _require(len(re.findall(r"<!--\s*release-version[^\n]*", readme)) == 1 and
             readme.count(marker) == 1 and
             len(re.findall(r"\{:xlsx_composer,[^\n]*", readme)) == 1 and
             readme.count(dependency) == 1,
             "Expected exactly one matching README marker and install snippet; synchronize release documentation first.")
    readme = readme.replace(marker, f"<!-- release-version: {version} -->", 1)
    readme = readme.replace(dependency, f'{{:xlsx_composer, "~> {version}"}}', 1)
    changelog = Path("CHANGELOG.md").read_text()
    top = re.search(r"^## .*$", changelog, re.MULTILINE)
    _require(top and re.fullmatch(rf"## {VERSION_PATTERN} \(unreleased\)", top.group()),
             "First CHANGELOG heading must be '## X.Y.Z (unreleased)'; synchronize release documentation first.")
    stamped = f"## {version} ({datetime.now(timezone.utc).date().isoformat()})"
    return (version + "\n", readme, changelog[:top.start()] + stamped + changelog[top.end():])


def _recovery(version, repository, destination, stage):
    tag = f"v{version}"
    print(f"Release {version}; tag {tag}; repository {repository}; last known stage: {stage}.", file=sys.stderr)
    print("Preserve this state. Inspect files/index/commit, annotated tag peel, BOTH remote refs, GitHub and Hex:", file=sys.stderr)
    commands = [
        ["git", "status", "--short"],
        ["git", "diff", "--", *RELEASE_FILES],
        ["git", "diff", "--cached", "--", *RELEASE_FILES],
        ["git", "show", "HEAD", "--", *RELEASE_FILES],
        ["git", "cat-file", "-t", tag],
        ["git", "rev-parse", f"{tag}^{{}}"],
        ["git", "ls-remote", destination, "refs/heads/main", f"refs/tags/{tag}", f"refs/tags/{tag}^{{}}"],
        ["gh", "release", "view", tag, "--repo", repository],
        ["mix", "hex.info", "xlsx_composer", version],
    ]
    for command in commands:
        print(shlex.join(command), file=sys.stderr)
    print(f"Read anonymous https://hex.pm/api/packages/xlsx_composer/releases/{version}; verify version and has_docs=true.", file=sys.stderr)
    print("Partial writes/index: inspect and complete or restore ONLY this operation's known file changes. "
          "A commit failure leaves the index; a tag failure leaves the commit. Compare the commit contents before tagging. "
          "A rejected atomic push changes neither ref; an interrupted/failed response is UNKNOWN until both refs are inspected. "
          "Push only known missing matching refs, atomically when both are missing; preserve conflicting state.", file=sys.stderr)
    print(f"If the matching release commit/tag are local only, after inspection: git tag -a {tag} -m 'Release {tag}' "
          f"(only if tag is absent); git push --atomic {shlex.quote(destination)} HEAD:refs/heads/main refs/tags/{tag}", file=sys.stderr)
    print("Finish a definitely missing GitHub release first, after verifying remote refs:", file=sys.stderr)
    print(shlex.join(["gh", "release", "create", tag, "--repo", repository,
                      "--verify-tag", "--generate-notes", "--title", tag]), file=sys.stderr)
    print(f"From a separate clean checkout of exact existing tag {tag}, with dependencies/ExDoc installed: "
          "if Hex package is definitely absent, mix hex.publish --yes; "
          "if package exists and docs are absent, mix hex.publish docs --yes. Verify public metadata afterward. "
          "GitHub/Hex may have succeeded despite an error. Unknown state: inspect, never blindly republish, "
          "replace, roll back, rerun the bump, or dispatch a new version to repair this one.", file=sys.stderr)


def release(bump):
    os.chdir(ROOT)
    for tool in ("git", "mix", "gh"):
        _require(shutil.which(tool), f"Required tool unavailable: {tool}.")
    _require(not _run("git", "status", "--porcelain", "--untracked-files=all"),
             "Commit or stash all changes, including untracked files, before releasing.")
    _require(_run("git", "branch", "--show-current") == "main", "Run releases from attached main.")
    head = _run("git", "rev-parse", "HEAD")
    raw = Path("VERSION").read_text()
    _require(re.fullmatch(VERSION_PATTERN + r"\n?", raw),
             "VERSION must contain MAJOR.MINOR.PATCH without leading zeroes.")
    current = raw.rstrip("\n")
    major, minor, patch = map(int, current.split("."))
    versions = {"MAJOR": f"{major + 1}.0.0", "MINOR": f"{major}.{minor + 1}.0", "SMALL": f"{major}.{minor}.{patch + 1}"}
    if bump is None:
        print(f"Current version: {current}")
        for level, version in versions.items():
            print(f"  {level}: {version}")
        bump = _bump_level(input("Version upgrade [MAJOR/MINOR/SMALL or MA/MI/S]: "))
    version = versions[bump]
    tag = f"v{version}"
    replacements = _documents(current, version)
    _require(not _run("git", "tag", "--list", tag), f"Tag {tag} already exists locally.")
    destinations = _run("git", "remote", "get-url", "--push", "--all", "origin").splitlines()
    _require(len(destinations) == 1, "origin must have exactly one push destination.")
    destination = destinations[0]
    refs = dict(line.split()[::-1] for line in _run(
        "git", "ls-remote", destination, "refs/heads/main", f"refs/tags/{tag}"
    ).splitlines())
    _require(f"refs/tags/{tag}" not in refs, f"Tag {tag} already exists on origin.")
    _require(refs.get("refs/heads/main") == head, "Local main must match the origin push destination's main.")
    repository = _run("gh", "repo", "view", destination, "--json", "nameWithOwner", "--jq", ".nameWithOwner")
    _require(re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository),
             "Could not resolve the GitHub repository for origin's push destination.")
    stage = "preflight; no release mutations"
    try:
        _require(os.environ.get("GITHUB_ACTIONS") != "true" or os.environ.get("HEX_API_KEY", "").strip(),
                 "GITHUB_ACTIONS requires a nonblank HEX_API_KEY before release mutation.")
        _require(_hex_metadata(version, 10) is None, f"Hex target {version} already exists; inspect the existing release.")
        print(f"Releasing {current} → {version} to {repository}; validating before mutation.", flush=True)
        checks = [("deps.unlock", "--check-unused"), ("compile", "--force", "--warnings-as-errors"),
                  ("compile", "--force", "--warnings-as-errors"), ("quality",), ("test",),
                  ("docs", "--warnings-as-errors")]
        for index, check in enumerate(checks):
            env = {**os.environ, "MIX_ENV": "test" if index in (2, 4) else "dev"}
            subprocess.run(["mix", *check], env=env, check=True)
        subprocess.run(["scripts/package_check.sh"], check=True)
        _require(_run("git", "branch", "--show-current") == "main" and
                 _run("git", "rev-parse", "HEAD") == head and
                 not _run("git", "status", "--porcelain", "--untracked-files=all"),
                 "The checkout changed during validation; stopped before updating release files.")
        stage = "writing release files; partial/mixed files possible"
        for name, text in zip(RELEASE_FILES, replacements):
            Path(name).write_text(text)
        stage = "release files written; staging may be partial"
        _run("git", "add", "--", *RELEASE_FILES)
        stage = "release files staged; commit not confirmed"
        subprocess.run(["git", "commit", "-m", f"chore: release {tag}"], check=True)
        stage = "release commit exists; tag not confirmed"
        _run("git", "tag", "-a", tag, "-m", f"Release {tag}")
        stage = "local commit and annotated tag; atomic push response unknown, inspect both remote refs"
        subprocess.run(["git", "push", "--atomic", destination, "HEAD:refs/heads/main", f"refs/tags/{tag}"], check=True)
        stage = "commit and tag pushed; GitHub creation unconfirmed"
        subprocess.run(["gh", "release", "create", tag, "--repo", repository,
                        "--verify-tag", "--generate-notes", "--title", tag], check=True)
        stage = "GitHub release created; Hex package/docs upload unconfirmed"
        subprocess.run(["mix", "hex.publish", "--yes"], env={**os.environ, "MIX_ENV": "dev"}, check=True)
        stage = "Hex command exited zero; public package/docs completion unverified"
        _verify_hex(version)
    except (ValueError, OSError, subprocess.CalledProcessError, KeyboardInterrupt):
        _recovery(version, repository, destination, stage)
        raise
    print(f"Published {tag} to {repository} and Hex with docs (public metadata verified).")


def _interrupt(signum, frame):
    raise KeyboardInterrupt


def main():
    signal.signal(signal.SIGTERM, _interrupt)
    try:
        raw_bump = os.environ.get("RELEASE_BUMP")
        release(None if raw_bump is None else _bump_level(raw_bump))
    except (ValueError, OSError, EOFError, subprocess.CalledProcessError) as error:
        print(f"Release failed: {error}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print("Release interrupted; preserve and inspect current state before finishing the same version.", file=sys.stderr)
        return 130
    return 0


if __name__ == "__main__":
    sys.exit(main())
