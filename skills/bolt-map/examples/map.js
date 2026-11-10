/**
 * js/map.js — bolt-map: 3D city map with a pin, without cookies or consent.
 *
 * A native ES module that components/ui/map.twig loads on pages with a map. It is not part of
 * js/app.js: the Rollup bundle is one IIFE file, and MapLibre would add about 450 kB to every
 * page. Nothing below runs until a map comes close to the viewport.
 *
 * Markup: [data-map] with data-map-lat, data-map-lng, data-map-zoom and data-map-i18n (the
 * translated control labels as JSON). The pin takes the element's text colour (`text-accent`).
 * The labels follow <html lang>, so every locale of the site works without a setting here.
 */
const STYLE_URL = 'https://tiles.openfreemap.org/styles/liberty';
const PITCH = 60;
const BEARING = -25;
const DEFAULT_ZOOM = 17;
const DEFAULT_LANGUAGE = 'cs';

// Keeps the ?v= cache buster of this module on the files it loads.
const assetUrl = (path) => new URL(`${path}${new URL(import.meta.url).search}`, import.meta.url).href;

let library;

function loadStylesheet() {
  return new Promise((resolve, reject) => {
    const link = document.createElement('link');
    link.rel = 'stylesheet';
    link.href = assetUrl('./maplibre/maplibre-gl.css');
    link.onload = resolve;
    link.onerror = reject;
    document.head.append(link);
  });
}

function loadLibrary() {
  library ??= Promise.all([
    import(assetUrl('./maplibre/maplibre-gl.js')),
    loadStylesheet(),
  ]).then(([maplibregl]) => {
    // The files are renamed to .js, which MapLibre's own worker lookup would not find.
    maplibregl.setWorkerUrl(assetUrl('./maplibre/maplibre-gl-worker.js'));

    return maplibregl;
  });

  return library;
}

// Place names in the language of the page, then the local name. Road numbers (`ref`) stay as they are.
function localiseLabels(map, language) {
  for (const layer of map.getStyle().layers) {
    const field = layer.type === 'symbol' && layer.layout?.['text-field'];

    if (field && JSON.stringify(field).includes('name:latin')) {
      map.setLayoutProperty(layer.id, 'text-field', [
        'coalesce',
        ['get', `name:${language}`],
        ['get', 'name:latin'],
        ['get', 'name'],
      ]);
    }
  }
}

async function mount(element) {
  const center = [Number(element.dataset.mapLng), Number(element.dataset.mapLat)];
  const language = (document.documentElement.lang || DEFAULT_LANGUAGE).split('-')[0].toLowerCase();
  const pinColor = getComputedStyle(element).color;
  const { Map: MapLibreMap, Marker, NavigationControl } = await loadLibrary();

  const map = new MapLibreMap({
    container: element,
    style: STYLE_URL,
    center,
    zoom: Number(element.dataset.mapZoom) || DEFAULT_ZOOM,
    pitch: PITCH,
    bearing: BEARING,
    // The page keeps scrolling over the map; zooming needs Ctrl or ⌘, panning on touch two fingers.
    cooperativeGestures: true,
    locale: JSON.parse(element.dataset.mapI18n || '{}'),
  });

  map.addControl(new NavigationControl({ visualizePitch: true }));
  map.on('style.load', () => localiseLabels(map, language));
  new Marker({ color: pinColor }).setLngLat(center).addTo(map);
}

const observer = new IntersectionObserver((entries) => {
  for (const entry of entries) {
    if (!entry.isIntersecting) {
      continue;
    }

    observer.unobserve(entry.target);
    mount(entry.target).catch((error) => {
      // No WebGL or a blocked file: the empty box stays, with the directions button on it.
      console.warn('bolt-map: the map could not start', error);
    });
  }
}, { rootMargin: '300px' });

document.querySelectorAll('[data-map]').forEach((element) => observer.observe(element));
