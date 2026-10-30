# Hadal Outpost artwork

The artwork was generated with the built-in `imagegen` tool on 2026-10-30.
Version 0.2.0 bundles the coherent city/seabed painting and five transparent
creature sprites unchanged in both targets. The earlier small station sprite
is preserved as a source asset but is no longer included in the builds.
No image service, API key or network connection is used at runtime.

| Resource | Origin |
| --- | --- |
| `hadal-city-seabed.png` | Current micro-city and detailed seafloor |
| `hadal-station.png` | Preserved 0.1.0 station sprite; excluded from current builds |
| `hadal-ribbon.png` | New gulper eel |
| `hadal-medusa.png` | New giant medusa |
| `hadal-carapace.png` | New armored crustacean |
| `hadal-maw.png` | Unmodified copy of `../../Abyss/Resources/abyss-leviathan.png` |
| `hadal-elder.png` | Unmodified copy of `../../Abyss/Resources/abyss-elder.png` |

The original Abyss Station scene and its assets are preserved. Provenance and
prompts for the two reused creatures are in [Abyss artwork](../../Abyss/Resources/ARTWORK.md).
The renderer extends the scene at different aspect ratios, deforms creature
sprites and reveals them through a per-frame illumination mask. Pressure-field
geometry, searchlights, flares, defensive charges, scatter and bubbles are
native Swift graphics. Every species approaches through water above the city.

## Visual references

Only broad mood, scale, anatomy and silhouette cues were used. No game images,
models, textures or audio are bundled. This is an independent project with no
affiliation with the games or their creators.

