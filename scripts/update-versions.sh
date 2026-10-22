#!/usr/bin/env bash
# Bumps invoiceninja/package.nix to the latest upstream invoiceninja and
# invoiceninja/ui versions, then rebuilds repeatedly -- using the
# "specified vs. got" hash mismatch that Nix reports for each
# fixed-output derivation -- to fill in the correct src/npmDeps/vendor
# hashes. Invoked via `just update`.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

pkg=package.nix

# Replaces the RHS (between the first "=" and the last ";") of the line
# immediately following the first line containing $anchor.
set_after() {
  local file="$1" anchor="$2" newrhs="$3"
  awk -v anchor="$anchor" -v newrhs="$newrhs" '
    {
      if (found) {
        sub(/=.*;/, "= " newrhs ";")
        found = 0
      }
      if (index($0, anchor) > 0) found = 1
      print
    }
  ' "$file" > "${file}.tmp"
  mv "${file}.tmp" "$file"
}

# Replaces the RHS of the first line assigning to $field. Only the first
# match is touched -- "version" is assigned twice in package.nix (the
# top-level invoiceninja version, and buildNpmPackage's own "version"
# attribute for the ui derivation, which must stay "= uiVersion;") and the
# top-level one always comes first.
set_field() {
  local file="$1" field="$2" newrhs="$3"
  awk -v field="$field" -v newrhs="$newrhs" '
    {
      if (!done && $0 ~ "^[[:space:]]*" field "[[:space:]]*=") {
        sub(/=.*;/, "= " newrhs ";")
        done = 1
      }
      print
    }
  ' "$file" > "${file}.tmp"
  mv "${file}.tmp" "$file"
}

current_main_version=$(grep -m1 -E '^\s*version = "' "$pkg" | sed -E 's/.*"([^"]+)".*/\1/')
current_ui_version=$(grep -m1 -E '^\s*uiVersion = "' "$pkg" | sed -E 's/.*"([^"]+)".*/\1/')

echo "Current: invoiceninja=$current_main_version ui=$current_ui_version"

latest_main_version=$(curl -sf https://api.github.com/repos/invoiceninja/invoiceninja/releases/latest | jq -r '.tag_name' | sed 's/^v//')

# invoiceninja/ui has no GitHub Releases, just date-stamped tags
# (DD.MM.YYYY.N) -- paginate through all tags and pick the newest by
# calendar date, ignoring "-release" hotfix tags and other one-off tag
# names that don't fit that scheme.
ui_tags=""
page=1
while :; do
  batch=$(curl -sf "https://api.github.com/repos/invoiceninja/ui/tags?per_page=100&page=${page}" | jq -r '.[].name')
  [ -z "$batch" ] && break
  ui_tags="${ui_tags}
${batch}"
  page=$((page + 1))
done

latest_ui_version=$(printf '%s\n' "$ui_tags" \
  | grep -E '^[0-9]{2}\.[0-9]{2}\.[0-9]{4}\.[0-9]+$' \
  | awk -F. '{printf "%s%02d%02d%s %s\n", $3, $2, $1, $4, $0}' \
  | sort \
  | tail -1 \
  | awk '{print $2}')

if [ -z "$latest_main_version" ] || [ -z "$latest_ui_version" ]; then
  echo "error: failed to determine latest versions (main=$latest_main_version ui=$latest_ui_version)" >&2
  exit 1
fi

echo "Latest:  invoiceninja=$latest_main_version ui=$latest_ui_version"

main_changed=0
ui_changed=0

if [ "$latest_main_version" != "$current_main_version" ]; then
  main_changed=1
  set_field "$pkg" version "\"$latest_main_version\""
fi

if [ "$latest_ui_version" != "$current_ui_version" ]; then
  ui_changed=1
  set_field "$pkg" uiVersion "\"$latest_ui_version\""
fi

if [ "$main_changed" = 0 ] && [ "$ui_changed" = 0 ]; then
  echo "Already up to date."
  exit 0
fi

# Invalidate every hash that could have changed as a result of the version
# bump(s) above, so the rebuild loop below reports the real ones.
if [ "$main_changed" = 1 ]; then
  set_after "$pkg" 'rev = "v${version}";' 'lib.fakeHash'
  set_after "$pkg" 'inherit src;' 'lib.fakeHash'
  set_field "$pkg" vendorHash 'lib.fakeHash'
fi

if [ "$ui_changed" = 1 ]; then
  set_after "$pkg" 'tag = uiVersion;' 'lib.fakeHash'
  set_field "$pkg" npmDepsHash 'lib.fakeHash'
fi

echo "Rebuilding to discover the correct hashes (this takes a few iterations)..."

max_iterations=10
for ((i = 1; i <= max_iterations; i++)); do
  echo "--- build attempt $i/$max_iterations ---"
  set +e
  build_output=$(nix build ".#invoiceninja" ".#invoiceninja.ui" --no-link -L 2>&1)
  status=$?
  set -e

  if [ "$status" -eq 0 ]; then
    echo "Build succeeded."
    exit 0
  fi

  mismatch_line=$(printf '%s\n' "$build_output" | grep -m1 "hash mismatch in fixed-output derivation" || true)
  if [ -z "$mismatch_line" ]; then
    echo "$build_output" | tail -80
    echo "error: build failed for a reason other than a hash mismatch; see output above" >&2
    exit 1
  fi

  drv_path=$(printf '%s\n' "$mismatch_line" | sed -E "s/.*'([^']+)'.*/\1/")
  # Store paths are "<32-char hash>-<name>"; strip the hash to get the name.
  name=$(basename "$drv_path" .drv | sed -E 's/^[0-9a-z]{32}-//')
  got_hash=$(printf '%s\n' "$build_output" | grep -m1 -E '^\s+got: ' | awk '{print $2}')

  if [ -z "$got_hash" ]; then
    echo "$build_output" | tail -80
    echo "error: could not parse the correct hash out of the build output above" >&2
    exit 1
  fi

  echo "Fixing hash for '$name': $got_hash"

  case "$name" in
    invoiceninja)
      set_after "$pkg" 'rev = "v${version}";' "\"$got_hash\""
      ;;
    invoiceninja-ui)
      set_after "$pkg" 'tag = uiVersion;' "\"$got_hash\""
      ;;
    invoiceninja-ui-*-npm-deps)
      set_field "$pkg" npmDepsHash "\"$got_hash\""
      ;;
    invoiceninja-composer-composer-repository-*)
      set_field "$pkg" vendorHash "\"$got_hash\""
      ;;
    invoiceninja-*-npm-deps)
      set_after "$pkg" 'inherit src;' "\"$got_hash\""
      ;;
    *)
      echo "error: unrecognized derivation '$name' in hash mismatch; don't know which field to update" >&2
      exit 1
      ;;
  esac
done

echo "error: exceeded $max_iterations build attempts without resolving all hash mismatches" >&2
exit 1
