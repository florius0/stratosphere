#!/usr/bin/env bash
mapfile -d "" files < <(find docs -type f -name '*.md' -print0)
for name in AGENTS.md README.md; do
  if [[ -f $name ]]; then files+=("$name"); fi
done
lychee --config /dev/null --offline --include-fragments --no-progress -- "${files[@]}"
gawk -f "$STRATOSPHERE_REFERENCES_QUERY" docs/{concepts,feature-map,functional-requirements,non-functional-requirements,decision-map}.md "${files[@]}"
while IFS= read -r -d "" diagram; do
  dot -Tsvg "$diagram" -o /dev/null
done < <(find docs -type f -name '*.dot' -print0)
echo "Documentation links and product references checked in ${#files[@]} files; DOT summaries parsed."
