<?php

declare(strict_types=1);

namespace App;

use Symfony\Component\DependencyInjection\Attribute\Autowire;
use Twig\Extension\AbstractExtension;
use Twig\TwigFilter;

/**
 * Twig extension for formatting file sizes and byte counts.
 *
 * Provides filters for downloadable files, PDF brochures, and media attachments. The filter is
 * `format_file_size`, not `format_bytes`: Bolt core already has a `format_bytes` filter
 * (binary units, used by the admin), and of two filters with one name only one runs.
 *
 *   {{ record.attachment|file_size|format_file_size }}
 */
class FileSizeExtension extends AbstractExtension
{
    public function __construct(
        #[Autowire('%kernel.project_dir%')]
        private readonly string $projectDir,
    ) {
    }

    public function getFilters(): array
    {
        return [
            new TwigFilter('file_size', [$this, 'getFileSize']),
            new TwigFilter('format_file_size', [$this, 'formatBytes']),
        ];
    }

    /**
     * Formats a byte count into a human-readable string (e.g. "1.25 MB", "450 kB").
     *
     * Decimal (SI) units, as the labels say and as file managers show them: 1 kB = 1000 B.
     * Pass the separator of the page's language: {{ size|format_file_size(1, ',') }} → "1,3 MB".
     */
    public function formatBytes(int $bytes, int $decimals = 2, string $decimalPoint = '.'): string
    {
        if ($bytes <= 0) {
            return '0 B';
        }

        $units = ['B', 'kB', 'MB', 'GB', 'TB'];
        $power = 0;
        $value = (float) $bytes;
        // Compare the rounded value, so 999 999 B reads "1 MB", not "1000 kB".
        while (round($value, $decimals) >= 1000 && $power < count($units) - 1) {
            $value /= 1000;
            ++$power;
        }

        $number = number_format($value, $power === 0 ? 0 : $decimals, $decimalPoint, '');
        if (str_contains($number, $decimalPoint)) {
            $number = mb_rtrim(mb_rtrim($number, '0'), $decimalPoint);
        }

        return $number . ' ' . $units[$power];
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

        $publicDir = realpath($this->projectDir . '/public');
        $realPath = realpath($this->projectDir . '/public/' . mb_ltrim(rawurldecode($urlPath), '/'));

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
