---
name: bolt-map
description: >-
  Adds a 3D city map with a pin to a Bolt CMS 6 theme, as the replacement for a Google Maps or
  Mapy.com embed: MapLibre GL JS with OpenFreeMap's hosted Liberty style, no API key, no cookies and
  no consent, so the map always shows. Labels and controls follow the page's language, light or
  dark follows the visitor's system, the pin takes the theme's accent colour, and the library loads only when a map
  comes into view. Use it when a site needs a location map, or when asked to replace Google Maps or
  remove a map from the cookie banner.
---

# Bolt CMS Location Map

A map that needs no cookie consent, so visitors never see a "load map" placeholder.

| What | How it follows the theme |
| :--- | :--- |
| 3D | Liberty style, tilted 60°, buildings raised from zoom 14 |
| Focus | Centred on the pin, starting close at zoom 17 so the visitor sees the place itself |
| Directions | A button on the map opens Google Maps with directions to the pin; an arrow that slides up and right on hover shows it leaves the site |
| Language | Place names and control labels follow `<html lang>`, for every locale in `app_locales`; Czech when the page sets none |
| Light or dark | The visitor's system setting, whatever the site itself does |
| Pin | The `text-accent` colour of the theme |
| Scrolling | The page keeps scrolling over the map; zooming needs Ctrl or ⌘, moving on touch two fingers |

Google Maps and Mapy.com iframes stay a job for `bolt-cookie-consent`'s placeholder. This skill
replaces them, so a site whose only reason for the banner was the map loses the banner too.

---

## Step 1: Get the Position

Ask for the place the pin marks: the business address or, without one, the centre of the city.
Convert it to coordinates and check them on a map before using them. Never guess them.

---

## Step 2: Scaffold

```bash
bash $SKILLS/bolt-map/scripts/scaffold.sh --lat=50.0755 --lng=14.4378
```

It keeps existing files and keys, so it can be repeated. It writes:

| File | Change |
| :--- | :--- |
| `js/map.js` | The map module ([`examples/map.js`](examples/map.js)) |
| `components/ui/map.twig` | The pure component ([`examples/map.twig`](examples/map.twig)) |
| `package.json` | `maplibre-gl`, the `build:map` script, and `build:map` as part of `prod` |
| `css/tailwind/index.css` | `@source not "../../js/maplibre";` and the map's light or dark rule |
| `theme.yaml` | `location:` with the coordinates and `zoom: 17` |

Merge the labels with the commands the scaffold prints. For a further locale, merge the English
catalog into `messages.<code>.xlf` and translate the targets.

---

## Step 3: Place the Map

```twig
{{ include('components/ui/map.twig', { class: 'mt-8' }) }}
```

It reads `theme.location`. For a site with several places, pass them from the page or container:

```twig
{{ include('components/ui/map.twig', { latitude: branch.lat, longitude: branch.lng, zoom: 16 }) }}
```

Remove the old Google Maps or Mapy.com embed and its `partials/_consent-embed.twig` include. A map
in a page section is enough; do not put it in the footer of every page, because each visit then
downloads the library and the tiles.

To change the height, edit `h-96` in the component. To change the pin, edit `text-accent`. To start
further out, lower `location.zoom` in `theme.yaml` (15 shows the town around the pin).

---

## Step 4: Privacy

There are no cookies to list, but the visitor's IP address reaches the tile host when the map loads.
Add the purpose when generating the privacy data (`bolt-cookie-consent`):

```bash
--purposes=web_operation,contact_form,map_display
```

Without `--embeds=google_maps` or `--embeds=mapy_com`, the map no longer counts towards the banner.
On an existing site, also remove those embeds' entries from `privacy:` in `theme.yaml` and increase
`config_version`.

---

## Step 5: Build

```bash
cd public/theme/<theme> && npm install && npm run prod && cd -
```

Bump `assets_version` in `theme.yaml`, then run `php bin/console cache:clear`. Upload `js/map.js` and
`js/maplibre/` with the rest of the theme. A site with the strict CSP of `bolt-security-hardening`
needs `connect-src https://tiles.openfreemap.org` and `img-src blob:`.

---

## Verification

```bash
bash $SKILLS/bolt-map/scripts/verify.sh
```

| Checks | Result |
| :--- | :--- |
| `js/map.js` and the component exist, the style is OpenFreeMap, nothing is stored in the browser, the wrapper has `isolate` | FAIL when not |
| The library is built under `js/maplibre/`, is part of `npm run prod`, stays out of `js/app.js` and out of Tailwind's scan | FAIL when not |
| Light or dark follows the visitor's system | FAIL when not |
| No Google Maps or Mapy.com embed remains | FAIL when not |
| Every locale's catalog has the map labels; a strict CSP allows the map | FAIL when not |
| Coordinates, zoom of at least 14, a template using the map, OpenFreeMap in the privacy data, `cooperativeGestures`, `pitch` | WARN when not |

Then open the page in a private window and confirm what only a browser can:

1. The map appears in 3D with the pin, without any banner or placeholder.
2. DevTools → Application shows no cookie or storage key from the map, and Network shows only the
   site and `tiles.openfreemap.org`.
3. Other pages do not request `js/map.js` or `js/maplibre/`.
4. On the second locale, zoom out: place names change (Vídeň / Vienna) and so do the button tooltips.
5. Switch the system between light and dark (or emulate it in DevTools → Rendering): the map follows
   and the pin keeps its colour, whatever the site's own theme does.

## Common Pitfalls

* **The map stays empty and the console shows a 403 or 404 for `.mjs`** → the files were copied
  without renaming. The `.htaccess` allowlist of `bolt-htaccess` serves `.js` in `js/`, not `.mjs`.
  Use `npm run build:map`.
* **MapLibre imported in `js/src/`** → the theme's Rollup output is a single IIFE file, so 450 kB
  lands on every page and the worker is not found. Keep it in `js/map.js`.
* **The map follows the site's theme toggle instead of the system** → `dark:` was used, and a theme can
  redefine it with `@custom-variant dark`. The rule in `css/tailwind/index.css` is plain
  `prefers-color-scheme` CSS for that reason, so keep it there.
* **"Use ⌘ + scroll to zoom" shows over the cookie banner or a sticky header** → the wrapper in
  `components/ui/map.twig` lost `isolate`. MapLibre puts that text at z-index 99999, and `isolate` keeps
  it inside the map. Do not raise the banner's z-index to compete with it.
* **The whole map is inverted, pin included** → the filter was put on the map element. It belongs on
  its `canvas`.
* **Tailwind's build is slow or the CSS grows** → `js/maplibre` is being scanned for classes.
* **The buildings look flat** → the zoom is below 14, or the style was changed from Liberty, which is
  the hosted style with a 3D buildings layer.
* **A street name appears in a foreign language** → the map data has no name in that language, so the
  label falls back to the local name. The data comes from OpenStreetMap.
* **The console warns `Image "atm" could not be loaded`** → the hosted Liberty style names a few icons
  its sprite does not contain. Those icons are simply not drawn, and the map works.
* **"© OpenStreetMap" was hidden** → the attribution is required by the data's licence. Keep it.
