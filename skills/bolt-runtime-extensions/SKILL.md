---
name: bolt-runtime-extensions
description: >-
  Use this skill whenever setting up, modifying, or verifying essential custom PHP
  Twig extensions under src/ in Bolt CMS. Deploys App\LocaleLinkExtension for automatic
  multi-language URL prefixing (locale_link), App\ImageDimensionsExtension for cached
  disk image resolution needed by PhotoSwipe (image_dimensions), and App\FileSizeExtension
  for human-readable download sizes (file_size, format_bytes), along with required
  bindings in config/services.yaml.
---

# Bolt CMS Runtime PHP Twig Extensions

While Bolt CMS provides powerful built-in Twig filters, real-world production projects require specialized runtime PHP extensions to handle multi-language URL routing, client-side lightbox animations, and file size formatting.

This skill standardizes the three battle-tested PHP extensions shared across production Bolt CMS repositories.

---

## 1. Overview of Shared Runtime Extensions

```text
src/
├── LocaleLinkExtension.php      # Function: locale_link(path)
├── ImageDimensionsExtension.php # Function: image_dimensions(imageUrl) [Cached]
└── FileSizeExtension.php        # Filters:  file_size(path), format_bytes(bytes)
```

| Extension | Twig Interface | Problem Solved |
| :--- | :--- | :--- |
| **`LocaleLinkExtension`** | `locale_link(path)` | **Multi-language link retention.** Automatically prefixes `/en` (or current locale) to internal links when viewing translated pages, while leaving default locale links clean (`/`). Prevents navigation from kicking users back to the default language. |
| **`ImageDimensionsExtension`** | `image_dimensions(imageUrl)` | **PhotoSwipe layout collapse.** PhotoSwipe 5 requires intrinsic `data-pswp-width` and `data-pswp-height` *before* opening slides. Bolt-managed images carry their dimensions in the media library (`image\|media` — read those first); static assets and images without a media entry lack them, so this extension reads disk headers, caches them via Symfony `CacheInterface`, and invalidates on file `mtime`. |
| **`FileSizeExtension`** | `|file_size`, `|format_bytes` | **Human-readable downloads.** Converts disk paths or file attachments into human-friendly strings (e.g. `2.45 MB`, `450 kB`, `0 B`) for PDF brochures, manuals, and catalogs. |

---

## 2. Extension Implementations & Logic

### A. `src/LocaleLinkExtension.php`
Ensures navigation menus and anchor links work predictably across all languages without forcing developers to hardcode `/en/` or write complex Twig conditions in every template.

```php
<?php

declare(strict_types=1);

namespace App;

use Symfony\Component\HttpFoundation\RequestStack;
use Twig\Extension\AbstractExtension;
use Twig\TwigFunction;

/**
 * Twig extension providing the `locale_link()` function.
 *
 * Automatically prefixes internal URLs with the current request locale when
 * viewing non-default language versions (e.g. `/en/sluzby`), while keeping
 * links clean on the default language (e.g. `/sluzby`).
 */
class LocaleLinkExtension extends AbstractExtension
{
    public function __construct(
        private readonly RequestStack $requestStack,
        private readonly string $appLocales, // e.g. "cs|en"
        private readonly string $defaultLocale, // e.g. "cs"
    ) {
    }

    public function getFunctions(): array
    {
        return [
            new TwigFunction('locale_link', [$this, 'localeLink']),
        ];
    }

    /**
     * Normalize a path so it matches the current request locale: strip any existing
     * locale prefix and re-add the current one, or none when on the default locale.
     */
    public function localeLink(string $path): string
    {
        // Absolute URLs (and protocol-relative ones) are external — leave them untouched.
        if ($this->isAbsoluteUrl($path)) {
            return $path;
        }

        // Pure fragment (e.g. "#kontakt") or query string — keep it relative to the
        // current page; prepending "/" would force a jump back to the homepage.
        if ($path !== '' && ($path[0] === '#' || $path[0] === '?')) {
            return $path;
        }

        $request = $this->requestStack->getCurrentRequest();
        $locale = $request?->getLocale() ?: $this->defaultLocale;

        $stripped = $this->stripLocale($path);

        if ($locale === $this->defaultLocale) {
            return $stripped === '' ? '/' : $stripped;
        }

        return '/' . $locale . ($stripped === '/' ? '' : $stripped);
    }

    /**
     * Detect whether the given string is a full URL rather than a site-relative path.
     */
    private function isAbsoluteUrl(string $path): bool
    {
        if (parse_url($path, PHP_URL_SCHEME) !== null || str_starts_with($path, '//')) {
            return true;
        }

        return preg_match('~^[a-z0-9-]+(\.[a-z0-9-]+)+([/?#].*)?$~i', $path) === 1;
    }

    /**
     * Remove a leading configured locale segment from a path, if present.
     */
    private function stripLocale(string $path): string
    {
        $path = '/' . mb_ltrim($path, '/');

        $stripped = preg_replace(
            '#^/(?:' . $this->appLocales . ')(?=/|$)#',
            '',
            $path
        );

        return $stripped === '' || $stripped === null ? '/' : $stripped;
    }
}
```

