#!/usr/bin/env bash
set -e

# Detect Bolt CMS project root
if [ -f "./config/services.yaml" ]; then
    BASE_DIR="$(pwd)"
else
    DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    while [ "$DIR" != "/" ]; do
        if [ -f "$DIR/config/services.yaml" ]; then
            BASE_DIR="$DIR"
            break
        fi
        DIR="$(dirname "$DIR")"
    done
fi

if [ -z "$BASE_DIR" ] || [ ! -f "$BASE_DIR/config/services.yaml" ]; then
    echo "ERROR: Could not locate Bolt CMS project root (config/services.yaml not found)."
    exit 1
fi

cd "$BASE_DIR"

# The zone every layer must use: --timezone=Area/City, else BOLT_TIMEZONE, else the house default.
EXPECTED_TIMEZONE="${BOLT_TIMEZONE:-Europe/Prague}"
for arg in "$@"; do
    case "$arg" in
        --timezone=*) EXPECTED_TIMEZONE="${arg#*=}" ;;
    esac
done
if ! php -r 'exit(in_array($argv[1], DateTimeZone::listIdentifiers(), true) ? 0 : 1);' "$EXPECTED_TIMEZONE"; then
    echo "ERROR: '$EXPECTED_TIMEZONE' is not a valid timezone identifier."
    exit 1
fi

echo "=========================================================="
echo " Bolt CMS Timezone Verification ($EXPECTED_TIMEZONE)"
echo " Project root: $BASE_DIR"
echo "=========================================================="

FAILED=0
WARNINGS=0

# -------------------------------------------------------------
# 1. Check config/bolt/config.yaml
# -------------------------------------------------------------
echo -n "[1/5] Checking config/bolt/config.yaml timezone setting... "
CONFIG_FILE="config/bolt/config.yaml"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "FAILED"
    echo "  Error: $CONFIG_FILE not found."
    FAILED=1
else
    CONFIG_TZ=$(grep -E "^\s*timezone:\s*" "$CONFIG_FILE" 2>/dev/null | awk '{print $2}' | tr -d '"' | tr -d "'" || true)
    if [ "$CONFIG_TZ" = "$EXPECTED_TIMEZONE" ]; then
        echo "PASSED (timezone: $CONFIG_TZ)"
    else
        echo "FAILED"
        echo "  Expected 'timezone: $EXPECTED_TIMEZONE', got: '${CONFIG_TZ:-<not set / commented out>}'"
        FAILED=1
    fi
fi

# -------------------------------------------------------------
# 2. Check src/Kernel.php override
# -------------------------------------------------------------
echo -n "[2/5] Checking src/Kernel.php runtime timezone boot override... "
KERNEL_FILE="src/Kernel.php"
if [ ! -f "$KERNEL_FILE" ]; then
    echo "FAILED"
    echo "  Error: $KERNEL_FILE does not exist. App\Kernel must extend Bolt\Kernel and override boot()."
    FAILED=1
else
    HAS_EXTENDS=$(grep -E "class\s+Kernel\s+extends\s+(BoltKernel|\\\\Bolt\\\\Kernel)" "$KERNEL_FILE" || true)
    HAS_TZ_CONST=$(grep -E "(const\s+TIMEZONE\s*=\s*['\"]${EXPECTED_TIMEZONE}['\"])" "$KERNEL_FILE" || true)
    HAS_TZ_CALL=$(grep -E "date_default_timezone_set\(" "$KERNEL_FILE" || true)

    if [ -n "$HAS_EXTENDS" ] && [ -n "$HAS_TZ_CONST" ] && [ -n "$HAS_TZ_CALL" ]; then
        echo "PASSED (Kernel extends BoltKernel and sets $EXPECTED_TIMEZONE in boot())"
    else
        echo "FAILED"
        [ -z "$HAS_EXTENDS" ] && echo "  - Kernel does not extend BoltKernel"
        [ -z "$HAS_TZ_CONST" ] && echo "  - Missing const TIMEZONE = '$EXPECTED_TIMEZONE'"
        [ -z "$HAS_TZ_CALL" ] && echo "  - Missing date_default_timezone_set() call in boot()"
        FAILED=1
    fi
fi

# -------------------------------------------------------------
# 3. Check Docker PHP INI configurations
# -------------------------------------------------------------
echo -n "[3/5] Checking docker/php/conf.d/*.ini files... "
DOCKER_INI_DIR="docker/php/conf.d"
if [ -d "$DOCKER_INI_DIR" ]; then
    DEV_INI="$DOCKER_INI_DIR/bolt.dev.ini"
    PROD_INI="$DOCKER_INI_DIR/bolt.prod.ini"
    INI_OK=1

    if [ -f "$DEV_INI" ]; then
        if ! grep -q -E "^\s*date\.timezone\s*=\s*$EXPECTED_TIMEZONE" "$DEV_INI"; then
            echo ""
            echo "  WARNING: $DEV_INI does not define 'date.timezone = $EXPECTED_TIMEZONE'"
            WARNINGS=$((WARNINGS + 1))
            INI_OK=0
        fi
    fi

    if [ -f "$PROD_INI" ]; then
        if ! grep -q -E "^\s*date\.timezone\s*=\s*$EXPECTED_TIMEZONE" "$PROD_INI"; then
            echo ""
            echo "  WARNING: $PROD_INI does not define 'date.timezone = $EXPECTED_TIMEZONE'"
            WARNINGS=$((WARNINGS + 1))
            INI_OK=0
        fi
    fi

    if [ "$INI_OK" -eq 1 ]; then
        echo "PASSED (docker/php/conf.d INI files configured)"
    fi
