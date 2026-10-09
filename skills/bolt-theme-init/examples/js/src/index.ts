// Theme client scripts — bundled by Rollup into js/app.js.
// Keep only the modules the site plan needs; each one is inert when its markup is absent.
import './auto-scroll';      // anchor scrolling below the sticky header ([data-sticky-header])
import './menu';             // dropdown accordions + mobile drawer/collapse menu
import './locale-switcher';  // multilingual sites: keeps scroll, query and hash across a switch ([data-locale-switch])
import './photoswipe';       // galleries: PhotoSwipe 5 lightbox (.photoswipe-gallery) — remove with the npm dependency if unused
// import './cookie-consent'; // added by bolt-cookie-consent's scaffold when the site uses tracking