---

### B. `src/ImageDimensionsExtension.php`
Solves the PhotoSwipe v5 issue where images without Bolt Media database entries collapse to 0×0. It reads `getimagesize()` once from disk and caches the width/height in Symfony Cache, invalidating instantly if the file is replaced. It is the **fallback**: images picked from the media library already have their dimensions in the database (`image|media`).

```php
<?php

declare(strict_types=1);

namespace App;

use Symfony\Contracts\Cache\CacheInterface;
use Symfony\Contracts\Cache\ItemInterface;
use Twig\Extension\AbstractExtension;
use Twig\TwigFunction;

/**
 * Resolves intrinsic image dimensions from disk with Symfony Cache.
 *
 * PhotoSwipe lightbox requires intrinsic width and height before opening slides
 * to size and animate them without layout shifts.
 *
 * Images managed by Bolt store their dimensions in the media library; read those
 * first with the `media` filter — a database read, no disk access:
 *
 *     {% set media = image|media %}{{ media.width }}×{{ media.height }}
 *
 * This function is the fallback for images without a media entry: static theme
 * assets (`image_dimensions(asset('img/hero.jpg'))`) and image fields whose `media`
 * id is empty because the filename was set without picking the file from the
 * library (`image_dimensions(record.image.path)`). It inspects the file on disk and
 * caches the result for 1 week, invalidating when the file's mtime changes.
 */
class ImageDimensionsExtension extends AbstractExtension
{
    /** @var array<string, array{width: int, height: int}> */
    private array $dimensions = [];

    public function __construct(
        private readonly string $projectDir,
        private readonly CacheInterface $cache,
    ) {
    }

    public function getFunctions(): array
    {
        return [
            new TwigFunction('image_dimensions', [$this, 'getImageDimensions']),
        ];
    }

    /**
     * @return array{width: int, height: int}
     */
    public function getImageDimensions(string $imageUrl): array
    {
        return $this->dimensions[$imageUrl] ??= $this->resolveImageDimensions($imageUrl);
    }

    /**
     * @return array{width: int, height: int}
     */
    private function resolveImageDimensions(string $imageUrl): array
    {
        $empty = ['width' => 0, 'height' => 0];
        $urlPath = parse_url($imageUrl, PHP_URL_PATH);

        if (! is_string($urlPath) || $urlPath === '') {
            return $empty;
        }

        $publicDir = realpath($this->projectDir . '/public');
        $imagePath = realpath($this->projectDir . '/public/' . mb_ltrim(rawurldecode($urlPath), '/'));

        // Reject paths climbing out of public/ directory
        if (
            $publicDir === false
            || $imagePath === false
            || ! str_starts_with($imagePath, $publicDir . DIRECTORY_SEPARATOR)
        ) {
            return $empty;
        }

        // Cache across requests using file mtime to invalidate on asset updates
        $cacheKey = 'image_dimensions.' . hash('xxh128', $imagePath . '|' . filemtime($imagePath));

        return $this->cache->get($cacheKey, static function (ItemInterface $item) use ($imagePath, $empty): array {
            $size = @getimagesize($imagePath);

            if ($size === false) {
                // Short cache on failures in case the asset is being uploaded
                $item->expiresAfter(60);

                return $empty;
            }

            // 1 week cache on success
            $item->expiresAfter(604800);

            return ['width' => $size[0], 'height' => $size[1]];
        });
    }
}
```

