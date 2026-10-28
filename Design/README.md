# Design

- `Carbon.icon`: the macOS app icon, an Icon Composer document. Drop it into the Xcode project (target → App Icon) instead of an asset catalog `AppIcon`.
- `mark.svg`: the "Graphene, ultra soft" mark on a 1024 grid, source for the icon layer and the website's flat black/white logo. Geometry comes from `.scratch/carbon-v1/prototypes/icon-board/`.

The icon follows Apple's macOS 26 app icon template (1024 px canvas, 128 px keyline grid, 820 px circle for round artwork): the mark is one filled compound path, scaled 1.36x in `icon.json` so it spans 766 px (128 to 896 keylines, about 75% of the canvas), with Liquid Glass on (specular, neutral shadow, 15% translucency). Default is a black mark on the System Light background, Dark a white mark on System Dark, and the tinted/clear (mono) appearances use a white mark that the system tints. Edit `icon.json` and the SVG by hand or in Icon Composer, but re-check `Assets/` after an Icon Composer save.
