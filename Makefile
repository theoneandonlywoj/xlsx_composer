.DEFAULT_GOAL := help
.PHONY: help quality release release-test

# Directory of this Makefile; release and release-test run from it.
ROOT := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

# Preserve command-line input literally, including Make/shell syntax.
ifneq ($(origin bump),undefined)
export RELEASE_BUMP := $(value bump)
endif
unexport bump

help:
	@printf '%s\n' \
		'Available targets:' \
		'  help          Show maintainer commands' \
		'  quality       Run compilation, formatting, Credo and Dialyzer (mix quality)' \
		'  release       Validate and publish GitHub + Hex (bump=SMALL/MINOR/MAJOR; omit to prompt)' \
		'  release-test  Test releases in isolated Git repos with fake publishers'

quality:
	mix quality

# The bash programs below are stored verbatim ($(value ...)), so Make never
# expands their $ signs. Make 3.81 turns a backslash-newline into one space, so
# they continue lines only where a space means the same (never in comments).
release: export RELEASE_SH = $(value release_sh)
release:
	@bash -c "$$RELEASE_SH" release "$(ROOT)"

release-test: export RELEASE_TEST_SH = $(value release_test_sh)
release-test:
	@bash -c "$$RELEASE_TEST_SH" release-test "$(ROOT)"

# ---------------------------------------------------------------------------
# make release: publish one new xlsx_composer version from clean, synchronized
# main. Needs bash 3.2+, git, mix, gh, curl and jq.
# ---------------------------------------------------------------------------
define release_sh
set -euo pipefail
unset RELEASE_SH
ROOT=$1

VERSION_RE='(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)'
SHELL_SAFE='^[A-Za-z0-9@%+=:,./_-]+$'
HEX_URL='https://hex.pm/api/packages/xlsx_composer/releases'
RELEASE_FILES=(VERSION README.md CHANGELOG.md)
stage= failure= interrupted= work= current= version= tag= repository= destination= head=

# Record why the release stopped and exit; the EXIT trap reports it.
die() {
  failure=$*
  exit 1
}

require() {
  command -v "$1" >/dev/null 2>&1 || die "Required tool unavailable: $1."
}

# Shell-quote one argument so the printed command can be pasted back.
quote() {
  local sq="'\\''"
  if [[ $1 =~ $SHELL_SAFE ]]; then printf '%s' "$1"; else printf "'%s'" "${1//\'/$sq}"; fi
}

show() {
  local out= arg
  for arg in "$@"; do out+="${out:+ }$(quote "$arg")"; done
  printf '%s\n' "$out" >&2
}

# slurp VAR FILE: read FILE exactly, trailing newlines included, into VAR.
slurp() {
  local __slurp
  __slurp=$(cat -- "$2" && printf x) || die "Cannot read $2."
  printf -v "$1" '%s' "${__slurp%x}"
}

# occurrences TEXT NEEDLE: count literal, non-overlapping NEEDLE occurrences.
occurrences() {
  local rest=$1 count=0
  while [[ $rest == *"$2"* ]]; do
    rest=${rest#*"$2"}
    count=$((count + 1))
  done
  printf '%s' "$count"
}

# replace_once TEXT OLD NEW: print TEXT with its first literal OLD replaced.
replace_once() {
  printf '%s%s%s' "${1%%"$2"*}" "$3" "${1#*"$2"}"
}

# bump_level VALUE: set $level from a case-insensitive, space-trimmed alias.
bump_level() {
  local value=$1
  value=${value#"${value%%[![:space:]]*}"}
  value=${value%"${value##*[![:space:]]}"}
  value=$(printf '%s' "$value" | tr '[:lower:]' '[:upper:]')
  case $value in
    MAJOR | MA) level=MAJOR ;;
    MINOR | MI) level=MINOR ;;
    SMALL | S) level=SMALL ;;
    *) die "Choose MAJOR (MA), MINOR (MI), or SMALL (S, patch)." ;;
  esac
}

# hex_metadata VERSION TIMEOUT: anonymous public metadata into $hex_docs
# (absent, true or false). Returns 1 with $hex_error when the state is unknown;
# only a definite HTTP 404 means absent. curl's own errors are discarded because
# they might contain proxy credentials, and ~/.curlrc is ignored (-q).
hex_metadata() {
  local code docs body="$work/hex.json"
  hex_error=
  rm -f -- "$body"
  if ! code=$(curl -q --silent --proto '=https' --max-time "$2" \
      --header 'Accept: application/json' --user-agent 'xlsx_composer-release/1.0' \
      --output "$body" --write-out '%{http_code}' "$HEX_URL/$1" 2>/dev/null); then
    hex_error="Hex state unknown (transport); inspect before retrying."
    return 1
  fi
  case $code in
    404) hex_docs=absent; return 0 ;;
    200) ;;
    *) hex_error="Hex state unknown (HTTP $code); inspect before retrying."; return 1 ;;
  esac
  if docs=$(jq -r --arg v "$1" 'if type == "object" and .version == $v and (.has_docs | type) == "boolean"
      then .has_docs else error("invalid") end' "$body" 2>/dev/null) && [[ $docs == true || $docs == false ]]; then
    hex_docs=$docs
    return 0
  fi
  hex_error="Hex state unknown (invalid or wrong-version metadata); inspect before retrying."
  return 1
}

# Poll public metadata for up to 60 seconds. Each request is cut off after at
# most 10 seconds or the remaining budget; the budget is rechecked after every
# response, so a late success is not accepted.
verify_hex() {
  local deadline remaining
  deadline=$(($(date +%s) + 60))
  while :; do
    remaining=$((deadline - $(date +%s)))
    if ((remaining <= 0)); then break; fi
    hex_metadata "$version" $((remaining < 10 ? remaining : 10)) || hex_docs=unknown
    remaining=$((deadline - $(date +%s)))
    if ((remaining <= 0)); then break; fi
    if [[ $hex_docs == true ]]; then return 0; fi
    sleep $((remaining < 2 ? remaining : 2))
  done
  die "Hex completion unverified for $version: expected version and has_docs=true within 60s."
}