---

### C. `src/FileSizeExtension.php`
Provides byte counting and readable formatting for file attachments and downloads. `|file_size` takes the file's public path (`field.path`) and, like `ImageDimensionsExtension`, refuses paths outside `public/`.

```php
<?php

declare(strict_types=1);

namespace App;

use Twig\Extension\AbstractExtension;
use Twig\TwigFilter;

/**
 * Twig extension for formatting file sizes and byte counts.
 *
 * Provides filters for downloadable files, PDF brochures, and media attachments:
 *   {{ record.attachment|file_size|format_bytes }}
 */
class FileSizeExtension extends AbstractExtension
{
    public function getFilters(): array
    {
        return [
            new TwigFilter('file_size', [$this, 'getFileSize']),
            new TwigFilter('format_bytes', [$this, 'formatBytes']),
        ];
    }

    /**
     * Formats a byte count into a human-readable string (e.g. "1.25 MB", "450 kB").
     */
    public function formatBytes(int $bytes, int $decimals = 2): string
    {
        if ($bytes <= 0) {
            return '0 B';
        }

        $units = ['B', 'kB', 'MB', 'GB', 'TB'];
        $power = min((int) floor(log($bytes, 1024)), count($units) - 1);
        $value = $bytes / (1024 ** $power);

        return mb_rtrim(mb_rtrim(number_format($value, $decimals), '0'), '.') . ' ' . $units[$power];
    }

    /**
     * Gets file size in bytes from the public directory.
     *
     * Pass the public path of the file — for Bolt file fields that is the field's `path`
     * (`record.brochure.path|file_size`, e.g. "/files/2026-01/manual.pdf"); the field's
     * plain string value is relative to files/ and would not resolve.
     *
     * @param string $filePath Public URL path (e.g. "/files/manual.pdf")
     * @return int File size in bytes, or 0 if file is missing/unreadable or outside public/
     */
    public function getFileSize(string $filePath): int
    {
        $urlPath = parse_url($filePath, PHP_URL_PATH);
        if (! is_string($urlPath) || $urlPath === '') {
            return 0;
        }

        $publicDir = realpath(__DIR__ . '/../public');
        $realPath = realpath(__DIR__ . '/../public/' . mb_ltrim(rawurldecode($urlPath), '/'));

        // realpath() resolves "..", so this also rejects paths climbing out of public/
        // (the value can come from editable content).
        if (
            $publicDir === false
            || $realPath === false
            || ! str_starts_with($realPath, $publicDir . DIRECTORY_SEPARATOR)
            || ! is_file($realPath)
        ) {
            return 0;
        }

        $size = filesize($realPath);

        return $size === false ? 0 : $size;
    }
}
```

---

## 3. Dependency Injection Configuration (`config/services.yaml`)

Add parameters and service definitions to `config/services.yaml`:

```yaml
parameters:
  locale: cs
  app_locales: cs|en

services:
  _defaults:
    autowire: true
    autoconfigure: true
    public: false
    bind:
      $locales: '%app_locales%'
      $defaultLocale: '%locale%'
      $projectDir: '%kernel.project_dir%'

  # Auto-discovers ImageDimensionsExtension and FileSizeExtension
  App\:
    resource: '../src/*'
    exclude:
      - ../src/DependencyInjection/
      - ../src/Entity/
      - ../src/Exception/
      - ../src/Kernel.php

  # Explicit service configuration for LocaleLinkExtension
  App\LocaleLinkExtension:
    arguments:
      $appLocales: '%app_locales%'
      $defaultLocale: '%locale%'
    tags: [ 'twig.extension' ]
```

---

## 4. Twig Usage Patterns & Recipes

### 1. Multi-Language Navigation Links (`locale_link`)
```twig
{# Automatically renders /sluzby on Czech locale, /en/sluzby on English locale #}
<nav>
    <a href="{{ locale_link('/') }}">Domů</a>
    <a href="{{ locale_link('/sluzby') }}">Služby</a>
    <a href="{{ locale_link('/#kontakt') }}">Kontakt</a>
</nav>
```

