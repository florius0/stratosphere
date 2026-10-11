#!/usr/bin/env bash
mkdir -p fixture
cd fixture
git init -q
printf '{x=1;}\n' >flake.nix
printf 'let number=1\n' >Example.swift
printf 'int example(){return 1;}\n' >example.m
printf '{"x":1}\n' >example.json
printf 'name:   CI\n' >example.yml
printf '# Heading\n\nA line of prose whose wrapping must remain unchanged.\n' >example.md
printf '#!/usr/bin/env bash\nif true;then echo ok;fi\n' >example.sh
printf 'x=1\n' >example.toml
mkdir -p .github/workflows .local/tart .build .swiftpm .direnv
cp example.yml .github/workflows/example.yml
for directory in .local/tart .build .swiftpm .direnv; do
  printf '{ignored=1;}\n' >"$directory/ignored.nix"
done
printf 'if true;then echo ok;fi\n' >.envrc
git add .
if treefmt --no-cache --fail-on-change >rejected.log 2>&1; then
  echo 'Unformatted sources accepted' >&2
  exit 1
fi
treefmt --no-cache
treefmt --no-cache --fail-on-change
for directory in .local/tart .build .swiftpm .direnv; do
  test "$(cat "$directory/ignored.nix")" = '{ignored=1;}'
done
test "$(cat .github/workflows/example.yml)" = 'name: CI'
for file in flake.nix Example.swift example.m example.json example.yml example.sh example.toml .envrc; do
  if git diff --quiet -- "$file"; then
    echo "Formatter did not process $file" >&2
    exit 1
  fi
done
grep -Fx 'A line of prose whose wrapping must remain unchanged.' example.md
touch "$out"
