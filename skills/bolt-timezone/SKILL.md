---
name: bolt-timezone
description: >-
  Use this skill whenever setting, configuring, or verifying the timezone
  (specifically Europe/Prague) in a Bolt CMS repository. Aligns all execution
  layers—config/bolt/config.yaml, src/Kernel.php boot override, Docker php.ini
  configurations, and compose.yaml environment—to prevent the critical Bolt CMS
  date-shifting bug on record saves.
---

# Bolt CMS Timezone Configuration (Europe/Prague)

In Bolt CMS websites operating in the Czech Republic and Central Europe, setting the timezone consistently is critical. Failing to align the timezone across all application and server layers causes a subtle but severe date corruption bug in Bolt's content editor.

This skill details the architectural root cause, the four required configuration places, and how to verify timezone parity across development, Docker, and production.

---

## 1. The Core Problem: The Bolt CMS Date-Shifting Bug

> [!CAUTION]
> **If PHP's runtime timezone and Bolt's configured `timezone` do not match, every save in the Bolt backend shifts publish dates by the timezone offset!**

### Why this happens:
1. **Wall-time storage:** Bolt maps its dates (`publishedAt`, `depublishedAt`, `createdAt`, `modifiedAt`) as Doctrine `datetime` columns (`Types::DATETIME_MUTABLE`). They store the date and time **without a zone**: whatever PHP's default timezone says is "now" is what lands in the database.
2. **Admin Display:** The Bolt Admin panel displays and accepts date inputs formatted in the timezone configured in `config/bolt/config.yaml` (`timezone: Europe/Prague`).
3. **Normalization & Conversion:** During record persistence and form normalization, Bolt converts date strings back into `DateTime` objects using PHP's current runtime timezone (`date_default_timezone_get()`).
4. **The Glitch:**
   If PHP's runtime timezone defaults to `UTC` (standard in bare Linux, Docker, or unconfigured PHP) while `config/bolt/config.yaml` is set to `Europe/Prague`:
   - An editor opens an article with publish date `14:00` Prague time.
   - On save the form value is read in one zone and written back in the other, so it moves by the offset: +1h (CET, winter) or +2h (CEST, summer).
   - After saving the article 3 times in the admin, the publish date has shifted forward by **6 hours**, potentially pushing the article into the future and unpublishing it!

> [!WARNING]
> **Changing the zone of a live site moves every stored date.** Because the database holds wall time without a zone, switching PHP from `UTC` to `Europe/Prague` makes every existing `14:00` (meant as UTC) display as `14:00` Prague time — one or two hours off. Before changing a site that already has content, decide: shift the stored values once (`UPDATE … SET published_at = published_at + INTERVAL …`, per DST period), or accept the offset on old records. New sites have nothing to migrate.
>
> Wall time also repeats one hour each October (DST end): two records saved at 02:30 in that hour cannot be ordered by the stored value. Harmless for publishing, worth knowing for logs.

**Other zones:** the skill uses `Europe/Prague` as the house default. For another zone, use the same value in every layer below and run the verification with `--timezone=Area/City`.

**The rule:** The timezone must be configured identically to `Europe/Prague` across all layers so that `date_default_timezone_get()` and Bolt's configured timezone never diverge.

---

## 2. The Four Places Where Timezone Must Be Set

Across production Bolt projects, timezone is configured at four distinct layers:

```text
├── config/bolt/config.yaml         # Layer 1: Bolt CMS Twig & Admin display
├── src/Kernel.php                  # Layer 2: Symfony / PHP runtime Kernel boot override
├── docker/php/conf.d/              # Layer 3: PHP engine configuration (CLI & FPM)
│   ├── bolt.dev.ini
│   └── bolt.prod.ini
└── compose.yaml                    # Layer 4: Container OS environment (MariaDB/MySQL)
```

---

### Layer 1: Bolt CMS Configuration (`config/bolt/config.yaml`)

Uncomment or set the `timezone` directive under the general configuration block:

```yaml
# config/bolt/config.yaml

# Set the timezone to be used on the website. For a list of valid timezone
# settings, see: http://php.net/manual/en/timezones.php
timezone: Europe/Prague
```

* **Purpose:** Instructs Bolt's admin editor, Twig datetime formatters, and date fields to use Czech local time.

> [!NOTE]
> **Why `config/packages/twig.yaml` (`twig.date.*`) does NOT work in Bolt CMS:**
> In standalone Symfony, developers often set default date formats in `config/packages/twig.yaml` under `twig.date.format` and `twig.date.timezone`. 
> 
> In Bolt CMS, this is **ignored**. Bolt's `Bolt\Twig\FieldExtension` explicitly overrides Twig's native `|date` filter:
> ```php
> public function getDate(Environment $twig, $date, $format = null, $timezone = null): string
> {
>     if ($format === null && ! $date instanceof DateInterval) {
>         $format = $this->config->get('general/date_format', null);
>     }
>     if ($timezone === null) {
>         $timezone = $this->config->get('general/timezone', null);
>     }
>     return $twig->getExtension(CoreExtension::class)->formatDate($date, $format, $timezone);
> }
> ```
> Because Bolt's `GeneralParser` always defaults `date_format` (`F j, Y H:i`) and `timezone` (`UTC` or configured value), `$format` and `$timezone` are never null when passed to Twig's formatter. Bolt intercepts every `{{ record.date|date }}` call and injects the values from `config/bolt/config.yaml`.
> 
> Therefore, to change the default date format or timezone in Twig, configure it directly in `config/bolt/config.yaml`:
> ```yaml
> # config/bolt/config.yaml
> timezone: Europe/Prague
> date_format: 'j. n. Y H:i' # or 'j. n. Y' for Czech dates without time
> ```
> This centrally controls:
> 1. Twig's `|date` filter when invoked without arguments (`{{ record.publishedAt|date }}`).
> 2. Twig's `|localdate` filter (localized using Carbon and active request locale).
> 3. Bolt Backend Admin listing columns and edit forms.
>
> It does **not** affect REST/GraphQL API output: API Platform serializes dates itself (ISO 8601 with offset), independent of these Twig settings.

