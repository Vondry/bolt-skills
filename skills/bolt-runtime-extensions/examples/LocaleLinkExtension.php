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