# Compute the new VERSION, README and CHANGELOG texts; touch nothing yet.
prepare_documents() {
  local readme changelog marker dependency markers before rest heading heading_re stamp
  local sync="synchronize release documentation first."
  slurp readme README.md
  marker="<!-- release-version: $current -->"
  dependency="{:xlsx_composer, \"~> $current\"}"
  markers=$({ grep -oE '<!--[[:space:]]*release-version' README.md || true; } | wc -l)
  if ((markers != 1)) || [[ $(occurrences "$readme" "$marker") != 1 ||
      $(occurrences "$readme" "{:xlsx_composer,") != 1 || $(occurrences "$readme" "$dependency") != 1 ]]; then
    die "Expected exactly one matching README marker and install snippet; $sync"
  fi
  readme=$(replace_once "$readme" "$marker" "<!-- release-version: $version -->"; printf x)
  new_readme=$(replace_once "${readme%x}" "$dependency" "{:xlsx_composer, \"~> $version\"}"; printf x)
  new_readme=${new_readme%x}

  slurp changelog CHANGELOG.md
  heading_re="^## $VERSION_RE \\(unreleased\\)\$"
  if [[ $changelog == "## "* ]]; then
    before=
  elif [[ $changelog == *$'\n## '* ]]; then
    before=${changelog%%$'\n## '*}$'\n'
  else
    die "First CHANGELOG heading must be '## X.Y.Z (unreleased)'; $sync"
  fi
  rest=${changelog:${#before}}
  heading=${rest%%$'\n'*}
  [[ $heading =~ $heading_re ]] || die "First CHANGELOG heading must be '## X.Y.Z (unreleased)'; $sync"
  stamp=$(date -u +%Y-%m-%d)
  new_changelog="$before## $version ($stamp)${rest:${#heading}}"
  new_version="$version"$'\n'
}

# Everything that can refuse before any release mutation.
preflight() {
  local raw major minor patch bump=$1 status branch tags destinations refs answer
  local version_file_re="^$VERSION_RE"$'\n'"?\$"
  cd "$ROOT"
  for tool in git mix gh curl jq; do require "$tool"; done
  status=$(git status --porcelain --untracked-files=all) || die "Cannot read git status."
  [[ -z $status ]] || die "Commit or stash all changes, including untracked files, before releasing."
  branch=$(git branch --show-current) || die "Cannot read the current branch."
  [[ $branch == main ]] || die "Run releases from attached main."
  head=$(git rev-parse HEAD)

  slurp raw VERSION
  [[ $raw =~ $version_file_re ]] || die "VERSION must contain MAJOR.MINOR.PATCH without leading zeroes."
  current=${raw%$'\n'}
  IFS=. read -r major minor patch <<<"$current"
  local -a levels=(MAJOR MINOR SMALL)
  local -a targets=("$((major + 1)).0.0" "$major.$((minor + 1)).0" "$major.$minor.$((patch + 1))")
  if [[ -z $bump ]]; then
    printf 'Current version: %s\n' "$current"
    for i in 0 1 2; do printf '  %s: %s\n' "${levels[i]}" "${targets[i]}"; done
    printf 'Version upgrade [MAJOR/MINOR/SMALL or MA/MI/S]: '
    IFS= read -r answer || [[ -n $answer ]] || die "No version upgrade chosen."
    bump_level "$answer"
    bump=$level
  fi
  case $bump in MAJOR) version=${targets[0]} ;; MINOR) version=${targets[1]} ;; *) version=${targets[2]} ;; esac
  tag="v$version"
  prepare_documents

  tags=$(git tag --list "$tag")
  [[ -z $tags ]] || die "Tag $tag already exists locally."
  destinations=$(git remote get-url --push --all origin) || die "origin must have exactly one push destination."
  [[ -n $destinations && $destinations != *$'\n'* ]] || die "origin must have exactly one push destination."
  destination=$destinations
  refs=$(git ls-remote "$destination" refs/heads/main "refs/tags/$tag") || die "Cannot read origin's refs."
  [[ -z $(awk -v ref="refs/tags/$tag" '$2 == ref' <<<"$refs") ]] || die "Tag $tag already exists on origin."
  [[ $(awk '$2 == "refs/heads/main" {print $1}' <<<"$refs") == "$head" ]] ||
    die "Local main must match the origin push destination's main."
  repository=$(gh repo view "$destination" --json nameWithOwner --jq .nameWithOwner) ||
    die "Could not resolve the GitHub repository for origin's push destination."
  [[ $repository =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] ||
    die "Could not resolve the GitHub repository for origin's push destination."
}

# mix_gate ENV ARGS...: one validation command under MIX_ENV=ENV.
mix_gate() {
  local env=$1
  shift
  MIX_ENV=$env mix "$@" || die "Validation failed: MIX_ENV=$env mix $*."
}

