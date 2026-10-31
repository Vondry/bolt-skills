<?php

declare(strict_types=1);

namespace App;

use Symfony\Component\DependencyInjection\Attribute\Autowire;
use Symfony\Component\HttpFoundation\RequestStack;
use Twig\Extension\AbstractExtension;
use Twig\TwigFunction;

/**
 * Twig extension providing the `locale_link()` function.
 *
 * Automatically prefixes internal URLs with the current request locale when
 * viewing non-default language versions (e.g. `/en/sluzby`), while keeping
 * links clean on the default language (e.g. `/sluzby`).
 *
 * Links often come from editable fields (buttons, cards), so only safe schemes pass:
 * http, https, mailto and tel. Anything else (`javascript:`, `data:`) becomes `#`.
 */
class LocaleLinkExtension extends AbstractExtension
{
    private const SAFE_SCHEMES = ['http', 'https', 'mailto', 'tel'];

    public function __construct(
        private readonly RequestStack $requestStack,
        #[Autowire('%app_locales%')]
        private readonly string $appLocales, // e.g. "cs|en"
        #[Autowire('%locale%')]
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
        $path = mb_trim($path);

        // Absolute URLs (and protocol-relative ones) are external — leave them untouched,
        // as long as the scheme is one a link may safely use.
        if ($this->isAbsoluteUrl($path)) {
            return $this->hasSafeScheme($path) ? $path : '#';
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

        // The localized homepage is '/{_locale}/' (Bolt's homepage_locale route, with the
        // slash); '/en' would cost a redirect.
        return '/' . $locale . $stripped;
    }

    /**
     * Detect whether the given string is a full URL rather than a site-relative path.
     */
    private function isAbsoluteUrl(string $path): bool
    {
        if ($this->scheme($path) !== null || str_starts_with($path, '//')) {
            return true;
        }

        return preg_match('~^[a-z0-9-]+(\.[a-z0-9-]+)+([/?#].*)?$~i', $path) === 1;
    }

    private function hasSafeScheme(string $url): bool
    {
        $scheme = $this->scheme($url);

        // Protocol-relative (//host) and bare domains (example.cz/page) have no scheme.
        return $scheme === null || in_array($scheme, self::SAFE_SCHEMES, true);
    }

    /**
     * The URL scheme, lower-cased, as a browser reads it: control characters and whitespace
     * inside the scheme ("java\tscript:") are ignored by browsers, so they are removed first.
     */
    private function scheme(string $url): ?string
    {
        $cleaned = (string) preg_replace('/[\x00-\x20]+/', '', $url);

        return preg_match('/^([a-z][a-z0-9+.-]*):/i', $cleaned, $match) === 1 ? mb_strtolower($match[1]) : null;
    }

    /**
     * Remove a leading configured locale segment from a path, if present.
     */
    private function stripLocale(string $path): string
    {
        $path = '/' . mb_ltrim($path, '/');
        $locales = implode('|', array_map(
            static fn (string $locale): string => preg_quote($locale, '#'),
            explode('|', $this->appLocales),
        ));

        $stripped = preg_replace('#^/(?:' . $locales . ')(?=/|$)#', '', $path);

        return $stripped === '' || $stripped === null ? '/' : $stripped;
    }
}
