<?php

declare(strict_types=1);

namespace App;

use Symfony\Component\DependencyInjection\Attribute\Autowire;
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
        #[Autowire('%kernel.project_dir%')]
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