validate() {
  local branch now status key
  if [[ ${GITHUB_ACTIONS:-} == true ]]; then
    key=${HEX_API_KEY:-}
    [[ -n ${key//[[:space:]]/} ]] || die "GITHUB_ACTIONS requires a nonblank HEX_API_KEY before release mutation."
  fi
  hex_metadata "$version" 10 || die "$hex_error"
  [[ $hex_docs == absent ]] || die "Hex target $version already exists; inspect the existing release."
  printf 'Releasing %s → %s to %s; validating before mutation.\n' "$current" "$version" "$repository"
  mix_gate dev deps.unlock --check-unused
  mix_gate dev compile --force --warnings-as-errors
  mix_gate test compile --force --warnings-as-errors
  mix_gate dev quality
  mix_gate test test
  mix_gate dev docs --warnings-as-errors
  scripts/package_check.sh || die "Validation failed: scripts/package_check.sh."
  branch=$(git branch --show-current) || branch=
  now=$(git rev-parse HEAD) || now=
  status=$(git status --porcelain --untracked-files=all) || status=unknown
  [[ $branch == main && $now == "$head" && -z $status ]] ||
    die "The checkout changed during validation; stopped before updating release files."
}

# step ARGS...: run one mutation; a failure keeps the current stage.
step() {
  "$@" || die "Command failed: $*."
}

publish() {
  stage="writing release files; partial/mixed files possible"
  printf '%s' "$new_version" >VERSION || die "Cannot write VERSION."
  printf '%s' "$new_readme" >README.md || die "Cannot write README.md."
  printf '%s' "$new_changelog" >CHANGELOG.md || die "Cannot write CHANGELOG.md."
  stage="release files written; staging may be partial"
  step git add -- "${RELEASE_FILES[@]}"
  stage="release files staged; commit not confirmed"
  step git commit -m "chore: release $tag"
  stage="release commit exists; tag not confirmed"
  step git tag -a "$tag" -m "Release $tag"
  stage="local commit and annotated tag; atomic push response unknown, inspect both remote refs"
  step git push --atomic "$destination" HEAD:refs/heads/main "refs/tags/$tag"
  stage="commit and tag pushed; GitHub creation unconfirmed"
  step gh release create "$tag" --repo "$repository" --verify-tag --generate-notes --title "$tag"
  stage="GitHub release created; Hex package/docs upload unconfirmed"
  MIX_ENV=dev mix hex.publish --yes || die "Command failed: mix hex.publish --yes."
  stage="Hex command exited zero; public package/docs completion unverified"
  verify_hex
}

recovery() {
  printf 'Release %s; tag %s; repository %s; last known stage: %s.\n' "$version" "$tag" "$repository" "$stage" >&2
  echo "Preserve this state. Inspect files/index/commit, annotated tag peel, BOTH remote refs, GitHub and Hex:" >&2
  show git status --short
  show git diff -- "${RELEASE_FILES[@]}"
  show git diff --cached -- "${RELEASE_FILES[@]}"
  show git show HEAD -- "${RELEASE_FILES[@]}"
  show git cat-file -t "$tag"
  show git rev-parse "$tag^{}"
  show git ls-remote "$destination" refs/heads/main "refs/tags/$tag" "refs/tags/$tag^{}"
  show gh release view "$tag" --repo "$repository"
  show mix hex.info xlsx_composer "$version"
  echo "Read anonymous $HEX_URL/$version; verify version and has_docs=true." >&2
  echo "Partial writes/index: inspect and complete or restore ONLY this operation's known file changes." \
    "A commit failure leaves the index; a tag failure leaves the commit. Compare the commit contents before tagging." \
    "A rejected atomic push changes neither ref; an interrupted/failed response is UNKNOWN until both refs are inspected." \
    "Push only known missing matching refs, atomically when both are missing; preserve conflicting state." >&2
  echo "If the matching release commit/tag are local only, after inspection: git tag -a $tag -m 'Release $tag'" \
    "(only if tag is absent); git push --atomic $(quote "$destination") HEAD:refs/heads/main refs/tags/$tag" >&2
  echo "Finish a definitely missing GitHub release first, after verifying remote refs:" >&2
  show gh release create "$tag" --repo "$repository" --verify-tag --generate-notes --title "$tag"
  echo "From a separate clean checkout of exact existing tag $tag, with dependencies/ExDoc installed:" \
    "if Hex package is definitely absent, mix hex.publish --yes;" \
    "if package exists and docs are absent, mix hex.publish docs --yes. Verify public metadata afterward." \
    "GitHub/Hex may have succeeded despite an error. Unknown state: inspect, never blindly republish," \
    "replace, roll back, rerun the bump, or dispatch a new version to repair this one." >&2
}

on_exit() {
  local status=$?
  trap - EXIT INT TERM
  if [[ -n $work ]]; then rm -rf -- "$work"; fi
  if ((status != 0)); then
    if [[ -n $stage ]]; then recovery; fi
    if [[ -n $interrupted ]]; then
      echo "Release interrupted; preserve and inspect current state before finishing the same version." >&2
    elif [[ -n $failure ]]; then
      printf 'Release failed: %s\n' "$failure" >&2
    else
      printf 'Release failed: a command exited with status %s.\n' "$status" >&2
    fi
  fi
  exit "$status"
}

main() {
  local bump=
  trap on_exit EXIT
  trap 'interrupted=1; exit 130' INT TERM
  if [[ -n ${RELEASE_BUMP+set} ]]; then
    bump_level "$RELEASE_BUMP"
    bump=$level
  fi
  preflight "$bump"
  work=$(mktemp -d "${TMPDIR:-/tmp}/xlsx_composer-release.XXXXXXXX")
  stage="preflight; no release mutations"
  validate
  publish
  printf 'Published %s to %s and Hex with docs (public metadata verified).\n' "$tag" "$repository"
}

main
endef

# ---------------------------------------------------------------------------
# make release-test: run make release in throwaway Git repositories (a real
# bare origin) with fake mix, gh, curl, date, sleep and package check. Needs
# bash 3.2+, git, make and jq; publishes nothing and needs no credentials.
# ---------------------------------------------------------------------------
define release_test_sh
set -uo pipefail
unset RELEASE_TEST_SH
ROOT=$1
for tool in git make jq; do
  command -v "$tool" >/dev/null 2>&1 || { echo "release-test needs $tool" >&2; exit 1; }
done
# Never inherit Git settings, credentials or Make flags from the caller.
for name in $(env | sed -n 's/^\(GIT_[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$name"; done
unset MAKEFLAGS MAKELEVEL MFLAGS GITHUB_ACTIONS HEX_API_KEY GH_TOKEN RELEASE_BUMP
REAL_GIT=$(command -v git)
SCRATCH=$(mktemp -d "${TMPDIR:-/tmp}/xlsx-release-test.XXXXXXXX")
trap 'rm -rf -- "$SCRATCH"' EXIT
OLD_README=$'<!-- release-version: 0.4.0 -->\n{:xlsx_composer, "~> 0.4.0"}\n'
OLD_CHANGELOG=$'# Changelog\n\n## 0.4.1 (unreleased)\n\n- New.\n\n## 0.3.9 (unreleased)\n\n- Old.\n'
FILES=$'CHANGELOG.md\nREADME.md\nVERSION'

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}
eq() {
  [[ $1 == "$2" ]] || fail "${3:-values differ}"$'\n'"expected: $2"$'\n'"actual:   $1"
}
contains() {
  [[ $1 == *"$2"* ]] || fail "missing text: $2"$'\n'"in: $1"
}
lacks() {
  [[ $1 != *"$2"* ]] || fail "unexpected text: $2"
}
g() {
  "$REAL_GIT" "$@"
}
# replace_first FILE OLD NEW: replace the first literal OLD in FILE.
replace_first() {
  local text
  text=$(cat -- "$1"; printf x)
  text=${text%x}
  [[ $text == *"$2"* ]] || fail "replace_first: $2 not in $1"
  printf '%s%s%s' "${text%%"$2"*}" "$3" "${text#*"$2"}" >"$1"
}

# Fake mix, gh and package check. Each logs "tool|MIX_ENV|args" and fails when
# FAIL_COMMAND equals "tool args" or "tool args:MIX_ENV".
write_fake_tool() {
  cat >"$1" <<'FAKE'
#!/bin/bash
set -uo pipefail
case ${0##*/} in package_check.sh) tool=package-check ;; *) tool=${0##*/} ;; esac
printf '%s|%s|%s\n' "$tool" "${MIX_ENV-}" "$*" >>"$FIXTURE_LOG"
command="$tool $*"
fail=
if [[ ${FAIL_COMMAND-} == "$command" || ${FAIL_COMMAND-} == "$command:${MIX_ENV-}" ]]; then fail=1; fi
has() { jq -e --arg x "$2" "$1" "$FIXTURE_STATE" >/dev/null; }
save() { local next; next=$(jq "$@" "$FIXTURE_STATE") && printf '%s\n' "$next" >"$FIXTURE_STATE"; }
case $tool in
  gh)
    case "${1-} ${2-}" in
      "repo view") [[ -z $fail ]] || exit 1; echo example/xlsx_composer ;;
      "release view") has '.github | map(. == $x) | any' "$3"; exit ;;
      "release create")
        [[ -z $fail ]] || exit 1
        has '.github | map(. == $x) | any | not' "$3" || { echo "duplicate GitHub release" >&2; exit 3; }
        save --arg t "$3" '.github += [$t]'
        [[ -z ${GH_AMBIGUOUS-} ]] || exit 1 ;;
    esac ;;
  mix)
    if [[ ${1-} == quality && -n ${MUTATE_CHECK-} ]]; then
      case $MUTATE_CHECK in
        branch) "$REAL_GIT" checkout -q -b other ;;
        head) "$REAL_GIT" commit -q --allow-empty -m "Changed during checks" ;;
        *) echo "external edit" >during-check ;;
      esac
    fi
    if [[ ${1-} == hex.publish ]]; then
      v=$(cat VERSION)
      has '.github | map(. == $x) | any' "v$v" || { echo "GitHub must precede Hex" >&2; exit 3; }
      if [[ -n $fail && -z ${HEX_AMBIGUOUS-} ]]; then exit 1; fi
      if [[ ${2-} == docs ]]; then
        has '.hex | has($x)' "$v" || exit 3
        save --arg v "$v" '.docs_uploads += [$v]'
      else
        has '.hex | has($x) | not' "$v" || exit 3
        save --arg v "$v" '.package_uploads += [$v]'
      fi
      docs=true
      [[ -z ${NO_DOCS-} ]] || docs=false
      save --arg v "$v" --argjson d "$docs" '.hex[$v] = {version: $v, has_docs: $d}'
    fi ;;
