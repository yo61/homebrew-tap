#!/usr/bin/env bash
set -euo pipefail

formula_dir="${1:-Formula}"
status=0

for file in "$formula_dir"/*.rb; do
  formula="$(basename "$file" .rb)"

  root_url="$(sed -n -E 's/^    root_url "(.*)"$/\1/p' "$file")"
  if [[ -z "$root_url" ]]; then
    echo "${formula}: no bottle root_url, skipped"
    continue
  fi

  sdist="$(grep -oE "${formula}-[0-9][^\"/]*\.tar\.gz" "$file" | head -1 || true)"
  version="${sdist#"${formula}"-}"
  version="${version%.tar.gz}"
  if [[ -z "$version" ]]; then
    echo "::error file=${file}::${formula}: has a bottle root_url but no ${formula}-<version>.tar.gz url to compare it with"
    status=1
    continue
  fi

  revision="$(sed -n -E 's/^  revision ([0-9]+)$/\1/p' "$file")"
  expected="${formula}-${version}${revision:+_${revision}}"
  actual="${root_url##*/}"

  if [[ "$actual" == "$expected" ]]; then
    echo "${formula}: bottle block matches ${expected}"
    continue
  fi

  echo "::error file=${file}::${formula}: formula is ${expected} but its bottle block points at ${actual}." \
    "A bump PR is in this state until publish-bottles adds the bottle commit: do not merge it by hand."
  status=1
done

exit "$status"