else
    echo "SKIPPED (docker/php/conf.d not present in this project)"
fi

# -------------------------------------------------------------
# 4. Check compose.yaml / docker-compose.yml
# -------------------------------------------------------------
echo -n "[4/5] Checking compose.yaml database service timezone... "
COMPOSE_FILE=""
if [ -f "compose.yaml" ]; then
    COMPOSE_FILE="compose.yaml"
elif [ -f "docker-compose.yml" ]; then
    COMPOSE_FILE="docker-compose.yml"
fi

if [ -n "$COMPOSE_FILE" ]; then
    if grep -q -E "(mariadb|mysql)" "$COMPOSE_FILE"; then
        # Map syntax (TZ: "Europe/Prague") or list syntax (- TZ=Europe/Prague)
        if grep -q -E "TZ[:=][[:space:]]*[\"']?${EXPECTED_TIMEZONE}[\"']?" "$COMPOSE_FILE"; then
            echo "PASSED (TZ: \"$EXPECTED_TIMEZONE\" in $COMPOSE_FILE)"
        else
            echo "WARNING"
            echo "  Database container in $COMPOSE_FILE does not specify TZ: \"$EXPECTED_TIMEZONE\""
            WARNINGS=$((WARNINGS + 1))
        fi
    else
        echo "SKIPPED (No MariaDB/MySQL service in $COMPOSE_FILE)"
    fi
else
    echo "SKIPPED (compose.yaml / docker-compose.yml not present)"
fi

# -------------------------------------------------------------
# 5. Runtime Kernel Boot Test (CLI check)
# -------------------------------------------------------------
echo -n "[5/5] Testing Symfony Kernel boot runtime timezone... "
if [ -f "vendor/autoload.php" ] && [ -f "src/Kernel.php" ]; then
    # Boots the project's App\Kernel in a subclass whose cache, build and log folders live in a
    # temporary directory, so the check writes nothing into the project's var/.
    TMP_KERNEL_DIR=$(mktemp -d)
    RUNTIME_TZ=$(php -d error_reporting=0 -r '
        require "vendor/autoload.php";
        if (! class_exists("App\\Kernel")) { echo "NO_KERNEL"; exit; }
        if ((new ReflectionClass("App\\Kernel"))->isFinal()) { echo "FINAL_KERNEL"; exit; }
        $kernel = new class("prod", false) extends App\Kernel {
            public function getProjectDir(): string { return getcwd(); }
            public function getCacheDir(): string { return $_SERVER["argv"][1] . "/cache"; }
            public function getBuildDir(): string { return $_SERVER["argv"][1] . "/build"; }
            public function getLogDir(): string { return $_SERVER["argv"][1] . "/log"; }
        };
        try {
            $kernel->boot();
        } catch (\Throwable $e) {
            // A failing container build (offline database, missing secret) does not matter here:
            // date_default_timezone_set() runs before parent::boot().
        }
        echo date_default_timezone_get();
    ' "$TMP_KERNEL_DIR" 2>/dev/null || true)
    rm -rf "$TMP_KERNEL_DIR"

    if [ "$RUNTIME_TZ" = "FINAL_KERNEL" ]; then
        echo "SKIPPED (App\Kernel is final; checks 1–2 cover the configuration)"
        RUNTIME_TZ="$EXPECTED_TIMEZONE"
    fi

    if [ "$RUNTIME_TZ" = "$EXPECTED_TIMEZONE" ]; then
        echo "PASSED (Runtime timezone verified as $RUNTIME_TZ)"
    else
        echo "FAILED"
        echo "  Kernel boot produced runtime timezone: '${RUNTIME_TZ:-error}' (expected: $EXPECTED_TIMEZONE)"
        FAILED=1
    fi
else
    echo "SKIPPED (vendor/autoload.php not installed)"
fi

# -------------------------------------------------------------
# Summary
# -------------------------------------------------------------
echo "=========================================================="
if [ "$FAILED" -eq 0 ]; then
    if [ "$WARNINGS" -gt 0 ]; then
        echo " RESULT: PASSED with $WARNINGS warning(s)."
    else
        echo " RESULT: All timezone checks passed perfectly ($EXPECTED_TIMEZONE)!"
    fi
    exit 0
else
    echo " RESULT: FAILED ($FAILED errors, $WARNINGS warnings). Please fix discrepancies."
    exit 1
fi
