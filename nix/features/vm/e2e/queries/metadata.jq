if type != "object" then error("object required") else . end |
with_entries(select(.key | IN("compiler","sdk","macOS","sourceRevision","xcode"))) |
if all(.[]; type == "string" and (gsub("\\s"; "") | length > 0) and utf8bytelength <= 4096 and (explode | all(. >= 32 or . == 10 or . == 9))) then . else error("invalid metadata") end
