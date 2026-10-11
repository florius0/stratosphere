#!/usr/bin/env bash
mkdir -p fixture/docs
cd fixture
for name in concepts feature-map functional-requirements non-functional-requirements decision-map; do
  : >"docs/$name.md"
done
cp "$DOC_FIXTURES/concepts.md" docs/concepts.md
echo '**F-01** — Feature' >docs/feature-map.md
echo '**FR-01:** Requirement' >docs/functional-requirements.md
echo '**NFR-01:** Quality' >docs/non-functional-requirements.md
printf '| D-01 | Decision |\n## Q-01 — Research\n' >docs/decision-map.md
cp "$DOC_FIXTURES/README.md" README.md
chmod u+w README.md
echo 'digraph Valid { a -> b }' >docs/concepts.dot
stratosphere-docs
cp README.md valid.md
reject() {
  if stratosphere-docs >result.log 2>&1; then
    echo "Accepted invalid $1" >&2
    exit 1
  fi
  grep -qi "$2" result.log
  cp valid.md README.md
}
echo '[missing](docs/absent.md)' >>README.md
reject link absent
echo '[missing](docs/concepts.md#absent)' >>README.md
reject anchor absent
echo 'FR-999' >>README.md
reject ID FR-999
echo 'digraph Broken { a -> }' >docs/concepts.dot
reject DOT syntax
touch "$out"