esac
[[ -z $fail ]] || exit 1
FAKE
  chmod +x "$1"
}

# Fake curl for the anonymous Hex endpoint. HTTP_MODE answers every request;
# otherwise, once the version is published, HTTP_AFTER is a comma list of
# answers used in order (the last repeats). "+N:answer" first advances the
# fake clock by N seconds, like a slow response body.
write_fake_curl() {
  cat >"$1" <<'FAKE'
#!/bin/bash
set -uo pipefail
all="$*" first=${1-} max= out= url= accept= agent=
while (($#)); do
  case $1 in
    --max-time) max=$2; shift ;;
    --output) out=$2; shift ;;
    --header) [[ $2 != 'Accept: application/json' ]] || accept=1; shift ;;
    --user-agent) agent=$2; shift ;;
    --write-out | --proto) shift ;;
    -*) ;;
    *) url=$1 ;;
  esac
  shift
done
v=${url##*/}
if [[ $first != -q || $url != "https://hex.pm/api/packages/xlsx_composer/releases/$v" || -z $accept ||
  $agent != xlsx_composer-release/1.0 || ! $max =~ ^[0-9]+$ ]] || ((max < 1 || max > 10)); then
  echo "unexpected curl request: $all" >&2
  exit 90
fi
printf 'curl|max=%s|%s\n' "$max" "$url" >>"$FIXTURE_LOG"
answer=record
if [[ -n ${HTTP_MODE-} ]]; then
  answer=$HTTP_MODE
elif [[ -n ${HTTP_AFTER-} ]] && jq -e --arg v "$v" '.hex | has($v)' "$FIXTURE_STATE" >/dev/null; then
  n=$(cat "$FIXTURE_STATE.after" 2>/dev/null || echo 0)
  echo $((n + 1)) >"$FIXTURE_STATE.after"
  IFS=, read -r -a answers <<<"$HTTP_AFTER"
  ((n < ${#answers[@]})) || n=$((${#answers[@]} - 1))
  answer=${answers[n]}
fi
if [[ $answer == +* ]]; then
  echo $(($(cat "$FIXTURE_CLOCK") + ${answer%%:*})) >"$FIXTURE_CLOCK"
  answer=${answer#*:}
fi
code=200 body=
case $answer in
  timeout) echo "curl: (28) proxy https://user:secret-proxy@proxy.test" >&2; exit 28 ;;
  404 | 503) code=$answer ;;
  bad) body='bad json' ;;
  array) body='[]' ;;
  wrong) body='{"version":"99.0.0","has_docs":true}' ;;
  string) body="{\"version\":\"$v\",\"has_docs\":\"true\"}" ;;
  true | false) body="{\"version\":\"$v\",\"has_docs\":$answer}" ;;
  record)
    if jq -e --arg v "$v" '.hex | has($v)' "$FIXTURE_STATE" >/dev/null; then
      body=$(jq -c --arg v "$v" '.hex[$v]' "$FIXTURE_STATE")
    else
      code=404
    fi ;;
esac
printf '%s' "$body" >"$out"
printf '%s' "$code"
FAKE
  chmod +x "$1"
}

# Fake clock: date +%s and sleep share one counter; UTC date is the day after
# local (Pacific/Honolulu) date, so a non-UTC stamp is caught.
write_fake_clock() {
  cat >"$1/date" <<'FAKE'
#!/bin/bash
case "$*" in
  '+%s') cat "$FIXTURE_CLOCK" ;;
  '-u +%Y-%m-%d') echo 2026-11-12 ;;
  '+%Y-%m-%d') echo 2026-11-11 ;;
  *) echo "unexpected date $*" >&2; exit 90 ;;
