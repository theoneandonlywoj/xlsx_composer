"""Real Make/Git release boundaries; publishers and anonymous HTTP are local fakes."""

import importlib.util
from http.client import IncompleteRead
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch
from urllib.error import HTTPError, URLError


ROOT = Path(__file__).resolve().parent.parent
SPEC = importlib.util.spec_from_file_location("release", ROOT / "scripts/release.py")
release = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(release)
FILES = ["CHANGELOG.md", "README.md", "VERSION"]
OLD_CHANGELOG = "# Changelog\n\n## 0.4.1 (unreleased)\n\n- New.\n\n## 0.3.9 (unreleased)\n\n- Old.\n"


def release_step():
    """The Release workflow's final step: its env names and run command."""
    step = (ROOT / ".github/workflows/release.yml").read_text().rsplit("\n      - ", 1)[1]
    assert step.startswith("name: Release\n"), step
    return re.findall(r"^          (\w+):", step, re.MULTILINE), re.search(r"^        run: (.+)$", step, re.MULTILINE).group(1)


# Executed only inside an isolated fixture. No release implementation flags exist.
LAUNCHER = r'''
import importlib.util, json, os, pathlib, sys
from datetime import datetime, timezone, timedelta
from types import SimpleNamespace
from urllib.error import HTTPError, URLError
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("fixture_release", sys.argv[-1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
logpath = pathlib.Path(os.environ["FIXTURE_LOG"])
statepath = pathlib.Path(os.environ["FIXTURE_STATE"])
def log(event):
    with logpath.open("a") as stream: stream.write(json.dumps(event) + "\n")
log({"tool": "launcher", "bump": os.environ.get("RELEASE_BUMP"), "original_bump": os.environ.get("bump")})
class FrozenDate(datetime):
    @classmethod
    def now(cls, tz=None):
        instant = datetime(2026, 11, 12, 0, 30, tzinfo=timezone.utc)
        return instant.astimezone(tz) if tz else instant.astimezone(timezone(timedelta(hours=-10))).replace(tzinfo=None)
mod.datetime = FrozenDate
clock = [0.0]
mod.time = SimpleNamespace(monotonic=lambda: clock[0], sleep=lambda seconds: clock.__setitem__(0, clock[0] + seconds))
class Response:
    status = 200
    def __init__(self, body): self.body = body
    def __enter__(self): return self
    def __exit__(self, *args): pass
    def read(self): return self.body
def transport(request, timeout):
    headers = dict(request.header_items())
    version = request.full_url.rsplit("/", 1)[1]
    assert request.full_url == "https://hex.pm/api/packages/xlsx_composer/releases/" + version
    assert headers == {"Accept": "application/json", "User-agent": "xlsx_composer-release/1.0"}
    assert 0 < timeout <= 10
    log({"tool": "http", "url": request.full_url, "headers": headers, "timeout": timeout})
    mode = os.environ.get("HTTP_MODE", "")
    state = json.loads(statepath.read_text())
    if mode == "timeout": raise URLError("fixture timeout")
    if mode == "malformed": return Response(b"bad json")
    if mode == "wrong-version": return Response(b'{"version":"99.0.0","has_docs":true}')
    if mode == "server-error": raise HTTPError(request.full_url, 503, "fixture", {}, None)
    if mode == "after-publish-timeout" and state["hex"]: raise URLError("fixture timeout")
    metadata = state["hex"].get(version)
    if metadata is None: raise HTTPError(request.full_url, 404, "fixture", {}, None)
    return Response(json.dumps(metadata).encode())
mod.urlopen = transport
if os.environ.get("INTERRUPT_WRITE"):
    original = pathlib.Path.write_text
    def write(path, text, *args, **kwargs):
        if str(path) == "README.md": raise KeyboardInterrupt
        return original(path, text, *args, **kwargs)
    pathlib.Path.write_text = write
sys.exit(mod.main())
'''

