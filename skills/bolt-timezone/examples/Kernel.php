<?php

declare(strict_types=1);

namespace App;

use Bolt\Kernel as BoltKernel;

class Kernel extends BoltKernel
{
    /**
     * Must match `timezone` in config/bolt/config.yaml. Bolt stores dates in UTC and converts
     * them using PHP's default timezone as "local" time, while the admin shows them in the
     * configured timezone. If the two differ, every save shifts publish dates by the offset.
     */
    private const TIMEZONE = 'Europe/Prague';

    public function boot(): void
    {
        date_default_timezone_set(self::TIMEZONE);

        parent::boot();
    }
}