- [Unknown Worlds: leviathan development](https://unknownworlds.com/en/news/subnautica-2-dev-vlog-3)
- [Barotrauma developers: abyss creatures](https://barotraumagame.com/gameplay-features/here-be-dragons-reintroducing-abyss-creatures/)
- [Barotrauma official media](https://barotraumagame.com/press/)

## Exact generation prompts

### Station sprite

```text
Use case: stylized-concept. Asset type: a single original research-outpost sprite for a native macOS underwater screensaver, genuine transparent background around entire object. Primary request: a small lonely heavy pressure-resistant deep-ocean research base, full station viewed frontally from a slightly elevated three-quarter angle, centred balanced composition. The base is a squat circular multi-storey cylindrical control habitat with a small glass observation dome, joined on both sides to two short ribbed horizontal pressure modules, pipes, narrow gantries, thick hatches and four small articulated floodlight arms pointing outward. Dense mechanical detail, corroded ivory metal, lead grey pressure ribs, restrained warm amber windows, a few very dim cyan practical lamps. Include short steel supporting legs and a narrow compact foundation pad directly under the structures; no landscape. Wide low silhouette about 2:1 width to height, complete structure and appendages inside generous 6% transparent margins, central circular core roughly centred. Lighting must feel like the bottom of the darkest ocean: most metal in cold blue-black shadow with readable subtle steel texture, warm windows provide a tiny human focal point. Floodlight bulbs may be present but NO emitted cones or broad glow, because these are animated in code. Detailed painterly pixel-art indie game environmental asset; small deliberate pixel clusters, convincing aged materials, original architecture, NOT vector blocks, NOT a shiny 3D render, NOT cute. NO ocean, sky, mountains, background, cliff, aquarium glass boundary or backdrop, NO fish or monsters, NO people, NO surrounding particles or bubbles, NO labels/logos/text/UI/watermark. True alpha transparency surrounds this single base. The station must look tiny and vulnerable once placed in vast dark water.
```

### Ribbon / gulper eel

```text
Use case: stylized-concept. Asset type: single isolated original immense deep-sea gulper eel sprite, true transparent background. A terrifying extremely long ribbon-bodied abyssal predator in complete side profile facing LEFT. A blunt skeletal head at left with a deep hinged gulper-jaw and long needlelike teeth, almost blind recessed tiny eyes, ribbed translucent gill chambers, extraordinarily long slender tapering body trailing right in an elegant broad S curve, continuous torn sail fin along the spine, one thin lure filament. Full body and complete curling tail contained with 5% transparent margins, panoramic wide composition approx 3:1. Detailed painterly pixel-art consistent with a mature dark undersea indie game, nuanced organic texture, subtle scaled and scarred leathery anatomy. Dark slate blue and cold green-black body, faint pale cyan rim light on upper ridges, soft sparse tiny photophores rather than bright stripes. Body must be visually distinct from a thick armored shark/dragon: narrow translucent serpentine gulper with uncanny elastic anatomy. Lovecraftian thalassophobia; evoke enormous hostile ocean fauna in Subnautica and Barotrauma while using original anatomy, no copying exact creatures or game assets. Genuine transparent alpha around the body and through fin gaps. No water, no fog, no glow on a backdrop, no particles, no scenery, no ground shadow, no text, no borders/logos. Not cute, not cartoon or flat vector shapes, no gore.
```

### Cathedral medusa

```text
Use case: stylized-concept. Asset type: a single isolated colossal deep-sea jellyfish creature sprite, genuine transparent alpha background. Original unsettling cathedral medusa from the deepest ocean: a tall elongated irregular ribbed bell resembling a translucent ancient organic cathedral, a thick central suspended visceral body, long ragged draping oral arms and dozens of fine serpentine tentacles trailing downward. Ribbed hood has a muted violet-blue inner texture and a sparse ring of very tiny sickly cold green photophores, NO eyes or human face. Full body front/three-quarter view, wide domed bell in upper third, long tentacles in lower two-thirds, appendages asymmetrical and all comfortably inside 6% transparent margin. Detailed painterly pixel art, mature retro underwater horror game asset with crisp tiny pixel clusters and subtle material shading, not a flat cartoon jellyfish or neon lamp. Dark indigo, oxidized teal and almost black translucent tissue, faint cold top-left highlights, very restrained inner luminescence. Immense alien marine animal, quietly frightening, Lovecraftian thalassophobia inspired by the feel of Subnautica and Barotrauma but with wholly original design. True alpha transparency around and between tentacles; NO water, background, backdrop, halo outside body, particles, ocean floor, text/logos/border/UI; NO cute expressions, no gore.
```

### Armored crustacean

```text
Use case: stylized-concept. Asset type: a single isolated original giant abyssal crustacean predator sprite, genuine transparent background. An immense alien deep-sea armored arthropod, broad asymmetric horseshoe-crab-like segmented carapace, rugged barnacle-encrusted slate armor plates, eight long sharp jointed legs splaying outward and downward, two enormous unequal spiked forelimbs, small recessed clustered cold eyes beneath shell rim and a hidden circular mouth between feelers. View front three-quarter with head oriented toward LEFT; all legs, claws and tail spines must fit with 6% transparent margin. Low wide crouched silhouette approx 1.7:1 width to height, biological rather than a robotic mech; original hostile abyssal fauna. Detailed painterly pixel-art indie game creature with small crisp pixel clusters, rich worn shell texture, cold dark blue-black and muted rust/sea-green with very faint highlights from upper left. Shadowed intimidating anatomy, convincingly huge marine predator in the mood of Barotrauma and Subnautica, not a copy of their exact assets/species. True alpha transparent space between limbs and around creature. NO surrounding water, scenery, background, floor, backdrop, particles, artificial halo or cast shadow, text/logo/UI/border. Not a colourful crab, not cute, not vector art, no gore.
```

## Micro-city revision (0.2.0)

`hadal-city-seabed.png` was generated with the built-in `imagegen` tool on
2026-10-30. It replaces the small station sprite in both build targets: the
city, heavy foundations, lighting and textured seafloor are one coherent
illustration. The original `hadal-station.png` remains as a previous source
asset, excluded from the current bundles.

The pressure dome, moving highlights and defensive effects are drawn in Swift.
The shared layout constrains every creature to open water above the dome and
seabed, and the renderer clips anatomy outside the protected city volume.
No game images or models are included.

### Exact micro-city generation prompt

```text
Use case: stylized-concept.
Asset type: a finished original landscape background painting for a native macOS deep-ocean screensaver, full landscape 16:10 composition. The image itself, no UI.
Primary request: a substantial UNDERWATER MICRO-CITY firmly built on a richly detailed abyssal ocean floor. Monumental retro-futurist science-fiction architecture, with Art Deco / brutalist civic towers and heavy industrial foundations, elegant and believable, a real settlement rather than a single capsule. Mature detailed painterly pixel art, small deliberate pixel clusters and crisp textured environmental illustration, cohesive cinematic indie-game-quality artwork. ORIGINAL architecture, no branding or game asset copies.
Composition is important: the city fills roughly x=18%..82%, y=36%..78%, approximately TWO THIRDS of the picture width, in the centre/lower centre. A large multi-block settlement with 12-20 different structures: tall central inhabited stepped towers, several shorter terraced apartment blocks, massive reactor/service halls, narrow bridges and skywalks, an access boulevard, pressure locks and maintenance docks, small exterior lamps and many tiny warm windows that communicate human scale. Architecture uses strong vertical and stepped forms, dark basalt/steel and pale worn concrete, embedded structural ribs, tiny streets/platforms between districts; NOT an arrangement of round tin cans or little submarines. Central tallest roof about y=36%, building foundations around y=76%. Leave adequate room above and around the entire city for an animated protective energy dome to be added in code; do NOT draw the energy dome, glass dome or shield yourself.
Landscape: the BOTTOM THIRD is a highly detailed visible deep-sea landscape. Dark basalt outcrops, uneven sediment and silt, weathered boulders, shallow erosion trenches, buried cables and pipelines, sparse pale benthic growth, long low shadows. Heavy foundations and retaining walls visibly meet and penetrate the seabed, no gaps or floating buildings. Seabed begins around y=72% across the frame, city foundation slightly lower at y=77%. Rocky foreground texture extends all the way to the bottom and both corners. Keep all ground/outcrops below y=70%, with no high side cliffs obstructing the water. The city has a convincing contact shadow and a restrained pool of blue/amber light on nearby sediment. Multiple layers of terrain give depth, not a flat black floor or simplistic polygon hills.
Water and atmosphere: open almost-black deep indigo ocean fills the UPPER THIRD and the space around the city. Absolutely no surface, sky, sun, moon, sunbeams or horizon. A tiny amount of blue-green ambient illumination makes distant water and rock readable, not a black featureless screen. Distant subtle dark water strata and scattering. City windows use restrained warm amber, a few muted cold cyan practical lights. The city and nearest seafloor details should be clearly readable on a normal monitor, but the setting remains at oppressive midnight depth. Calm, impressive, lonely and mysterious.
Constraints: NO creatures, fish, people, submarines, hovering objects, bubbles or particles; these will be animated separately. No emitted wide spotlight cones, flares, explosions or weapons firing (animated later). No text, logos, UI, map, border or watermark. Do not include a static shield: leave its volume empty so native code can animate it. Full coherent illustration, NOT an isolated object on transparent background, NOT a photo, NOT a glossy 3D product render, not cartoonish, not neon cyberpunk. Prioritize the solid city scale, architectural density, detailed textured seafloor and physical grounding.
```

