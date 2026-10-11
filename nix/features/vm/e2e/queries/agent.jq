$specification[0].launchAgent + {
  Label: $label,
  ProgramArguments: [
    ($tools + "/EnvironmentProbe"), "--profile", "guest",
    "--fixture", ($tools + "/FixtureApp.app"),
    "--output", ($remote + "/qualification.json")
  ],
  EnvironmentVariables: (
    $specification[0].launchAgent.EnvironmentVariables + {
      STRATOSPHERE_IMAGE_IDENTITY: $image,
      STRATOSPHERE_BUILD_METADATA: ($metadata | tojson)
    } + (if $metadata.sourceRevision then {
      STRATOSPHERE_SOURCE_REVISION: $metadata.sourceRevision
    } else {} end)
  ),
  StandardOutPath: ($remote + "/probe.log"),
  StandardErrorPath: ($remote + "/probe.log")
}
