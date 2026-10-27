<?php

declare(strict_types=1);

/*
 * Static pages in the sitemap (bolt-extension-setup section 2.4), run by verify.sh from the
 * project root.
 *
 * tomvondracek/bolt-sitemap lists a static page through its TemplateController route: a route
 * without parameters for the default locale, and a `<name>_locale` twin (path `/{_locale}/…`,
 * same templateName) for the other languages. Prints one line per page in
 * `static-pages/`: `OK|…`, `WARN|…` or `FAIL|…`.
 *
 * Usage: php static-pages.php <theme dir> <app_locales> <sitemap config file>
 */

use Symfony\Component\Yaml\Yaml;
[, $themeDir, $appLocales, $sitemapConfig] = $argv + [null, '', '', ''];
if (! is_file('vendor/autoload.php')) {
    echo "WARN|vendor/autoload.php missing — run composer install to check the static routes\n";
    exit;
}
require 'vendor/autoload.php';

// Routes of the project: config/routes.yaml and config/routes/*.yaml, except the extensions' copies.
$routes = [];
foreach (array_merge(['config/routes.yaml'], glob('config/routes/*.yaml') ?: []) as $file) {
    if (! is_file($file) || str_starts_with(basename($file), 'extension_')) {
        continue;
    }
    try {
        $parsed = Yaml::parseFile($file, Yaml::PARSE_CUSTOM_TAGS);
    } catch (Throwable $e) {
        echo "FAIL|$file is not valid YAML: {$e->getMessage()}\n";
        continue;
    }
    foreach (is_array($parsed) ? $parsed : [] as $name => $route) {
        if (! is_array($route) || ! isset($route['path']) || ! is_string($route['path'])) {
            continue;
        }
        $controller = $route['controller'] ?? $route['defaults']['_controller'] ?? '';
        $template = $route['defaults']['templateName'] ?? null;
        if (is_string($controller) && str_contains($controller, 'TemplateController') && is_string($template)) {
            $routes[] = ['name' => (string) $name, 'path' => $route['path'], 'template' => $template];
        }
    }
}

$excluded = [];
if (is_file($sitemapConfig)) {
    $config = Yaml::parseFile($sitemapConfig);
    $excluded = is_array($config['exclude_static_routes'] ?? null) ? $config['exclude_static_routes'] : [];
}
$multilingual = count(array_filter(array_map('trim', explode('|', $appLocales)))) > 1;

foreach (glob($themeDir . '/static-pages/*.twig') ?: [] as $file) {
    $template = 'static-pages/' . basename($file);
    if (str_starts_with(basename($file), '_')) {
        continue; // a partial, not a page
    }
    $base = $twin = null;
    foreach ($routes as $route) {
        if ($route['template'] !== $template) {
            continue;
        }
        preg_match_all('/\{([^}]+)\}/', $route['path'], $vars);
        if ($vars[1] === []) {
            $base ??= $route;
        } elseif ($vars[1] === ['_locale']) {
            $twin ??= $route;
        }
    }

    if ($base === null && $twin !== null) {
        echo "FAIL|$template has only the locale route {$twin['path']} — add a route without parameters for the default locale; the sitemap lists a static page through it (section 2.4)\n";
    } elseif ($base === null) {
        echo "FAIL|$template has no TemplateController route in config/routes.yaml — the page is neither served nor in the sitemap (section 2.4)\n";
    } elseif (in_array($base['name'], $excluded, true)) {
        echo "OK|$template → {$base['path']} (route {$base['name']}), left out of the sitemap by exclude_static_routes\n";
    } elseif ($multilingual && $twin === null) {
        echo "WARN|$template → {$base['path']} has no {$base['name']}_locale twin (path /{_locale}…, same templateName) — its other languages are not in the sitemap (section 2.4)\n";
    } else {
        echo "OK|$template → {$base['path']}" . ($twin !== null ? " + {$twin['path']}" : '') . " in the sitemap\n";
    }
}
