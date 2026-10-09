# Neon District artwork

`neon-district.png` is the original background for **Neon District**. It was
created with Codex's built-in `imagegen` tool on 2026-10-02 from the prompt below.
No external image API or API key is used by this project. The installed saver
loads this local PNG and draws animation in native Swift code; it makes no
network requests.

The user supplied a Cyberpunk-themed city and sports-car screenshot as a visual
reference for this generation. That reference is **not included in this
repository**. The generated scene uses its own car, fictional advertising and
architecture. It contains no foreground person. The portrait on a building is
part of a fictional advertisement. This project has no affiliation with
Cyberpunk 2077 or its creators.

The generated PNG is 1586 × 992 pixels and is saved unchanged. At runtime the
renderer samples it onto a 1152 × 720 raster using nearest-neighbor sampling.
Animated signs, lights, smoke and reflections use the same pixel grid.

## Exact generation prompt

```text
Use case: stylized-concept.
Asset type: background artwork for an actual macOS pixel-art screensaver, landscape 16:10. Make a highly polished coherent pixel-art illustration, not a mockup, not a screenshot of an app. Use the supplied image ONLY as a reference for mood, visual density, low street-level composition and cyan/magenta lighting. Create original artwork.
Scene: atmospheric nocturnal cyberpunk megacity, layered imposing buildings filling the upper two-thirds, dense intricate architecture, luminous vertical billboards, cyan building edges, violet and electric-magenta advertising, deep midnight blue/teal sky. Wet urban street in the foreground with crisp broken reflections and small pavement details. Strong perspective and believable depth, visually rich like a finished indie game background. No overwhelming white or neon bloom.
Main subject: an original low, wide, angular futuristic sports coupe parked in the foreground at the right, rear three-quarter view, front facing to the right; thick dark tires, cyan wheel rims, restrained magenta/cyan trim, rear engine vents and two visible exhaust outlets pointing left. The complete car, including tires and nose, must fit comfortably inside the image. Approximate framing: car occupies x=30%..93%, y=60%..89%. Leave visible street below it. Rear lights and exhaust tips should be distinguishable, for subtle animation later. The distant city remains visible above the car roof.
Screens: 3-5 large clearly bounded flat billboard screens on buildings, readable as individual surfaces with bright pixel borders. Their contents are fictional abstract techno graphics or a stylized portrait advertisement, no actual game logos, no known corporate names, no trademark emblems. Keep their surfaces simple enough for animated native-code overlays. Strong purple vertical screen at left; turquoise horizontal screen at upper right; a couple smaller magenta panels deeper in the city.
Style: authentic deliberate pixel art as if authored on a single ~480x300 pixel grid and enlarged using nearest-neighbor. Every pixel has clean square edges; architectural details and curved tire silhouettes are carefully stepped. Limited controlled palette, intentional clusters and dithering rather than photographic noise. Consistent pixel scale across buildings, car and reflections. No smooth photorealism, no vector look, no blur, no anti-aliased edges.
Constraints: remove the standing foreground man from the reference entirely. NO people, NO human silhouettes anywhere on the street or near the car. A portrait confined inside a billboard is allowed. No watermark, no border, no captions, no UI. Do not reproduce Cyberpunk 2077 branding, Arasaka logo, or exact reference car model. The visual atmosphere may evoke the game. No fog or smoke obscuring the car; exhaust smoke will be animated in code. Place all important features inside a 4% margin. Final image should be visually exciting, cinematic yet calm enough to look at for a long time.
```
