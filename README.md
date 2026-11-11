# XLSXComposer
A declarative wrapper around `elixlsx` that focuses on readability and performance (`elixlsx` slows down when a sheet is built with many `set_cell` calls).

## Installation

<!-- release-version: 0.4.0 -->

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `xlsx_composer` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:xlsx_composer, "~> 0.4.0"}
  ]
end
```

## Documentation

The guides are on [HexDocs](https://hexdocs.pm/xlsx_composer): Overview,
Components, a tested Example and Why XLSXComposer vs Elixlsx. Run `mix docs` to
build them locally.

## Development

The development toolchain is pinned in `.tool-versions` to Elixir 1.20.2 and
Erlang/OTP 28.5. CI and the Release workflow read the same file through
`.github/actions/setup-beam`. These development and CI pins do not change the
library's declared Elixir requirement of `~> 1.18` or establish compatibility
with that minimum version.

CI runs on pushes to `main` and pull requests targeting it: release tests, unused
dependencies, warning-fatal dev/test compilation, `make quality`, warning-fatal
docs, the package check and `mix test`. Its `mix hex.outdated` report is advisory
and goes to the job summary. A newer push cancels a superseded pull request run,
never a `main` run.

Run `make help` for maintainer commands and `make quality` for warning-fatal
compilation, formatting, Credo and Dialyzer. Run `mix test` for the public tests,
`mix docs --warnings-as-errors` for documentation, and `scripts/package_check.sh`
to build the Hex artifact and compile it in a fresh host outside this checkout.
The package check requires Hex/Rebar and network access for declared dependencies.
`VERSION` is the package version source; the installation example and changelog
track releases.

## Releasing

Both release targets are self-contained bash in the `Makefile`. Run
`make release-test` to test the release command with isolated Git repositories
and fake publishers (it needs bash, Git, Make and `jq`). It does not need
credentials or publish anything publicly.

For a real release, use the pinned development toolchain, bash, Git, Make, `curl`, `jq`,
GitHub CLI (`gh`), Hex/Rebar and installed dependencies, including ExDoc. Start
from clean, attached `main`, synchronized with the single origin push destination.
Configure Git commit identity, Git push access and `gh` authentication with access
to create releases in that destination repository. Branch protection may require
additional permissions; the command does not bypass it. For Hex, use existing
local authenticated credentials or `HEX_API_KEY` with package-scoped write access
to `xlsx_composer`. In GitHub Actions a nonblank `HEX_API_KEY` is required.
Credential presence does not prove publish rights; no account settings are changed.

Prepare and commit a top changelog heading such as `## 0.4.1 (unreleased)` with
truthful release notes. `VERSION`, the README release marker and installation
snippet must agree. Then run:

```sh
make release bump=SMALL
```

`SMALL`/`S` increments patch, `MINOR`/`MI` resets patch and increments minor, and
`MAJOR`/`MA` resets minor/patch and increments major (case-insensitive). Omit `bump`
to choose interactively. An explicitly empty or invalid value is rejected.

The command checks clean synchronized main, documentation, tags and public Hex
version absence before mutation. It runs unused-dependency checks, separate
warning-fatal dev/test compilation, quality, tests, warning-fatal docs and the
fresh-host package check. It rechecks the checkout, updates only VERSION/README/
CHANGELOG, stamps only the first changelog heading with the chosen version and UTC
date, creates one release commit and annotated tag, and pushes main plus tag
atomically. It then creates the GitHub Release with generated notes and runs
`mix hex.publish --yes` with ExDoc available. Success additionally requires public
Hex metadata for the exact version with `has_docs=true`.

Public verification polls for up to 60 seconds; each request is cut off after at
most 10 seconds or the remaining budget. A timeout, staged approval policy or network failure can
leave an upload present while completion is unverified. A nonzero Hex command
also remains a failure even if an upload landed.

The consumed changelog entry prevents an unprepared second invocation from
creating another release. For a later intentional release, prepare and commit a
new top unreleased entry first.

### Releasing from GitHub Actions

The manual **Release** workflow (`.github/workflows/release.yml`) takes a
`SMALL`/`MINOR`/`MAJOR` level (default `SMALL`) and runs the same
`make release bump="$LEVEL"` after `make release-test`; every other gate runs
inside `make release`. Pushes made with `GITHUB_TOKEN` start no CI run, so the
release validates itself. It refuses before any mutation unless dispatched from
`main` with a nonblank `HEX_API_KEY` repository secret holding a key with
package-scoped write access to `xlsx_composer`. The job has `contents: write` to
push the release commit and tag and create the GitHub Release with `GITHUB_TOKEN`;
branch protection on `main` was not inspected and may reject that push. Releases
are serialized per repository and a running one is never cancelled. If staged
approval is configured remotely, publication may stay pending or incomplete.

A rerun checks out its original event commit, never today's `main`. Before the
push, rerun the same run only if `main` has not advanced; otherwise the command
refuses. After the push, do not rerun or dispatch a new version: finish the exact
existing tag as below.

### Finishing a partial release

Preserve the failed command's state and use its printed version, tag, repository
and last known stage. Do not rerun a bump or dispatch another version to repair
this one. Inspect the release-file working diff and index (`git status --short`,
`git diff -- VERSION README.md CHANGELOG.md`, and the corresponding
`git diff --cached`), `git show HEAD`, the annotated tag type and peeled commit
(`git cat-file -t vX.Y.Z`, `git rev-parse 'vX.Y.Z^{}'`), both remote refs
(`git ls-remote <push-destination> refs/heads/main refs/tags/vX.Y.Z 'refs/tags/vX.Y.Z^{}'`),
`gh release view vX.Y.Z --repo owner/repository`, and
`mix hex.info xlsx_composer X.Y.Z`. Also inspect anonymous JSON at
`https://hex.pm/api/packages/xlsx_composer/releases/X.Y.Z`: verify the exact version
and boolean `has_docs`. A 404 is definite absence at observation time; transport,
server or malformed responses leave the state unknown.

Apply only the known missing operation, after comparing the observed state with
the intended release. Partial writes can leave mixed documents; complete or
restore only this operation's known edits. Commit failure retains the index;
tag failure retains the release commit. Verify its contents before completing a
missing commit/tag. A rejected atomic push changes neither remote ref, retaining
the local commit/tag; an interrupted push response is unknown until **both** refs
are inspected. Push matching missing refs only, atomically when both are absent;
preserve conflicting or ambiguous state for manual reconciliation.

Once the remote commit and tag are confirmed, finish a definitely missing GitHub
Release first:

```sh
gh release create vX.Y.Z --repo owner/repository --verify-tag --generate-notes --title vX.Y.Z
```

Then use a separate clean checkout of that exact existing tag with its dependencies
and ExDoc installed. If the Hex package is definitely absent, publish that same
version with `mix hex.publish --yes`. If it exists with docs absent, run only
`mix hex.publish docs --yes`. Recheck the public JSON for matching version and
`has_docs=true` afterward. GitHub or Hex may have completed despite a network
error; unknown state never justifies blind retry, replacement or rollback. Remote
staged publication, if configured, can require external approval. This command
does not provide automatic crash recovery or undo public release history.