esac
FAKE
  cat >"$1/sleep" <<'FAKE'
#!/bin/bash
printf 'sleep|%s\n' "$1" >>"$FIXTURE_LOG"
echo $(($(cat "$FIXTURE_CLOCK") + $1)) >"$FIXTURE_CLOCK"
FAKE
  chmod +x "$1/date" "$1/sleep"
}

# Git wrapper for faults at the index, tag and push-response boundaries.
git_fault() {
  cat >"$bin/git" <<'FAKE'
#!/bin/bash
case ${GIT_FAULT-} in
  tag) if [[ ${1-} == tag && ${2-} == -a ]]; then exit 1; fi ;;
  index) if [[ ${1-} == add ]]; then "$REAL_GIT" add VERSION; exit 1; fi ;;
  push-response) if [[ ${1-} == push && ${2-} == --atomic ]]; then "$REAL_GIT" "$@" && exit 1; exit; fi ;;
esac
exec "$REAL_GIT" "$@"
FAKE
  chmod +x "$bin/git"
  EXTRA+=("GIT_FAULT=$1")
}

# fixture: a fresh checkout at 0.4.0 whose main is pushed to a bare origin.
fixture() {
  F=$(mktemp -d "$SCRATCH/case.XXXXXXXX")
  repo=$F/checkout remote=$F/origin.git bin=$F/bin
  mkdir -p "$repo/scripts" "$bin" "$F/home"
  export HOME=$F/home GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null TZ=Pacific/Honolulu REAL_GIT
  export FIXTURE_LOG=$F/commands.log FIXTURE_STATE=$F/state.json FIXTURE_CLOCK=$F/clock
  : >"$FIXTURE_LOG"
  echo 0 >"$FIXTURE_CLOCK"
  echo '{"github":[],"hex":{},"package_uploads":[],"docs_uploads":[]}' >"$FIXTURE_STATE"
  EXTRA=()
  write_fake_tool "$bin/mix"
  write_fake_tool "$bin/gh"
  write_fake_tool "$repo/scripts/package_check.sh"
  write_fake_curl "$bin/curl"
  write_fake_clock "$bin"
  cd "$repo"
  g init -q --initial-branch=main
  g config user.name "Release Fixture"
  g config user.email fixture@example.test
  g init -q --bare "$remote"
  g remote add origin "$remote"
  cp "$ROOT/Makefile" Makefile
  echo 0.4.0 >VERSION
  printf '%s' "$OLD_README" >README.md
  printf '%s' "$OLD_CHANGELOG" >CHANGELOG.md
  commit
  g push -q origin main
  START=$(g rev-parse HEAD)
}
commit() {
  g add .
  g commit -q -m "Fixture preparation"
}
sync() {
  commit
  g push -q origin main
}
set_env() {
  EXTRA+=("$@")
}
# fixture_env CMD...: run CMD with only the fixture's environment.
fixture_env() {
  env -i PATH="$bin:$PATH" HOME="$HOME" TMPDIR="${TMPDIR:-/tmp}" GIT_CONFIG_NOSYSTEM=1 \
    GIT_CONFIG_GLOBAL=/dev/null TZ="$TZ" REAL_GIT="$REAL_GIT" FIXTURE_LOG="$FIXTURE_LOG" \
    FIXTURE_STATE="$FIXTURE_STATE" FIXTURE_CLOCK="$FIXTURE_CLOCK" ${EXTRA[@]+"${EXTRA[@]}"} "$@"
}
# capture CMD...: run CMD in the fixture; set RC, OUT and ERR.
capture() {
  RC=0
  fixture_env "$@" <"${STDIN:-/dev/null}" >"$F/out" 2>"$F/err" || RC=$?
  OUT=$(cat "$F/out")
  ERR=$(cat "$F/err")
}
# release BUMP [STDIN]: make release bump=BUMP; BUMP @none omits bump.
release() {
  local args=(make --no-print-directory release)
  [[ $1 == @none ]] || args+=("bump=$1")
  STDIN=${2:-} capture "${args[@]}"
}
workflow_step() {
  awk '/^      - /{step = ""} {step = step $0 "\n"} END {printf "%s", step}' "$ROOT/.github/workflows/release.yml"
}
# dispatch KEY=VALUE...: run the Release workflow step's command as Actions would.
dispatch() {
  local run
  run=$(workflow_step | sed -n 's/^        run: //p')
  capture env GITHUB_ACTIONS=true LEVEL=SMALL "$@" bash -e -c "$run"
}
remote_ref() {
  g ls-remote origin | awk -v ref="$1" '$2 == ref {print $1}'
}
public() {
  jq -c "$1" "$FIXTURE_STATE"
}
snapshot() {
  {
    find . -path ./.git -prune -o -type f -print | LC_ALL=C sort | while IFS= read -r file; do
      printf '%s ' "$file"
      cksum <"$file"
    done
    g rev-parse HEAD
    g branch --show-current
    g rev-list --count HEAD
    g status --porcelain --untracked-files=all
    g diff --cached --binary
    g show-ref || true
    g ls-remote origin
    cat "$FIXTURE_STATE"
  } | cksum
}
# refused CMD...: CMD must fail without changing files, Git or publications.
refused() {
  local before lines
  before=$(snapshot)
  lines=$(wc -l <"$FIXTURE_LOG")
  "$@"
  [[ $RC != 0 ]] || fail "expected a refusal: $*"$'\n'"$OUT"$'\n'"$ERR"
  eq "$(snapshot)" "$before" "refusal changed state: $*"
  if tail -n +$((lines + 1)) "$FIXTURE_LOG" | grep -qE '^(mix\|[^|]*\|hex\.publish|gh\|[^|]*\|release )'; then
    fail "refusal published: $*"
  fi
}
published() {
  local v=$1 t=v$1
  eq "$(cat VERSION; printf x)" "$v"$'\nx'
  contains "$(cat README.md)" "<!-- release-version: $v -->"
  contains "$(cat README.md)" "{:xlsx_composer, \"~> $v\"}"
  eq "$(g status --porcelain)" ""
  eq "$(g cat-file -t "$t")" tag
  eq "$(g rev-parse "$t^{}")" "$(g rev-parse HEAD)"
  eq "$(remote_ref refs/heads/main)" "$(g rev-parse HEAD)"
  eq "$(remote_ref "refs/tags/$t")" "$(g rev-parse "$t")"
  eq "$(g show --name-only --format= HEAD | LC_ALL=C sort)" "$FILES"
  eq "$(g log -1 --format=%s)" "chore: release $t"
  eq "$(public ".hex[\"$v\"]")" "{\"version\":\"$v\",\"has_docs\":true}"
  contains "$(public .github)" "\"$t\""
}

# repair: the documented inspect-and-finish procedure, driven by observed state.
repair() {
  local v=0.4.1 t=v0.4.1 head refs missing=() docs
  EXTRA=()
  rm -f "$bin/git"
  case $(cat VERSION) in 0.4.0 | 0.4.1) ;; *) fail "unexpected VERSION" ;; esac
  echo "$v" >VERSION
  printf '%s' "${OLD_README//0.4.0/$v}" >README.md
  printf '%s' "$OLD_CHANGELOG" >CHANGELOG.md
  replace_first CHANGELOG.md "## 0.4.1 (unreleased)" "## 0.4.1 (2026-11-12)"
  if [[ -n $(g status --porcelain) ]]; then
    rm -f .git/hooks/pre-commit
    g add -- VERSION README.md CHANGELOG.md
    g commit -q -m "chore: release $t"
  fi
  eq "$(g show --name-only --format= HEAD | LC_ALL=C sort)" "$FILES"
  [[ -n $(g tag --list "$t") ]] || g tag -a "$t" -m "Release $t"
  eq "$(g cat-file -t "$t")" tag
  eq "$(g rev-parse "$t^{}")" "$(g rev-parse HEAD)"
  head=$(g rev-parse HEAD)
  [[ $(remote_ref refs/heads/main) == "$head" ]] || missing+=("$head:refs/heads/main")
  [[ $(remote_ref "refs/tags/$t") == "$(g rev-parse "$t")" ]] || missing+=("$(g rev-parse "$t"):refs/tags/$t")
  if ((${#missing[@]})); then
    rm -f "$remote/hooks/update"
    g push -q --atomic origin "${missing[@]}"
  fi
  "$bin/gh" release view "$t" --repo example/xlsx_composer ||
    "$bin/gh" release create "$t" --repo example/xlsx_composer --verify-tag --generate-notes --title "$t"
  # Publication recovery runs in a separate clean checkout of the exact tag.
  [[ -d $F/recovery ]] || g clone -q --branch "$t" "$remote" "$F/recovery" 2>/dev/null
  eq "$(g -C "$F/recovery" status --porcelain)" ""
  docs=$(public ".hex[\"$v\"].has_docs")
  if [[ $docs == null ]]; then
    (cd "$F/recovery" && "$bin/mix" hex.publish --yes)
  elif [[ $docs == false ]]; then
    (cd "$F/recovery" && "$bin/mix" hex.publish docs --yes)
  fi
  eq "$(public ".hex[\"$v\"]")" "{\"version\":\"$v\",\"has_docs\":true}"
  eq "$(public .github)" "[\"$t\"]"
  eq "$(public .package_uploads)" "[\"$v\"]"
}

test_sequential_bumps_aliases_and_utc_stamp() {
  local bumps bump expected i count headings
  for bumps in "small MINOR MAJOR" "s mi Ma"; do
    fixture
    expected=(0.4.1 0.5.0 1.0.0)
    headings="## 0.3.9 (unreleased)"
    i=0
    for bump in $bumps; do
      if ((i > 0)); then
        replace_first CHANGELOG.md $'# Changelog\n' $'# Changelog\n\n## 9.9.9 (unreleased)\n'
        sync
      fi
      count=$(g rev-list --count HEAD)
      release "$bump"
      eq "$RC" 0 "$OUT$ERR"
      published "${expected[i]}"
      eq "$(g rev-list --count HEAD)" $((count + 1))
      headings="## ${expected[i]} (2026-11-12)"$'\n'"$headings"
      eq "$(grep '^## ' CHANGELOG.md)" "$headings"
      i=$((i + 1))
    done
    eq "$(grep '^mix|' "$FIXTURE_LOG" | head -n 7)" "mix|dev|deps.unlock --check-unused
mix|dev|compile --force --warnings-as-errors
mix|test|compile --force --warnings-as-errors
mix|dev|quality
mix|test|test
mix|dev|docs --warnings-as-errors
mix|dev|hex.publish --yes"
    contains "$(cat "$FIXTURE_LOG")" "package-check||"
    eq "$(grep '^gh||release create' "$FIXTURE_LOG" | head -n 1)" \
      "gh||release create v0.4.1 --repo example/xlsx_composer --verify-tag --generate-notes --title v0.4.1"
    lacks "$(cat "$FIXTURE_LOG")" whoami
  done
}

test_interactive_levels_and_aliases() {
  local pair
  for pair in "s=0.4.1" " SMALL =0.4.1" "mi=0.5.0" "minor=0.5.0" "ma=1.0.0" "major=1.0.0"; do
    fixture
    printf '%s\n' "${pair%=*}" >"$F/answer"
    release @none "$F/answer"
    eq "$RC" 0 "$OUT$ERR"
    contains "$OUT" "Version upgrade"
    published "${pair#*=}"
  done
}

test_invalid_input_is_transported_literally_without_make_or_shell_evaluation() {
  local sentinel value answer
  fixture
  sentinel=$F/sentinel
  for value in "" M PATCH "'" '"' "S; touch $sentinel" "\$(shell touch $sentinel)" \
    "\$(file >$sentinel,oops)" "\`touch $sentinel\`" '${HOME}' "\$\$(touch $sentinel)"; do
    refused release "$value"
    contains "$ERR" "Choose MAJOR"
    [[ ! -e $sentinel ]] || fail "input was evaluated: $value"
  done
  for answer in garbage $'\n' "" "'" '$(shell x)'; do
    printf '%s' "$answer" >"$F/answer"
    refused release @none "$F/answer"
  done
}

test_unsafe_git_states() {
  local state
  for state in dirty staged untracked detached branch stale push-urls local-tag remote-tag; do
    fixture
    case $state in
      dirty) echo edit >README.md ;;
      staged) echo edit >user-work; g add user-work ;;
      untracked) echo edit >user-work ;;
      detached) g checkout -q --detach ;;
      branch) g checkout -q -b feature ;;
      stale) g commit -q --allow-empty -m Unpushed ;;
      push-urls) g config --add remote.origin.pushurl "$remote"; g config --add remote.origin.pushurl "$remote" ;;
      local-tag) g tag v0.4.1 ;;
      remote-tag) g push -q origin HEAD:refs/tags/v0.4.1 ;;
    esac
    refused release SMALL
  done
}

