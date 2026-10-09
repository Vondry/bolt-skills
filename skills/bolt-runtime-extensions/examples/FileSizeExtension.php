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
