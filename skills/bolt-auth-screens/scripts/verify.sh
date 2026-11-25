#!/usr/bin/env bash
set -e

# bolt-auth-screens verification: the shared sign-in templates, their wiring in theme.yaml, the
# project's bolt_auth values and their contrast, the theme integration, Twig syntax and the live
# login and reset-request screens (BOLT_BASE_URL, else PHP's built-in server).

DIR="$(pwd)"
while [ "$DIR" != "/" ] && [ ! -f "$DIR/config/services.yaml" ]; do
    DIR="$(dirname "$DIR")"
done
if [ ! -f "$DIR/config/services.yaml" ]; then
    echo "ERROR: Could not locate Bolt CMS project root (config/services.yaml not found)."
    exit 1
fi
BASE_DIR="$DIR"
cd "$BASE_DIR"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=========================================================="
echo " Bolt CMS Auth Screens Verification"
echo " Project root: $BASE_DIR"
echo "=========================================================="

FAILED=0
WARNINGS=0
SECTION=0
TOTAL_SECTIONS=8

section() { SECTION=$((SECTION + 1)); echo ""; echo "[$SECTION/$TOTAL_SECTIONS] $1"; }
pass() { echo "  ✓ $1"; }
warn() { echo "  ⚠ WARNING: $1"; WARNINGS=$((WARNINGS + 1)); }
fail() { echo "  ✗ FAILED: $1"; FAILED=$((FAILED + 1)); }

report() {
    while IFS= read -r line; do
        kind="${line%% *}"
        message="${line#* }"
        case "$kind" in
            SECTION) section "$message" ;;
            PASS) pass "$message" ;;
            WARN) warn "$message" ;;
            FAIL) fail "$message" ;;
            *) [ -n "$line" ] && echo "  $line" ;;
        esac
    done
}

# Live screens: BOLT_BASE_URL, else PHP's built-in server started for this check.
BASE_URL=""
SERVER_PID=""
if [ -n "${BOLT_BASE_URL:-}" ] && curl -s --max-time 10 -o /dev/null "$BOLT_BASE_URL"; then
    BASE_URL="${BOLT_BASE_URL%/}"
elif command -v php > /dev/null 2>&1 && [ -f public/index.php ]; then
    PORT=$((18000 + RANDOM % 1000))
    ROUTER="$SCRIPT_DIR/../../bolt-theme-templates/scripts/php-server-router.php"
    # The project's .env may limit trusted hosts to the production domain; 127.0.0.1 must pass here.
    SYMFONY_TRUSTED_HOSTS='' php -S "127.0.0.1:$PORT" -t public "$ROUTER" > /dev/null 2>&1 &
    SERVER_PID=$!
    trap '[ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null' EXIT
    for _ in $(seq 1 30); do
        curl -s --max-time 2 -o /dev/null "http://127.0.0.1:$PORT/" && { BASE_URL="http://127.0.0.1:$PORT"; break; }
        sleep 0.5
    done
fi

# The rate-limit test runs only against the server started here: it uses up the limit of this IP
# address, and the limiter's pool is cleared afterwards.
RATE_TEST=""
[ -n "$SERVER_PID" ] && RATE_TEST="--rate-limit-test=1"
report < <(php "$SCRIPT_DIR/auth-screens.php" check "$BASE_DIR" ${BASE_URL:+--base-url="$BASE_URL"} $RATE_TEST 2>&1)
if [ -n "$RATE_TEST" ]; then
    php bin/console cache:pool:clear cache.rate_limiter > /dev/null 2>&1 || true
fi

THEME="$(grep -E '^theme:' config/bolt/config.yaml | head -n 1 | sed -E 's/^theme:[[:space:]]*//; s/[[:space:]]*#.*$//' | tr -d "\"' ")"
section "Twig syntax (bin/console lint:twig public/theme/$THEME/bolt-auth)"
if [ -d "public/theme/$THEME/bolt-auth" ]; then
    if LINT=$(php bin/console lint:twig "public/theme/$THEME/bolt-auth" 2>&1); then
        pass "the bolt-auth templates compile"
    else
        fail "lint:twig reports errors:"
        echo "$LINT" | grep -E "ERROR|Error|error" | head -10 | sed 's/^/      /'
    fi
else
    fail "public/theme/$THEME/bolt-auth not found"
fi

section "Every screen and state renders (scripts/preview.php check: Bolt's forms, dummy data, no account)"
report < <(php "$SCRIPT_DIR/preview.php" check "$BASE_DIR" 2>&1)

if [ -z "$BASE_URL" ]; then
    section "Live screens"
    fail "no site to test against — set BOLT_BASE_URL, or make PHP's built-in server start (php -S, database reachable)"
fi
[ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null && { wait "$SERVER_PID" 2>/dev/null || true; SERVER_PID=""; }

echo ""
echo "  Not checked here (SKILL.md, Step 5): the look in a browser — run the preview server"
echo "  (php -S 127.0.0.1:8899 -t public $SCRIPT_DIR/preview.php → /__bolt-auth/) — and signing in."

echo ""
echo "=========================================================="
if [ $FAILED -eq 0 ]; then
    echo " VERIFICATION PASSED ($WARNINGS warning(s))"
    echo "=========================================================="
    exit 0
else
    echo " VERIFICATION FAILED ($FAILED failure(s), $WARNINGS warning(s))"
    echo " Please review the errors reported above."
    echo "=========================================================="
    exit 1
fi