test_malformed_release_documents() {
  local version kind heading
  for version in $'01.2.3\n' $'1.2\n' $'1.2.3-rc1\n' $'1.2.3\nother' $' 1.2.3\n' $'-1.0.0\n' $'0.4.0\n\n'; do
    fixture
    printf '%s' "$version" >VERSION
    sync
    refused release SMALL
    contains "$ERR" "VERSION must contain"
  done
  for kind in missing-marker duplicate-marker wrong-marker missing-install duplicate-install wrong-install \
    dated trailing-space no-top bad-semver; do
    fixture
    case $kind in
      missing-marker) replace_first README.md "<!-- release-version: 0.4.0 -->" "" ;;
      duplicate-marker) echo "<!-- release-version: 0.4.0 -->" >>README.md ;;
      wrong-marker) replace_first README.md "release-version: 0.4.0" "release-version: 0.3.0" ;;
      missing-install) head -n 1 README.md >README.tmp && mv README.tmp README.md ;;
      duplicate-install) echo '{:xlsx_composer, "~> 0.4.0"}' >>README.md ;;
      wrong-install) replace_first README.md '"~> 0.4.0"' '"~> 0.3.0"' ;;
      *)
        case $kind in
          dated) heading="## 0.4.1 (2026-11-11)" ;;
          trailing-space) heading="## 0.4.1 (unreleased) " ;;
          no-top) heading="## Unreleased" ;;
          bad-semver) heading="## 01.2.3 (unreleased)" ;;
        esac
        replace_first CHANGELOG.md "## 0.4.1 (unreleased)" "$heading" ;;
    esac
    sync
    refused release SMALL
    contains "$ERR" "synchronize release documentation"
  done
}

