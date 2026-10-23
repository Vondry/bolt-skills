<?php

declare(strict_types=1);

/*
 * Router for PHP's built-in server, used by verify.sh when BOLT_BASE_URL is not set:
 *   php -S 127.0.0.1:PORT -t public php-server-router.php
 * Serves existing files from public/ and sends everything else to Bolt's front controller.
 */

$path = rawurldecode((string) parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH));
if ($path !== '/' && is_file($_SERVER['DOCUMENT_ROOT'] . $path)) {
    return false;
}

$_SERVER['SCRIPT_FILENAME'] = $_SERVER['DOCUMENT_ROOT'] . '/index.php';
$_SERVER['SCRIPT_NAME'] = $_SERVER['PHP_SELF'] = '/index.php';

require $_SERVER['DOCUMENT_ROOT'] . '/index.php';