### 2. PhotoSwipe Lightbox with Intrinsic Dimensions (`image|media` first, `image_dimensions` as fallback)
```twig
{# PhotoSwipe needs width and height up front to calculate smooth zoom animations.
   Media-library images: dimensions from the database. Others: cached disk probe. #}
{% set media = record.image|media %}
{% set size = media and media.width
    ? { width: media.width, height: media.height }
    : image_dimensions(record.image.path) %}
<div class="photoswipe-gallery">
    <a href="{{ record.image.path }}"
       class="photoswipe-gallery__link"
       data-pswp-width="{{ size.width }}"
       data-pswp-height="{{ size.height }}">
        <img src="{{ record.image|thumbnail(400, 300) }}" alt="{{ record.image.alt|default(record|title) }}">
    </a>
</div>

{# Static theme asset (no media entry at all) #}
{% set hero = image_dimensions(asset('img/hero.jpg')) %}
```
`components/ui/picture.twig` from `bolt-theme-templates` implements the same order of preference (`pswp: true`).

### 3. File Downloads with Formatted Size (`field.path|file_size|format_bytes`)
```twig
{% if record.pdf_brochure is defined and record.pdf_brochure is not empty %}
    {% set bytes = record.pdf_brochure.path|file_size %}
    <a href="{{ record.pdf_brochure.path }}" download class="btn btn-secondary">
        <span>Stáhnout katalog (PDF{{ bytes > 0 ? ', ' ~ bytes|format_bytes : '' }})</span>
    </a>
{% endif %}
```
Pass the field's `path` (the public URL such as `/files/2026-01/catalog.pdf`); the field's plain string value is relative to `files/` and would report `0 B`.

---

## 5. Automated Scaffolding & Verification Runbook

### Automatic Installation
To deploy all three extensions and configure `config/services.yaml` in one command:
```bash
./skills/bolt-runtime-extensions/scripts/scaffold.sh [project-root] [--force]
```
Existing `src/*Extension.php` files are kept unless `--force` is given. `LocaleLinkExtension` is needed on every site (the menu, template and cookie-banner examples call `locale_link()`); remove `ImageDimensionsExtension` / `FileSizeExtension` when the site has no galleries / downloads (the verification then reports a warning, which the site plan lists as expected).

### Verification Script
Run the automated test suite from the project root:
```bash
./skills/bolt-runtime-extensions/scripts/verify.sh
```

The script verifies:
1. `src/LocaleLinkExtension.php` exists, passes PHP syntax check (`php -l`), and provides `locale_link`.
2. `src/ImageDimensionsExtension.php` exists, provides `image_dimensions`, and integrates with `CacheInterface`.
3. `src/FileSizeExtension.php` exists and provides `file_size` and `format_bytes`.
4. `config/services.yaml` has `App\LocaleLinkExtension` registered with `$appLocales` and `$defaultLocale`.
5. Symfony container compiles (`bin/console lint:container`) and all functions/filters appear in `bin/console debug:twig`.

---

## 6. Common Pitfalls & Security Safeguards

| Pitfall | Risk / Symptom | Solution |
| :--- | :--- | :--- |
| **Path Traversal in `ImageDimensionsExtension`** | Malicious users input `../../../../etc/passwd`. | `realpath()` check enforces `$imagePath` starts with `$publicDir . DIRECTORY_SEPARATOR`. |
| **Bypassing Symfony Cache** | Calling `getimagesize()` on every request hits disk I/O and degrades TTFB. | Cached for 1 week using `xxh128` hash key combining image path and `filemtime`. |
| **Mismatched constructor args in `services.yaml`** | Container compilation fails with `Cannot autowire service App\LocaleLinkExtension`. | Explicitly configure `$appLocales: '%app_locales%'` and `$defaultLocale: '%locale%'`. |
| **Fragment jumping across locales** | `locale_link('#kontakt')` prepending `/` forces home reload. | Explicit check for `$path[0] === '#'` leaves local page anchors untouched. |
| **`image_dimensions()` for every image** | A disk read per image although the media library already stored the size. | `{% set media = image\|media %}` first; `image_dimensions(image.path)` only without a media entry. |
| **`record.file\|file_size`** | Always `0 B`: the field value is relative to `files/`. | `record.file.path\|file_size`. |