---

### Layer 2: Application Kernel Override (`src/Kernel.php`)

Ensure `src/Kernel.php` extends `Bolt\Kernel` and overrides the `boot()` method to explicitly set PHP's default timezone:

```php
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
```

* **Why this is critical:**
  - In many deployment environments (shared hosting, CI/CD runners, CLI scripts, developer machines), developers or runners may not have access to alter global `php.ini`.
  - Overriding `Kernel::boot()` guarantees that the moment the Symfony application boots—whether serving web traffic via `public/index.php` or running CLI commands via `bin/console`—PHP's runtime timezone is set to `Europe/Prague` before any entity or service logic executes.

---

### Layer 3: PHP INI Directives (`docker/php/conf.d/`)

If the project uses Docker or custom PHP configuration drop-in directories, set `date.timezone` in both development and production configurations:

#### `docker/php/conf.d/bolt.dev.ini`
```ini
apc.enable_cli = 1
date.timezone = Europe/Prague
session.auto_start = Off
short_open_tag = Off
```

#### `docker/php/conf.d/bolt.prod.ini`
```ini
apc.enable_cli = 1
date.timezone = Europe/Prague
session.auto_start = Off
short_open_tag = Off
```

* **Purpose:** Sets the baseline engine timezone for PHP-FPM worker pools and CLI processes before scripts start, eliminating PHP runtime notices about unset timezone.

---

### Layer 4: Container Environment (`compose.yaml` / `docker-compose.yml`)

Under database services (MariaDB / MySQL), set the container's `TZ` environment variable:

```yaml
# compose.yaml
services:
  database: # or <project>-mariadb, etc.
    image: mariadb:11.4   # an LTS release; 10.4 reached end of life in 2024
    environment:
      # Local development container only — never reuse these values on a server.
      MYSQL_ROOT_PASSWORD: dev_root
      MYSQL_DATABASE: bolt_db
      MYSQL_USER: bolt_user
      MYSQL_PASSWORD: dev_password
      TZ: "Europe/Prague"
      LANG: "en_US.UTF-8"
```

* **Purpose:** Ensures the database server clock, `NOW()`, `CURRENT_TIMESTAMP`, and MySQL error/query logs match the application's local Prague timestamps.

---

## 3. Template & Content Contexts (Best Practices)

When generating machine-readable or public summaries containing timestamps (e.g. `llms.txt.twig`, transactional emails, opening hours):
* Explicitly state the timezone in the copy to remove ambiguity:
  > *"Times are local time in Prague (Europe/Prague)."*

---

## 4. Step-by-Step Implementation Checklist

1. **Update `config/bolt/config.yaml`:**
   Change `# timezone: UTC` or existing setting to `timezone: Europe/Prague`.
2. **Check or create `src/Kernel.php`:**
   If `src/Kernel.php` is missing or does not override `boot()`, update it to extend `Bolt\Kernel` and call `date_default_timezone_set('Europe/Prague')` in `boot()`.
3. **Update Docker INI files:**
   If `docker/php/conf.d/` exists, verify `date.timezone = Europe/Prague` is present in `bolt.dev.ini` and `bolt.prod.ini`.
4. **Update Docker Compose:**
   If `compose.yaml` has a database container, add `TZ: "Europe/Prague"`.
5. **Clear Symfony Cache:**
   Run `bin/console cache:clear` so the compiled container recognizes any updated configuration.
6. **Verify:**
   Run the verification script (see below).

---

## 5. Automated Verification Script

Run the automated verification script from your project root:

```bash
vendor/tomvondracek/bolt-skills/skills/bolt-timezone/scripts/verify.sh
```

### What the script checks:
1. `[1/5]` **Bolt Config:** Confirms `config/bolt/config.yaml` has `timezone: Europe/Prague` active (not commented out).
2. `[2/5]` **Kernel Override:** Confirms `src/Kernel.php` extends `BoltKernel`, defines `const TIMEZONE = 'Europe/Prague'`, and calls `date_default_timezone_set(self::TIMEZONE)` in `boot()`.
3. `[3/5]` **Docker INI:** Validates `docker/php/conf.d/bolt.dev.ini` and `bolt.prod.ini` if present.
4. `[4/5]` **Docker Compose:** Checks for `TZ: "Europe/Prague"` on database containers in `compose.yaml` / `docker-compose.yml`.
5. `[5/5]` **Runtime Boot Check:** Boots the `App\Kernel` in CLI mode (with cache, build and log folders in a temporary directory, so nothing is written to the project) and asserts that `date_default_timezone_get()` returns the expected zone.

Every check compares against `Europe/Prague`, or the zone given with `--timezone=Area/City` (or `BOLT_TIMEZONE`).
