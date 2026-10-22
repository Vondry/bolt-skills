<?php

declare(strict_types=1);

/*
 * Bolt Configuration Notices from the command line (bolt-build).
 *
 * Runs the checks of bolt/configuration-notices-widget — the "Bolt Configuration Notices" box on
 * the admin dashboard — without a browser, so an agent can resolve every notice before content is
 * entered (reserved field names, ambiguous slugs, slug `uses`, unknown field types, new
 * ContentTypes without a cache clear, …).
 *
 * Usage: php config-notices.php [--project=<dir>] [--base-url=http://127.0.0.1:8000] [--min=info|warning|danger]
 * Exit code: 0 = no notice at or above --min (default: warning), 1 = notices found, 2 = cannot run.
 */

$options = getopt('', ['project::', 'base-url::', 'min::']);
$project = realpath($options['project'] ?? getcwd()) ?: getcwd();
$baseUrl = rtrim($options['base-url'] ?? 'http://127.0.0.1:8000', '/');
$levels = ['info' => 1, 'warning' => 2, 'danger' => 3];
$min = $levels[$options['min'] ?? 'warning'] ?? 2;

// Deprecation notices of vendor code are not configuration notices.
error_reporting(E_ALL & ~E_DEPRECATED & ~E_USER_DEPRECATED);

if (! is_file($project . '/vendor/autoload.php')) {
    fwrite(STDERR, "vendor/autoload.php not found in {$project} (run composer install).\n");
    exit(2);
}
if (! is_dir($project . '/vendor/bolt/configuration-notices-widget')) {
    fwrite(STDERR, "bolt/configuration-notices-widget is not installed — nothing to check.\n");
    exit(2);
}

chdir($project);
require $project . '/vendor/autoload.php';
// The project's own environment (.env + .env.local), as the dashboard sees it.
(new Symfony\Component\Dotenv\Dotenv())->bootEnv($project . '/.env');

// The test environment exposes Bolt's private services (Config, FieldRepository) through
// `test.service_container` (framework.test: true in Bolt's framework.yaml). Only configuration is
// read: no request is handled and nothing is written to the database.
$kernel = new App\Kernel('test', true);
$kernel->boot();
$container = $kernel->getContainer()->get('test.service_container');

// The production SYMFONY_TRUSTED_HOSTS of .env would reject the local host of this synthetic request.
Symfony\Component\HttpFoundation\Request::setTrustedHosts([]);

// The checks read the current request (host, scheme) for the "local URL" and reachability checks.
$container->get('request_stack')->push(Symfony\Component\HttpFoundation\Request::create($baseUrl . '/bolt/'));
// Set by Bolt's Canonical service during a real request; the "logged in on another hostname"
// check compares them with the request URL, which is meaningless on the command line.
$_SERVER['CANONICAL_SCHEME'] ??= (string) parse_url($baseUrl, PHP_URL_SCHEME);
$_SERVER['CANONICAL_HOST'] ??= (string) parse_url($baseUrl, PHP_URL_HOST);

// Bolt sets this static on kernel.request; the field-type checks need it.
Bolt\Repository\FieldRepository::setEntityManager($container->get('doctrine.orm.entity_manager'));

$extension = new Bolt\ConfigurationNoticesWidget\Extension();
$extension->injectObjects(['manager' => null, 'query' => null, 'container' => $container]);
$results = (new Bolt\ConfigurationNoticesWidget\Checks($extension))->getResults();

if ($results === null) {
    fwrite(STDERR, "Bolt was not ready to run the checks.\n");
    exit(2);
}

$found = 0;
foreach ($results['notices'] as $notice) {
    $level = $levels[$notice['severity']] ?? 1;
    $text = static fn (?string $html): string => trim((string) preg_replace('/\s+/', ' ', html_entity_decode(strip_tags((string) $html), ENT_QUOTES)));
    printf("%-7s %s\n", strtoupper($notice['severity']), $text($notice['notice']));
    if ($text($notice['info']) !== '') {
        printf("        → %s\n", $text($notice['info']));
    }
    if ($level >= $min) {
        $found++;
    }
}

if ($results['notices'] === []) {
    echo "No Bolt configuration notices.\n";
}

exit($found > 0 ? 1 : 0);