test_existing_hex_unknown_http_and_missing_ci_key() {
  local state
  for state in existing timeout bad wrong 503 array string ci-missing ci-empty ci-blank; do
    fixture
    case $state in
      existing)
        jq '.hex["0.4.1"] = {version: "0.4.1", has_docs: false}' "$FIXTURE_STATE" >"$F/next"
        mv "$F/next" "$FIXTURE_STATE" ;;
      ci-missing) set_env GITHUB_ACTIONS=true ;;
      ci-empty) set_env GITHUB_ACTIONS=true HEX_API_KEY= ;;
      ci-blank) set_env GITHUB_ACTIONS=true HEX_API_KEY=$'  \t' ;;
      *) set_env HTTP_MODE="$state" ;;
    esac
    refused release SMALL
    if grep -q '^mix|' "$FIXTURE_LOG"; then fail "validation ran for $state"; fi
    contains "$ERR" "0.4.1"
    lacks "$ERR" "secret-proxy"
  done
  fixture
  set_env GITHUB_ACTIONS=true HEX_API_KEY=fixture-private-key GH_TOKEN=fixture-private-token
  release SMALL
  eq "$RC" 0 "$OUT$ERR"
  lacks "$OUT$ERR$(cat "$FIXTURE_LOG")" fixture-private
}

test_release_workflow_step_invokes_the_same_make_release() {
  local step key
  step=$(workflow_step)
  [[ $step == "      - name: Release"$'\n'* ]] || fail "last Release workflow step is not named Release"
  eq "$(printf '%s\n' "$step" | sed -n 's/^        run: //p')" 'make release bump="$LEVEL"'
  eq "$(printf '%s\n' "$step" | sed -n 's/^          \([A-Za-z_]*\):.*/\1/p' | LC_ALL=C sort | tr '\n' ' ')" \
    "GH_TOKEN HEX_API_KEY LEVEL "
  fixture
  dispatch GH_TOKEN=fixture-private-token HEX_API_KEY=fixture-private-key
  eq "$RC" 0 "$OUT$ERR"
  published 0.4.1
  eq "$(public .package_uploads)" '["0.4.1"]'
  lacks "$OUT$ERR$(cat "$FIXTURE_LOG")" fixture-private
  for key in "" $' \t'; do
    fixture
    refused dispatch GH_TOKEN=fixture HEX_API_KEY="$key"
  done
  fixture
  refused dispatch GH_TOKEN=fixture
}

test_rerun_of_original_event_after_remote_advances_is_refused() {
  fixture
  g clone -q --branch main "$remote" "$F/other"
  g -C "$F/other" -c user.name=Other -c user.email=o@example.test commit -q --allow-empty -m "Later main"
  g -C "$F/other" push -q origin main
  refused dispatch GH_TOKEN=fixture HEX_API_KEY=fixture
  contains "$ERR" "must match the origin push destination"
  eq "$(g rev-parse HEAD)" "$START"
}

test_each_validation_gate_failure_preserves_state() {
  local command
  for command in "gh repo view" "mix deps.unlock --check-unused" "mix compile --force --warnings-as-errors:dev" \
    "mix compile --force --warnings-as-errors:test" "mix quality" "mix test" "mix docs --warnings-as-errors" \
    "package-check "; do
    fixture
    if [[ $command == "gh repo view" ]]; then
      command="gh repo view $remote --json nameWithOwner --jq .nameWithOwner"
    fi
    set_env FAIL_COMMAND="$command"
    refused release SMALL
  done
}

test_checkout_changes_during_validation_including_branch_at_same_head() {
  local mutation before
  for mutation in branch head untracked; do
    fixture
    set_env MUTATE_CHECK="$mutation"
    before=$(g ls-remote origin)
    release SMALL
    [[ $RC != 0 ]] || fail "release succeeded after $mutation"
    contains "$ERR" "checkout changed during validation"
    eq "$(g ls-remote origin)" "$before"
    eq "$(cat VERSION)" 0.4.0
    eq "$(g tag --list)" ""
    eq "$(public .github)" "[]"
    if [[ $mutation == branch ]]; then eq "$(g rev-parse HEAD)" "$START"; fi
  done
}

