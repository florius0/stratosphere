if type == "array" and all(.[];
  type == "object" and (.Source | type) == "string" and (.Name | type) == "string")
then any(.[]; .Source == "local" and .Name == $image)
else error("Invalid Tart image listing")
end