TOOL = r'''
import json, os, pathlib, subprocess, sys
tool = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
logpath = pathlib.Path(os.environ["FIXTURE_LOG"])
statepath = pathlib.Path(os.environ["FIXTURE_STATE"])
with logpath.open("a") as stream:
    stream.write(json.dumps({"tool": tool, "args": args, "mix_env": os.environ.get("MIX_ENV")}) + "\n")
state = json.loads(statepath.read_text())
command = tool + " " + " ".join(args)
fail = os.environ.get("FAIL_COMMAND") == command or os.environ.get("FAIL_COMMAND") == command + ":" + os.environ.get("MIX_ENV", "")
if tool == "gh":
    if args[:2] == ["repo", "view"]:
        if fail: sys.exit(1)
        print("example/xlsx_composer")
    elif args[:2] == ["release", "view"]:
        sys.exit(0 if args[2] in state["github"] else 1)
    elif args[:2] == ["release", "create"]:
        if fail: sys.exit(1)
        assert args[2] not in state["github"]
        state["github"].append(args[2])
        statepath.write_text(json.dumps(state))
        if os.environ.get("GH_AMBIGUOUS"): sys.exit(1)
elif tool == "mix":
    if args[:1] == ["quality"] and os.environ.get("MUTATE_CHECK"):
        mode = os.environ["MUTATE_CHECK"]
        if mode == "branch": subprocess.run([os.environ["REAL_GIT"], "checkout", "-b", "other"], check=True)
        elif mode == "head": subprocess.run([os.environ["REAL_GIT"], "commit", "--allow-empty", "-m", "Changed during checks"], check=True)
        else: pathlib.Path("during-check").write_text("external edit")
    if args[:1] == ["hex.publish"]:
        version = pathlib.Path("VERSION").read_text().strip()
        assert "v" + version in state["github"], "GitHub must precede Hex"
        if fail and not os.environ.get("HEX_AMBIGUOUS"): sys.exit(1)
        docs_only = args[1:2] == ["docs"]
        if docs_only:
            assert version in state["hex"]
            state["docs_uploads"].append(version)
        else:
            assert version not in state["hex"]
            state["package_uploads"].append(version)
        state["hex"][version] = {"version": version, "has_docs": not bool(os.environ.get("NO_DOCS"))}
        statepath.write_text(json.dumps(state))
    if fail: sys.exit(1)
elif tool == "package-check":
    if fail: sys.exit(1)
'''

GIT_WRAPPER = r'''
import os, subprocess, sys
args = sys.argv[1:]
fault = os.environ.get("GIT_FAULT")
if fault == "tag" and args[:2] == ["tag", "-a"]: sys.exit(1)
if fault == "index" and args[:1] == ["add"]:
    subprocess.run([os.environ["REAL_GIT"], "add", "VERSION"], check=True)
    sys.exit(1)
result = subprocess.run([os.environ["REAL_GIT"], *args])
if fault == "push-response" and args[:2] == ["push", "--atomic"] and result.returncode == 0: sys.exit(1)
sys.exit(result.returncode)
'''


