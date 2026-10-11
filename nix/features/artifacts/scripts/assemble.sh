#!/usr/bin/env bash
binaries=$1
destination=$2
while IFS=$'\t' read -r name plist; do
  mkdir -p "$destination/$name.app/Contents/MacOS" "$destination/$name.app/Contents/Resources"
  cp "$binaries/$name" "$destination/$name.app/Contents/MacOS/$name"
  chmod 755 "$destination/$name.app/Contents/MacOS/$name"
  cp "$plist" "$destination/$name.app/Contents/Info.plist"
  while IFS=$'\t' read -r resource source; do
    cp "$source" "$destination/$name.app/Contents/Resources/$resource"
  done < <(jq -r --arg name "$name" '.apps[$name].resources | to_entries[] | [.key, .value] | @tsv' "$STRATOSPHERE_ARTIFACT_SPEC")

done < <(jq -r '.apps | to_entries[] | [.key, .value.plist] | @tsv' "$STRATOSPHERE_ARTIFACT_SPEC")
while IFS= read -r name; do
  cp "$binaries/$name" "$destination/$name"
  chmod 755 "$destination/$name"
done < <(jq -r '.executables[]' "$STRATOSPHERE_ARTIFACT_SPEC")
