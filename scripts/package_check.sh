#!/usr/bin/env bash
# Compile the actual unpacked Hex package as a fresh host's only direct dependency.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/xlsx_composer-package-check.XXXXXXXX")"
trap 'rm -rf "$work_dir"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# A caller's Mix paths must not turn the fresh host into a checkout-cache check.
unset MIX_BUILD_PATH MIX_DEPS_PATH MIX_LOCKFILE MIX_ENV MIX_TARGET

source_version="$(cat "$repo_root/VERSION")"
cd "$repo_root"
mix hex.build --unpack --output "$work_dir/xlsx_composer"

cmp "$repo_root/VERSION" "$work_dir/xlsx_composer/VERSION"
cd "$work_dir/xlsx_composer"
package_version="$(mix run --no-compile --no-deps-check --no-start -e 'IO.puts(Mix.Project.config()[:version])')"
if [[ "$package_version" != "$source_version" ]]; then
  printf 'Package version %s does not match VERSION %s\n' "$package_version" "$source_version" >&2
  exit 1
fi
printf 'Packaged version: %s\n' "$package_version"

mkdir "$work_dir/host"
cat > "$work_dir/host/mix.exs" <<'EOF'
defmodule PackageCheckHost.MixProject do
  use Mix.Project

  def project do
    [
      app: :package_check_host,
      version: "0.1.0",
      elixir: "~> 1.18",
      deps: [{:xlsx_composer, path: "../xlsx_composer"}]
    ]
  end

  def application, do: [extra_applications: [:logger]]
end
EOF

cd "$work_dir/host"
mix deps.get
mix compile --warnings-as-errors
installed_version="$(mix run --no-start -e 'Application.load(:xlsx_composer); IO.puts(Application.spec(:xlsx_composer, :vsn))')"
if [[ "$installed_version" != "$source_version" ]]; then
  printf 'Installed version %s does not match VERSION %s\n' "$installed_version" "$source_version" >&2
  exit 1
fi
printf 'Installed version: %s\n' "$installed_version"
