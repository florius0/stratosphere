# App icons

Five selected Stratosphere designs, each with a 1024 × 1024 transparent PNG and a macOS `.icns` file containing standard and Retina representations:

| File stem             | Design                                                                   |
| --------------------- | ------------------------------------------------------------------------ |
| `AtmosphericLayers`   | A: layered blue atmospheric ribbons                                      |
| `WindowConstellation` | B: overlapping blue, lavender, and cyan glass windows                    |
| `StratosphericS`      | C: vibrant blue S on white glass                                         |
| `PlanetAtmosphere`    | First planet with a surrounding atmospheric halo                         |
| `PlanetSunlit`        | Revised planet with broad upper-left light and a shaded lower-right face |

`PlanetSunlit.icns` is the current app icon. The [bundle specification](../../nix/features/artifacts/package.nix) selects it for the Story Catalog, the current Stratosphere UI development app. The fixture app retains its separate identity.

The PNGs preserve the original generated interior artwork, resized onto a transparent icon canvas with a consistent inset. Each tile uses a fitted contour to exclude the opaque exterior backdrop and shadow; the blue and white tiles require different contours. A generic rounded-rectangle mask leaves visible exterior matte and must not be reused. The corrected edges were inspected on dark and light backgrounds. The `.icns` files include 16, 32, 64, 128, 256, 512, and 1024 pixel representations, including Retina variants. Artwork was generated with the built-in image tool; Apple image tooling packages the assets. No animation is included.