test_failure_boundaries_retry_refusal_and_state_derived_recovery() {
  local boundary text lines final
  for boundary in index commit tag push-rejection push-response github github-ambiguous hex hex-ambiguous \
    docs metadata-timeout complete; do
    fixture
    case $boundary in
      index | tag | push-response) git_fault "$boundary" ;;
      commit) printf '#!/bin/sh\nexit 1\n' >.git/hooks/pre-commit; chmod +x .git/hooks/pre-commit ;;
      push-rejection)
        printf '#!/bin/sh\ncase "$1" in refs/tags/*) exit 1;; esac\n' >"$remote/hooks/update"
        chmod +x "$remote/hooks/update" ;;
      github) set_env FAIL_COMMAND="gh release create v0.4.1 --repo example/xlsx_composer --verify-tag --generate-notes --title v0.4.1" ;;
      github-ambiguous) set_env GH_AMBIGUOUS=1 ;;
      hex) set_env FAIL_COMMAND="mix hex.publish --yes" ;;
      hex-ambiguous) set_env FAIL_COMMAND="mix hex.publish --yes" HEX_AMBIGUOUS=1 ;;
      docs) set_env NO_DOCS=1 ;;
      metadata-timeout) set_env HTTP_AFTER=timeout ;;
    esac
    release SMALL
    if [[ $boundary == complete ]]; then eq "$RC" 0 "$OUT$ERR"; else [[ $RC != 0 ]] || fail "$boundary succeeded"; fi
    case $boundary in
      index | commit)
        eq "$(g rev-parse HEAD)" "$START"
        eq "$(g tag --list)" ""
        eq "$(cat VERSION)" 0.4.1
        if [[ $boundary == index ]]; then
          eq "$(g diff --cached --name-only)" VERSION
        else
          eq "$(g diff --cached --name-only | LC_ALL=C sort)" "$FILES"
        fi ;;
      *)
        eq "$(g rev-list --count HEAD)" 2
        eq "$(g status --porcelain)" ""
        if [[ $boundary == tag ]]; then eq "$(g tag --list)" ""; else eq "$(g cat-file -t v0.4.1)" tag; fi ;;
    esac
    case $boundary in
      index | commit | tag | push-rejection)
        eq "$(remote_ref refs/heads/main)" "$START"
        eq "$(remote_ref refs/tags/v0.4.1)" ""
        eq "$(public .github)" "[]" ;;
      *)
        eq "$(remote_ref refs/heads/main)" "$(g rev-parse HEAD)"
        eq "$(remote_ref refs/tags/v0.4.1)" "$(g rev-parse v0.4.1)" ;;
    esac
    if [[ $boundary != complete ]]; then
      for text in "last known stage:" "repository example/xlsx_composer" "tag v0.4.1" "git ls-remote" "v0.4.1^{}" \
        "gh release view v0.4.1 --repo example/xlsx_composer" "mix hex.info xlsx_composer 0.4.1" \
        "mix hex.publish docs --yes" "Unknown state"; do
        contains "$ERR" "$text"
      done
    fi
    if [[ $boundary == docs ]]; then contains "$ERR" "completion unverified"; fi
    if [[ $boundary == push-response ]]; then contains "$ERR" "push response unknown"; fi
    case $boundary in
      hex-ambiguous | metadata-timeout | docs | complete) eq "$(public .package_uploads)" '["0.4.1"]' ;;
    esac
    # A new bump cannot resume any leftover, even after clearing injected faults.
    EXTRA=()
    rm -f "$bin/git"
    lines=$(wc -l <"$FIXTURE_LOG")
    refused release SMALL
    if tail -n +$((lines + 1)) "$FIXTURE_LOG" | grep -qE '^(mix|gh|curl)\|'; then fail "retry reached publishers"; fi
    repair
    final=$(snapshot)
    eq "$(g rev-list --count HEAD)" 2
    published 0.4.1
    if [[ $boundary == docs ]]; then eq "$(public .docs_uploads)" '["0.4.1"]'; else eq "$(public .docs_uploads)" "[]"; fi
    # Re-observing a completed recovery adds no commit, tag or upload.
    repair
    eq "$(snapshot)" "$final"
  done
}

test_hex_polling_waits_through_pending_and_unknown_answers() {
  fixture
  set_env HTTP_AFTER=404,timeout,bad,wrong,false,record
  release SMALL
  eq "$RC" 0 "$OUT$ERR"
  eq "$(grep -c '^curl|' "$FIXTURE_LOG")" 7
  eq "$(grep '^sleep|' "$FIXTURE_LOG" | tr '\n' ' ')" "sleep|2 sleep|2 sleep|2 sleep|2 sleep|2 "
}

test_hex_deadline_clips_requests_and_sleep_and_rejects_late_body() {
  local late
  for late in false true; do
    fixture
    set_env HTTP_AFTER="+57:false,+2:$late"
    release SMALL
    [[ $RC != 0 ]] || fail "late answer accepted"
    contains "$ERR" "completion unverified"
    eq "$(grep '^curl|' "$FIXTURE_LOG" | tail -n +2 | cut -d'|' -f2 | tr '\n' ' ')" "max=10 max=1 "
    eq "$(grep '^sleep|' "$FIXTURE_LOG" | tr '\n' ' ')" "sleep|2 "
    eq "$(cat "$FIXTURE_CLOCK")" 61
  done
  fixture
  set_env HTTP_AFTER="+59:false"
  release SMALL
  [[ $RC != 0 ]] || fail "pending docs accepted"
  eq "$(grep '^curl|' "$FIXTURE_LOG" | tail -n +2 | cut -d'|' -f2 | tr '\n' ' ')" "max=10 "
  eq "$(grep '^sleep|' "$FIXTURE_LOG" | tr '\n' ' ')" "sleep|1 "
}

passed=0
failed=0
for name in $(declare -F | awk '$3 ~ /^test_/ {print $3}'); do
  (
    set -e
    "$name"
  ) >"$SCRATCH/$name.log" 2>&1
  if [[ $? == 0 ]]; then
    passed=$((passed + 1))
    printf 'ok    %s\n' "$name"
  else
    failed=$((failed + 1))
    printf 'FAIL  %s\n' "$name"
    tail -n 25 "$SCRATCH/$name.log" | sed 's/^/      /'
  fi
done
printf '%s passed, %s failed\n' "$passed" "$failed"
((failed == 0))
endef
