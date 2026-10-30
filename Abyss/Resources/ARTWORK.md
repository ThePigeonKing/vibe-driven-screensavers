# Abyss Station artwork

Three original illustrations were generated with the built-in `imagegen` tool
on 2026-10-30: `abyss-station.png` (background), `abyss-elder.png` and
`abyss-leviathan.png` (creatures with real alpha transparency). All are bundled
unchanged in both the preview app and the native screen saver. No API key,
network request or image generation is needed at runtime.

The scene evokes deep-ocean isolation and cosmic horror. Subnautica was a mood
reference supplied by the user; no game screenshots, models or other game
assets were used. Swift deforms the creature sprites in cached continuous
strips and draws searchlights, marine snow, bubbles and station light changes.
The renderer applies distance fades and masks at runtime, without modifying
the committed PNG files.
This independent project has no affiliation with Subnautica or its creators.

## Background: exact generation prompt

```text
Use case: stylized-concept.
Asset type: original background painting for an animated native macOS screensaver, landscape 16:10 composition. Deliver the artwork itself, no UI mockup.
Primary request: an exquisitely atmospheric dark deep-ocean research station scene evoking thalassophobia and cosmic horror. Subnautica-like sense of immense underwater depth and lonely human scale, original design, no copying any game's assets or logos. Mature painterly pixel art / detailed retro indie game environmental art, clean deliberate small pixel clusters and richly detailed mechanical surfaces, muted limited palette.
Composition: camera outside the base at a slightly elevated distant three-quarter view. Tiny isolated research habitat occupies the LEFT LOWER THIRD, approximately x=8%-43%, y=48%-77%, anchored on a rough basalt ledge. Pressure-resistant modular cylindrical steel rooms, ribbed pipes, small observation windows, a narrow antenna, a little docking gantry; corroded ivory and dark teal metal with very restrained warm amber windows and a couple dim cyan lamps. The ledge slopes down from bottom left and plunges into a seemingly bottomless chasm around x=48%. Some foreground dark rocks and thin deepwater vegetation only along the bottom left. All station modules fit in the image with comfortable margin. A sparse very distant rock face at far right dissolves in water. Two thirds of the image, especially center/right and upper half, are OPEN DARK OCEAN, near-black petrol blue with subtly visible muted teal depth layers, enormous negative space where animated leviathans will later pass. Dim distant vertical geological formations may be barely suggested, no strong horizon.
Lighting: absolutely no surface, sun, sky or bright waterline, no sun rays from above; truly deep midnight ocean. Very faint localized cyan haze surrounding the station. The windows and tiny fixed lights provide small warm human-scale focal points, but the station's steel and rock detail should still be readable. Darkness feels vast and oppressive, cinematic, melancholic and frightening. A quiet hint of abyssal green in distant water; not a bright turquoise tropical sea. Keep center/right water a fairly smooth dark uniform gradient with subdued pixelated texture so animated dark silhouettes can be composited naturally.
Animation constraints: NO creatures, no tentacles, no eyes, no fish, no bubbles, no falling particles, no dynamic spotlights or wide searchlight cones; those will be animated separately in Swift. Draw only architecture, geology, water and static practical tiny lights. NO humans, divers, submarines or foreground figures. NO text, letters, numbers, clocks, HUD, logos, watermark, border or framing. Detailed finished art, not simple rectangle geometry, not photorealistic, no glossy 3D render, no heavy blur, no dramatic flashes. Extremely dark ocean but enough tonal separation to read the scene on a normal monitor.
```

## Elder sprite: exact generation prompt

```text
Use case: stylized-concept. Asset type: a single isolated original sea-monster sprite for an atmospheric underwater game scene, genuine transparent background, nothing else. Primary request: an immense terrifying ancient abyssal cephalopod deity, Lovecraftian cosmic horror in an original design. Full body seen from the front in a slight three-quarter view, drifting vertically, with all appendages fitting comfortably inside the canvas. An irregular elongated, ridged, armored cranial mantle, scarred leathery skin, folds and encrusted gnarled plates, six tiny recessed sickly sea-green eyes set deep under jagged brows, an obscene bundle of 9-12 very long curling tapered tentacles hanging below the head and torso. Vestigial ragged membranous fins unfurl to either side like an ancient deepwater animal. Asymmetric, biologically convincing, oppressive and alien. No human torso, no human limbs, no costume or clothing. Composition: head around upper central third, webbed side fins in middle, tentacle tips trail to bottom. Full silhouette including fins and tentacles must be contained within image with a 5% transparent margin. Style: very detailed painterly pixel art matching a mature retro indie underwater environment, small crisp pixel clusters, organic shading, rich texture, not a vector illustration. Restrained dark petrol blue and decayed sea-green palette; soft cold light skims the upper left ridges, nearly black underside; enough subtle texture to read the anatomy without bright outlines. Menacing and solemn, NOT cute, NOT a cartoon squid or flat simple geometric shape, no neon, no bright eyes, no gore, no water background, no fog, no particles, no ground, no shadow on a backdrop, no border, no letters, no logos. True transparency around the creature and between tentacles. Tall full-body composition.
```

## Leviathan sprite: exact generation prompt

```text
Use case: stylized-concept. Asset type: a single isolated original abyssal leviathan sprite for a dark underwater game, genuine transparent background. Primary request: a colossal ancient deep-sea predator, original Lovecraftian marine horror, full length SIDE PROFILE facing LEFT. A long sinuous eel-like body with powerful massive armored head, tapering tail to the right, irregular dorsal spines and torn membranous fins, lateral gill slits, rows of coarse dark scales and barnacle scars. Head has a bony asymmetrical wedge-shaped skull and long narrow slightly open jaw with unsettling delicate teeth; several tiny recessed pale cold eyes above the jaw, four thin trailing chin barbels. Anatomy should feel plausible and horrifying in dark water rather than a dragon or toy fish. Composition: horizontal panoramic full body, roughly 3 times as wide as tall including fins, head on left quarter, tail curls slightly toward the right edge; every part fits within a 5% transparent margin. Style: detailed painterly pixel art for an atmospheric mature indie game, crisp tiny pixel clusters, nuanced organic texture, consistent with an intricate deep-ocean research base background. Dark muted blue-black, petrol green and slate palette, faint cold rim light on top-left ridges, underside almost black, no bright outlines, no neon, tiny restrained eyes. NOT cute, NOT cartoonish, NOT flat vector art, no simple triangular identical repeated fins, no water background, no fog or particles, no floor, no shadow outside creature, no text, no logo, no border, no human figures, no gore. Genuine alpha transparency surrounding entire creature.
```