class Fixture:
    def __init__(self, case):
        self.temp = tempfile.TemporaryDirectory(prefix="xlsx-release-test-")
        case.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repo = self.root / "checkout"
        self.repo.mkdir()
        self.remote = self.root / "origin.git"
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.log = self.root / "commands.jsonl"
        self.state = self.root / "publications.json"
        self.state.write_text(json.dumps({"github": [], "hex": {}, "package_uploads": [], "docs_uploads": []}))
        home = self.root / "home"
        home.mkdir()
        # Never inherit credentials, Git settings or MAKEFLAGS from the caller.
        self.env = {key: os.environ[key] for key in ("PATH", "SYSTEMROOT", "TMPDIR") if key in os.environ}
        self.env.update(PATH=str(self.bin) + os.pathsep + os.environ["PATH"], HOME=str(home),
                        GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull,
                        FIXTURE_LOG=str(self.log), FIXTURE_STATE=str(self.state),
                        REAL_GIT=shutil.which("git"), TZ="Pacific/Honolulu")
        self.git("init", "--initial-branch=main")
        self.git("config", "user.name", "Release Fixture")
        self.git("config", "user.email", "fixture@example.test")
        self.command([self.env["REAL_GIT"], "init", "--bare", str(self.remote)], check=True)
        self.git("remote", "add", "origin", str(self.remote))
        for name in ("Makefile", "scripts/release.py"):
            path = self.repo / name
            path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy(ROOT / name, path)
        (self.repo / "VERSION").write_text("0.4.0\n")
        (self.repo / "README.md").write_text('<!-- release-version: 0.4.0 -->\n{:xlsx_composer, "~> 0.4.0"}\n')
        (self.repo / "CHANGELOG.md").write_text(OLD_CHANGELOG)
        self.executable(self.repo / "scripts/package_check.sh", TOOL, name="package-check")
        for name in ("mix", "gh"):
            self.executable(self.bin / name, TOOL)
        self.executable(self.bin / "python3", LAUNCHER)
        self.commit()
        self.git("push", "origin", "main")
        self.start = self.git("rev-parse", "HEAD")

    def executable(self, path, source, name=None):
        if name:
            # Keep the package command recognizable in the fake tool's log.
            source = source.replace('tool = pathlib.Path(sys.argv[0]).name', f'tool = {name!r}')
        path.write_text(f"#!{sys.executable}\n" + source)
        path.chmod(0o755)

    def command(self, args, *, cwd=None, check=False, input=None):
        return subprocess.run(args, cwd=cwd or self.repo, env=self.env, check=check,
                              input=input, capture_output=True, text=True)

    def git(self, *args):
        return self.command([self.env["REAL_GIT"], *args], check=True).stdout.strip()

    def commit(self):
        self.git("add", ".")
        self.git("commit", "-m", "Fixture preparation")

    def sync(self):
        self.commit()
        self.git("push", "origin", "main")

    def run(self, bump="SMALL", input=None):
        return self.command(["make", "release", *([] if bump is None else [f"bump={bump}"])], input=input)

    def dispatch(self, level="SMALL", **secrets):
        """Run the workflow's Release step command as Actions would, with fake secrets."""
        _, command = release_step()
        env = dict(self.env, GITHUB_ACTIONS="true", LEVEL=level, **secrets)
        return subprocess.run(["bash", "-e", "-c", command], cwd=self.repo, env=env,
                              capture_output=True, text=True)

    def events(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []

    def public(self):
        return json.loads(self.state.read_text())

    def snapshot(self):
        return {"files": {str(p.relative_to(self.repo)): p.read_bytes() for p in self.repo.rglob("*")
                          if p.is_file() and ".git" not in p.relative_to(self.repo).parts},
                "head": self.git("rev-parse", "HEAD"), "branch": self.git("branch", "--show-current"),
                "count": self.git("rev-list", "--count", "HEAD"),
                "status": self.git("status", "--porcelain", "--untracked-files=all"),
                "index": self.git("diff", "--cached", "--binary"),
                "refs": self.git("show-ref"), "remote": self.git("ls-remote", "origin"),
                "public": self.public()}

    def git_fault(self, fault):
        self.executable(self.bin / "git", GIT_WRAPPER)
        self.env["GIT_FAULT"] = fault

    def repair_missing_stages(self, case):
        """Execute the documented inspect-and-finish procedure from observed state."""
        self.env.pop("GIT_FAULT", None)
        self.env.pop("FAIL_COMMAND", None)
        self.env.pop("NO_DOCS", None)
        self.env.pop("INTERRUPT_WRITE", None)
        version, tag = "0.4.1", "v0.4.1"
        # Inspect every persistence boundary before deciding what remains.
        observed = self.snapshot()
        case.assertIn(observed["files"]["VERSION"], (b"0.4.0\n", b"0.4.1\n"))
        goals = {"VERSION": version + "\n",
                 "README.md": '<!-- release-version: 0.4.1 -->\n{:xlsx_composer, "~> 0.4.1"}\n',
                 "CHANGELOG.md": OLD_CHANGELOG.replace("## 0.4.1 (unreleased)", "## 0.4.1 (2026-11-12)", 1)}
        for name, goal in goals.items():
            path = self.repo / name
            if path.read_text() != goal:
                path.write_text(goal)
        if self.git("status", "--porcelain"):
            hook = self.repo / ".git/hooks/pre-commit"
            if hook.exists(): hook.unlink()
            self.git("add", "--", *FILES)
            self.git("commit", "-m", f"chore: release {tag}")
        case.assertEqual(sorted(self.git("show", "--name-only", "--format=", "HEAD").splitlines()), FILES)
        if not self.git("tag", "--list", tag):
            self.git("tag", "-a", tag, "-m", f"Release {tag}")
        case.assertEqual(self.git("cat-file", "-t", tag), "tag")
        case.assertEqual(self.git("rev-parse", f"{tag}^{{}}"), self.git("rev-parse", "HEAD"))
        refs = dict(line.split()[::-1] for line in self.git("ls-remote", "origin").splitlines())
        desired = {"refs/heads/main": self.git("rev-parse", "HEAD"), f"refs/tags/{tag}": self.git("rev-parse", tag)}
        missing = [ref for ref, sha in desired.items() if refs.get(ref) != sha]
        if missing:
            hook = self.remote / "hooks/update"
            if hook.exists(): hook.unlink()
            self.git("push", "--atomic", "origin", *[f"{desired[ref]}:{ref}" for ref in missing])
        lookup = self.command(["gh", "release", "view", tag, "--repo", "example/xlsx_composer"])
        if lookup.returncode:
            self.command(["gh", "release", "create", tag, "--repo", "example/xlsx_composer",
                          "--verify-tag", "--generate-notes", "--title", tag], check=True)
        # Publication recovery takes place in a separate clean checkout of the exact tag.
        checkout = self.root / "recovery"
        if not checkout.exists():
            self.command([self.env["REAL_GIT"], "clone", "--branch", tag, str(self.remote), str(checkout)], check=True)
        case.assertEqual(self.command([self.env["REAL_GIT"], "status", "--porcelain"], cwd=checkout, check=True).stdout, "")
        metadata = self.observe_hex(version)
        if metadata is None:
            self.command(["mix", "hex.publish", "--yes"], cwd=checkout, check=True)
        elif not metadata["has_docs"]:
            self.command(["mix", "hex.publish", "docs", "--yes"], cwd=checkout, check=True)
        case.assertEqual(self.observe_hex(version), {"version": version, "has_docs": True})
        case.assertEqual(self.public()["github"], [tag])
        case.assertEqual(self.public()["package_uploads"], [version])
        return self.snapshot()

    def observe_hex(self, version):
        """Read the fake public record through the real anonymous HTTP helper."""
        metadata = self.public()["hex"].get(version)
        def transport(request, timeout):
            assert request.full_url == f"https://hex.pm/api/packages/xlsx_composer/releases/{version}"
            assert dict(request.header_items()) == {"Accept": "application/json", "User-agent": "xlsx_composer-release/1.0"}
            if metadata is None:
                raise HTTPError(request.full_url, 404, "absent", {}, None)
            return HexTransportTest().response(json.dumps(metadata).encode())
        with patch.object(release, "urlopen", side_effect=transport):
            return release._hex_metadata(version, 10)


class ReleaseTest(unittest.TestCase):
    def fixture(self):
        return Fixture(self)

    def assert_refusal(self, fixture, bump="SMALL", input=None, run=None):
        before = fixture.snapshot()
        events = fixture.events()
        result = run() if run else fixture.run(bump, input)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(fixture.snapshot(), before)
        new = fixture.events()[len(events):]
        self.assertFalse(any(e.get("args", [])[:1] in (["hex.publish"], ["release"]) for e in new))
        return result

    def assert_published(self, fixture, version):
        tag = "v" + version
        self.assertEqual((fixture.repo / "VERSION").read_text(), version + "\n")
        readme = (fixture.repo / "README.md").read_text()
        self.assertIn(f"<!-- release-version: {version} -->", readme)
        self.assertIn(f'{{:xlsx_composer, "~> {version}"}}', readme)
        self.assertEqual(fixture.git("status", "--porcelain"), "")
        self.assertEqual(fixture.git("cat-file", "-t", tag), "tag")
        self.assertEqual(fixture.git("rev-parse", tag + "^{}"), fixture.git("rev-parse", "HEAD"))
        remote = dict(line.split()[::-1] for line in fixture.git("ls-remote", "origin").splitlines())
        self.assertEqual(remote["refs/heads/main"], fixture.git("rev-parse", "HEAD"))
        self.assertEqual(remote["refs/tags/" + tag], fixture.git("rev-parse", tag))
        self.assertEqual(sorted(fixture.git("show", "--name-only", "--format=", "HEAD").splitlines()), FILES)
        self.assertEqual(fixture.git("log", "-1", "--format=%s"), "chore: release " + tag)
        self.assertEqual(fixture.public()["hex"][version], {"version": version, "has_docs": True})
        self.assertIn(tag, fixture.public()["github"])

    def test_sequential_bumps_aliases_and_utc_stamp(self):
        for bumps in (("small", "MINOR", "MAJOR"), ("s", "mi", "Ma")):
            f = self.fixture()
            previous = []
            for index, (bump, expected) in enumerate(zip(bumps, ("0.4.1", "0.5.0", "1.0.0"))):
                with self.subTest(bump=bump):
                    if index:
                        path = f.repo / "CHANGELOG.md"
                        path.write_text(path.read_text().replace("# Changelog\n", "# Changelog\n\n## 9.9.9 (unreleased)\n", 1))
                        f.sync()
                    count = int(f.git("rev-list", "--count", "HEAD"))
                    result = f.run(bump)
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assert_published(f, expected)
                    self.assertEqual(int(f.git("rev-list", "--count", "HEAD")), count + 1)
                    previous.insert(0, f"## {expected} (2026-11-12)")
                    headings = [line for line in (f.repo / "CHANGELOG.md").read_text().splitlines() if line.startswith("## ")]
                    self.assertEqual(headings, previous + ["## 0.3.9 (unreleased)"])
                    # A naive datetime.now() stamps 2026-11-11 in the frozen boundary.
                    self.assertNotIn("(2026-11-11)", headings[0])
            events = f.events()
            mixes = [(e["args"], e["mix_env"]) for e in events if e["tool"] == "mix"]
            self.assertEqual(mixes[:7], [(["deps.unlock", "--check-unused"], "dev"),
                (["compile", "--force", "--warnings-as-errors"], "dev"),
                (["compile", "--force", "--warnings-as-errors"], "test"), (["quality"], "dev"),
                (["test"], "test"), (["docs", "--warnings-as-errors"], "dev"), (["hex.publish", "--yes"], "dev")])
            self.assertTrue(any(e["tool"] == "package-check" for e in events))
            creates = [e for e in events if e["tool"] == "gh" and e["args"][:2] == ["release", "create"]]
            self.assertEqual(creates[0]["args"], ["release", "create", "v0.4.1", "--repo", "example/xlsx_composer",
                                                "--verify-tag", "--generate-notes", "--title", "v0.4.1"])
            self.assertFalse(any("whoami" in str(e) for e in events))

    def test_interactive_levels_and_aliases(self):
        for answer, expected in (("s", "0.4.1"), (" SMALL ", "0.4.1"), ("mi", "0.5.0"),
                                 ("minor", "0.5.0"), ("ma", "1.0.0"), ("major", "1.0.0")):
            with self.subTest(answer=answer):
                f = self.fixture()
                result = f.run(None, answer + "\n")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("Version upgrade", result.stdout)
                self.assert_published(f, expected)

    def test_invalid_input_is_transported_literally_without_make_or_shell_evaluation(self):
        f = self.fixture()
        sentinel = f.root / "sentinel"
        for value in ("", "M", "PATCH", "'", '"', f"S; touch {sentinel}",
                      f"$(shell touch {sentinel})", f"$(file >{sentinel},oops)", f"`touch {sentinel}`", "${HOME}"):
            with self.subTest(value=value):
                result = self.assert_refusal(f, value)
                self.assertIn("Choose MAJOR", result.stderr)
                self.assertEqual(f.events()[-1], {"tool": "launcher", "bump": value, "original_bump": None})
                self.assertFalse(sentinel.exists())
        for answer in ("garbage\n", "\n", "", "'\n", "$(shell x)\n"):
            self.assert_refusal(f, None, answer)

    def test_unsafe_git_states(self):
        for state in ("dirty", "staged", "untracked", "detached", "branch", "stale", "push-urls", "local-tag", "remote-tag"):
            with self.subTest(state=state):
                f = self.fixture()
                if state == "dirty": (f.repo / "README.md").write_text("edit")
                elif state in ("staged", "untracked"):
                    (f.repo / "user-work").write_text("edit")
                    if state == "staged": f.git("add", "user-work")
                elif state == "detached": f.git("checkout", "--detach")
                elif state == "branch": f.git("checkout", "-b", "feature")
                elif state == "stale": f.git("commit", "--allow-empty", "-m", "Unpushed")
                elif state == "push-urls":
                    f.git("config", "--add", "remote.origin.pushurl", str(f.remote))
                    f.git("config", "--add", "remote.origin.pushurl", str(f.remote))
                elif state == "local-tag": f.git("tag", "v0.4.1")
                elif state == "remote-tag": f.git("push", "origin", "HEAD:refs/tags/v0.4.1")
                self.assert_refusal(f)

    def test_malformed_release_documents(self):
        for version in ("01.2.3\n", "1.2\n", "1.2.3-rc1\n", "1.2.3\nother", " 1.2.3\n", "-1.0.0\n"):
            f = self.fixture()
            (f.repo / "VERSION").write_text(version)
            f.sync()
            self.assertIn("VERSION must contain", self.assert_refusal(f).stderr)
        for kind in ("missing-marker", "duplicate-marker", "wrong-marker", "missing-install", "duplicate-install", "wrong-install",
                     "dated", "trailing-space", "no-top", "bad-semver"):
            with self.subTest(kind=kind):
                f = self.fixture()
                path = f.repo / ("README.md" if "marker" in kind or "install" in kind else "CHANGELOG.md")
                value = path.read_text()
                if kind == "missing-marker": value = value.replace("<!-- release-version: 0.4.0 -->", "")
                elif kind == "duplicate-marker": value += "<!-- release-version: 0.4.0 -->\n"
                elif kind == "wrong-marker": value = value.replace("release-version: 0.4.0", "release-version: 0.3.0")
                elif kind == "missing-install": value = value.splitlines()[0] + "\n"
                elif kind == "duplicate-install": value += '{:xlsx_composer, "~> 0.4.0"}\n'
                elif kind == "wrong-install": value = value.replace('"~> 0.4.0"', '"~> 0.3.0"')
                else:
                    heading = {"dated": "## 0.4.1 (2026-11-11)", "trailing-space": "## 0.4.1 (unreleased) ",
                               "no-top": "## Unreleased", "bad-semver": "## 01.2.3 (unreleased)"}[kind]
                    value = value.replace("## 0.4.1 (unreleased)", heading, 1)
                path.write_text(value)
                f.sync()
                self.assertIn("synchronize release documentation", self.assert_refusal(f).stderr)

    def test_existing_hex_unknown_http_and_missing_ci_key(self):
        for state in ("existing", "timeout", "malformed", "wrong-version", "server-error", "ci-missing", "ci-empty", "ci-blank"):
            with self.subTest(state=state):
                f = self.fixture()
                if state == "existing":
                    public = f.public()
                    public["hex"]["0.4.1"] = {"version": "0.4.1", "has_docs": False}
                    f.state.write_text(json.dumps(public))
                elif state.startswith("ci-"):
                    f.env["GITHUB_ACTIONS"] = "true"
                    if state != "ci-missing": f.env["HEX_API_KEY"] = "" if state == "ci-empty" else "  \t"
                else: f.env["HTTP_MODE"] = state
                result = self.assert_refusal(f)
                self.assertFalse(any(e["tool"] == "mix" for e in f.events()))
                self.assertIn("0.4.1", result.stderr)
        f = self.fixture()
        f.env.update(GITHUB_ACTIONS="true", HEX_API_KEY="fixture-private-key", GH_TOKEN="fixture-private-token")
        result = f.run()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("fixture-private", result.stdout + result.stderr + f.log.read_text())

    def test_release_workflow_step_invokes_the_same_make_release(self):
        names, command = release_step()
        self.assertEqual(command, 'make release bump="$LEVEL"')
        self.assertEqual(sorted(names), ["GH_TOKEN", "HEX_API_KEY", "LEVEL"])
        secrets = dict(GH_TOKEN="fixture-private-token", HEX_API_KEY="fixture-private-key")
        f = self.fixture()
        result = f.dispatch(**secrets)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assert_published(f, "0.4.1")
        self.assertEqual(f.public()["package_uploads"], ["0.4.1"])
        self.assertNotIn("fixture-private", result.stdout + result.stderr + f.log.read_text())
        for key in ("", " \t"):
            with self.subTest(key=key):
                f = self.fixture()
                self.assert_refusal(f, run=lambda: f.dispatch(GH_TOKEN="fixture", HEX_API_KEY=key))
        f = self.fixture()
        self.assert_refusal(f, run=lambda: f.dispatch(GH_TOKEN="fixture"))

    def test_rerun_of_original_event_after_remote_advances_is_refused(self):
        f = self.fixture()
        other = f.root / "other"
        f.command([f.env["REAL_GIT"], "clone", "--branch", "main", str(f.remote), str(other)], check=True)
        for args in (("commit", "--allow-empty", "-m", "Later main"), ("push", "origin", "main")):
            f.command([f.env["REAL_GIT"], "-c", "user.name=Other", "-c", "user.email=o@example.test", *args],
                      cwd=other, check=True)
        result = self.assert_refusal(f, run=lambda: f.dispatch(GH_TOKEN="fixture", HEX_API_KEY="fixture"))
        self.assertIn("must match the origin push destination", result.stderr)
        self.assertEqual(f.git("rev-parse", "HEAD"), f.start)

    def test_each_validation_gate_failure_preserves_state(self):
        for command in ("gh repo view", "mix deps.unlock --check-unused", "mix compile --force --warnings-as-errors:dev",
                        "mix compile --force --warnings-as-errors:test", "mix quality", "mix test",
                        "mix docs --warnings-as-errors", "package-check "):
            with self.subTest(command=command):
                f = self.fixture()
                if command == "gh repo view":
                    f.env["FAIL_COMMAND"] = f"gh repo view {f.remote} --json nameWithOwner --jq .nameWithOwner"
                else: f.env["FAIL_COMMAND"] = command
                self.assert_refusal(f)

    def test_checkout_changes_during_validation_including_branch_at_same_head(self):
        for mutation in ("branch", "head", "untracked"):
            f = self.fixture()
            f.env["MUTATE_CHECK"] = mutation
            before_remote = f.git("ls-remote", "origin")
            result = f.run()
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("checkout changed during validation", result.stderr)
            self.assertEqual(f.git("ls-remote", "origin"), before_remote)
            self.assertEqual((f.repo / "VERSION").read_text(), "0.4.0\n")
            self.assertEqual(f.git("tag", "--list"), "")
            self.assertEqual(f.public()["github"], [])
            if mutation == "branch": self.assertEqual(f.git("rev-parse", "HEAD"), f.start)

    def test_failure_boundaries_retry_refusal_and_state_derived_recovery(self):
        for boundary in ("files", "index", "commit", "tag", "push-rejection", "push-response", "github", "github-ambiguous",
                         "hex", "hex-ambiguous", "docs", "metadata-timeout", "complete"):
            with self.subTest(boundary=boundary):
                f = self.fixture()
                if boundary == "files": f.env["INTERRUPT_WRITE"] = "1"
                elif boundary in ("index", "tag"): f.git_fault(boundary)
                elif boundary == "commit": f.executable(f.repo / ".git/hooks/pre-commit", "raise SystemExit(1)\n")
                elif boundary == "push-rejection":
                    hook = f.remote / "hooks/update"
                    hook.write_text('#!/bin/sh\ncase "$1" in refs/tags/*) exit 1;; esac\n')
                    hook.chmod(0o755)
                elif boundary == "push-response": f.git_fault("push-response")
                elif boundary in ("github", "github-ambiguous"):
                    if boundary == "github": f.env["FAIL_COMMAND"] = "gh release create v0.4.1 --repo example/xlsx_composer --verify-tag --generate-notes --title v0.4.1"
                    else: f.env["GH_AMBIGUOUS"] = "1"
                elif boundary in ("hex", "hex-ambiguous"):
                    f.env["FAIL_COMMAND"] = "mix hex.publish --yes"
                    if boundary == "hex-ambiguous": f.env["HEX_AMBIGUOUS"] = "1"
                elif boundary == "docs": f.env["NO_DOCS"] = "1"
                elif boundary == "metadata-timeout": f.env["HTTP_MODE"] = "after-publish-timeout"
                result = f.run()
                self.assertEqual(result.returncode == 0, boundary == "complete", result.stdout + result.stderr)
                state = f.snapshot()
                remote = dict(line.split()[::-1] for line in state["remote"].splitlines())
                early = boundary in ("files", "index", "commit")
                if early:
                    self.assertEqual(state["head"], f.start)
                    self.assertEqual(f.git("tag", "--list"), "")
                    self.assertEqual(state["public"]["github"], [])
                    self.assertEqual((f.repo / "VERSION").read_text(), "0.4.1\n")
                    if boundary == "files":
                        self.assertIn("0.4.0", (f.repo / "README.md").read_text())
                        self.assertEqual(state["index"], "")
                    else:
                        staged = f.git("diff", "--cached", "--name-only").splitlines()
                        self.assertEqual(staged, ["VERSION"] if boundary == "index" else FILES)
                else:
                    self.assertEqual(int(state["count"]), 2)
                    self.assertEqual(state["status"], "")
                    if boundary == "tag": self.assertEqual(f.git("tag", "--list"), "")
                    else: self.assertEqual(f.git("cat-file", "-t", "v0.4.1"), "tag")
                if early or boundary in ("tag", "push-rejection"):
                    self.assertEqual(remote["refs/heads/main"], f.start)
                    self.assertNotIn("refs/tags/v0.4.1", remote)
                    self.assertEqual(state["public"]["github"], [])
                else:
                    self.assertEqual(remote["refs/heads/main"], state["head"])
                    self.assertEqual(remote["refs/tags/v0.4.1"], f.git("rev-parse", "v0.4.1"))
                if boundary != "complete":
                    self.assertIn("last known stage:", result.stderr)
                    for text in ("repository example/xlsx_composer", "tag v0.4.1", "git ls-remote", "v0.4.1^{}",
                                 "gh release view v0.4.1 --repo example/xlsx_composer", "mix hex.info xlsx_composer 0.4.1",
                                 "mix hex.publish docs --yes", "Unknown state"):
                        self.assertIn(text, result.stderr)
                if boundary == "docs": self.assertIn("completion unverified", result.stderr)
                if boundary == "push-response": self.assertIn("push response unknown", result.stderr)
                if boundary in ("hex-ambiguous", "metadata-timeout", "docs", "complete"):
                    self.assertEqual(state["public"]["package_uploads"], ["0.4.1"])
                # A new bump cannot resume any leftover, even after clearing injected faults.
                for key in ("INTERRUPT_WRITE", "GIT_FAULT", "FAIL_COMMAND", "NO_DOCS", "HTTP_MODE", "GH_AMBIGUOUS", "HEX_AMBIGUOUS"):
                    f.env.pop(key, None)
                before_retry_events = len(f.events())
                self.assert_refusal(f)
                self.assertFalse(any(e["tool"] in ("mix", "gh", "http") for e in f.events()[before_retry_events:]))
                final = f.repair_missing_stages(self)
                self.assertEqual(final["count"], "2")
                self.assert_published(f, "0.4.1")
                self.assertEqual(f.public()["docs_uploads"], ["0.4.1"] if boundary == "docs" else [])
                # Re-observe a completed recovery: no duplicate commit, tag or upload.
                self.assertEqual(f.repair_missing_stages(self), final)


class HexTransportTest(unittest.TestCase):
    def response(self, data=b'{"version":"0.4.1","has_docs":true}', status=200, read=None):
        class Response:
            def __enter__(self): return self
            def __exit__(self, *args): pass
        result = Response()
        result.status = status
        result.read = read or (lambda: data)
        return result

    def test_anonymous_https_shape_and_definite_absence(self):
        def transport(request, timeout):
            self.assertEqual(request.full_url, "https://hex.pm/api/packages/xlsx_composer/releases/0.4.1")
            self.assertEqual(dict(request.header_items()), {"Accept": "application/json", "User-agent": "xlsx_composer-release/1.0"})
            self.assertEqual(timeout, 7)
            return self.response()
        with patch.object(release, "urlopen", side_effect=transport):
            self.assertEqual(release._hex_metadata("0.4.1", 7), {"version": "0.4.1", "has_docs": True})
        with patch.object(release, "urlopen", side_effect=HTTPError("https://hex.pm", 404, "absent", {}, None)):
            self.assertIsNone(release._hex_metadata("0.4.1", 10))

    def test_invalid_and_unknown_metadata_is_never_absence(self):
        responses = [self.response(b"no"), self.response(b"[]"), self.response(b'{}'), self.response(status=503),
                     self.response(b'{"version":"0.4.0","has_docs":true}'),
                     self.response(b'{"version":"0.4.1","has_docs":"true"}')]
        for response in responses:
            with patch.object(release, "urlopen", return_value=response), self.assertRaises(ValueError):
                release._hex_metadata("0.4.1", 10)
        for error in (TimeoutError("secret-proxy"), URLError("secret-proxy"), IncompleteRead(b"secret-proxy"),
                      HTTPError("https://hex.pm", 503, "bad", {}, None)):
            with patch.object(release, "urlopen", side_effect=error), self.assertRaises(ValueError) as result:
                release._hex_metadata("0.4.1", 10)
            self.assertNotIn("secret-proxy", str(result.exception))

    def test_polling_pending_unknown_and_then_public_docs(self):
        clock = [0.0]
        sleeps = []
        def sleep(seconds):
            sleeps.append(seconds)
            clock[0] += seconds
        values = [HTTPError("https://hex.pm", 404, "absent", {}, None), URLError("timeout"),
                  self.response(b"bad"), self.response(b'{"version":"0.4.0","has_docs":true}'),
                  self.response(b'{"version":"0.4.1","has_docs":false}'), self.response()]
        with patch.object(release, "time", SimpleNamespace(monotonic=lambda: clock[0], sleep=sleep)), \
             patch.object(release, "urlopen", side_effect=values) as transport:
            release._verify_hex("0.4.1")
        self.assertEqual(sleeps, [2] * 5)
        self.assertEqual(transport.call_count, 6)

    def test_deadline_clips_socket_and_sleep_and_rejects_late_body(self):
        for late_success in (False, True):
            clock, timeouts, sleeps = [0.0], [], []
            def sleep(seconds):
                self.assertGreater(seconds, 0)
                self.assertLessEqual(seconds, 60 - clock[0])
                sleeps.append(seconds)
                clock[0] += seconds
            def transport(request, timeout):
                timeouts.append(timeout)
                self.assertLessEqual(timeout, min(10, 60 - clock[0]))
                def body():
                    # First response consumes 57s; last arrives past the deadline.
                    clock[0] += 57 if len(timeouts) == 1 else 2
                    docs = late_success and len(timeouts) == 2
                    return json.dumps({"version": "0.4.1", "has_docs": docs}).encode()
                return self.response(read=body)
            with patch.object(release, "time", SimpleNamespace(monotonic=lambda: clock[0], sleep=sleep)), \
                 patch.object(release, "urlopen", side_effect=transport), self.assertRaisesRegex(ValueError, "completion unverified"):
                release._verify_hex("0.4.1")
            self.assertEqual(timeouts, [10, 1])
            self.assertEqual(sleeps, [2])
            self.assertEqual(clock[0], 61)

    def test_last_sleep_clipped_and_no_request_after_budget(self):
        clock, sleeps, requests = [0.0], [], []
        def transport(request, timeout):
            requests.append(timeout)
            clock[0] += 59.75
            return self.response(b'{"version":"0.4.1","has_docs":false}')
        def sleep(seconds):
            sleeps.append(seconds)
            clock[0] += seconds
        with patch.object(release, "time", SimpleNamespace(monotonic=lambda: clock[0], sleep=sleep)), \
             patch.object(release, "urlopen", side_effect=transport), self.assertRaises(ValueError):
            release._verify_hex("0.4.1")
        self.assertEqual(requests, [10])
        self.assertEqual(sleeps, [0.25])


if __name__ == "__main__":
    unittest.main()
