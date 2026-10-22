#!/usr/bin/env bash
set -e

# bolt-contenttypes verification: YAML syntax, then the rules of SKILL.md checked by
# scripts/check-contenttypes.php on the parsed config/bolt/contenttypes.yaml, and the admin
# icons (rule 11) checked by scripts/admin-icons.php against Bolt's bundled Font Awesome.

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
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CT_FILE="config/bolt/contenttypes.yaml"
if [ ! -f "$CT_FILE" ]; then
    echo "ERROR: ContentTypes configuration file '$CT_FILE' not found in $BASE_DIR."
    exit 1
fi

echo "=========================================================="
echo " Bolt CMS ContentTypes & Fields Verification"
echo " Project root: $BASE_DIR"
echo " Config file:  $CT_FILE"
echo "=========================================================="

FAILED=0
WARNINGS=0
SECTION=0
TOTAL_SECTIONS=4

section() { SECTION=$((SECTION + 1)); echo ""; echo "[$SECTION/$TOTAL_SECTIONS] $1"; }
pass() { echo "  ✓ $1"; }
warn() { echo "  ⚠ WARNING: $1"; WARNINGS=$((WARNINGS + 1)); }
fail() { echo "  ✗ FAILED: $1"; FAILED=$((FAILED + 1)); }

section "YAML syntax (bin/console lint:yaml $CT_FILE --parse-tags)"
if LINT_OUTPUT=$(php bin/console lint:yaml "$CT_FILE" --parse-tags 2>&1); then
    pass "valid YAML"
else
    fail "invalid YAML:"
    echo "$LINT_OUTPUT" | sed 's/^/    /'
fi

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
done < <(php "$SCRIPT_DIR/check-contenttypes.php" "$BASE_DIR" 2>&1; php "$SCRIPT_DIR/admin-icons.php" check "$BASE_DIR" 2>&1)

# The same checks Bolt shows in the "Bolt Configuration Notices" box of the admin dashboard
# (reserved field names, ambiguous slugs, slug `uses`, unknown field types, cache not cleared
# after a new ContentType, …), run from the command line by bolt-build/scripts/config-notices.php.
NOTICES_SCRIPT="$SCRIPT_DIR/../../bolt-build/scripts/config-notices.php"
section "Bolt Configuration Notices (admin dashboard widget)"
if [ ! -d "vendor/bolt/configuration-notices-widget" ]; then
    warn "bolt/configuration-notices-widget is not installed — open the admin dashboard to see notices."
elif [ ! -f "$NOTICES_SCRIPT" ]; then
    warn "bolt-build/scripts/config-notices.php not found next to this skill."
else
    NOTICES_STATUS=0
    NOTICES_OUTPUT=$(php "$NOTICES_SCRIPT" --project="$BASE_DIR" 2>&1) || NOTICES_STATUS=$?
    case "$NOTICES_STATUS" in
        0) pass "no warning or danger notice"
           echo "$NOTICES_OUTPUT" | grep -v '^No Bolt configuration notices' | sed 's/^/    /' ;;
        1) fail "Bolt reports configuration notices — resolve every one before entering content:"
           echo "$NOTICES_OUTPUT" | sed 's/^/    /' ;;
        *) warn "could not run the notice checks:"
           echo "$NOTICES_OUTPUT" | sed 's/^/    /' ;;
    esac
fi

echo ""
echo "=========================================================="
if [ $FAILED -eq 0 ]; then
    echo " VERIFICATION PASSED ($WARNINGS warning(s))"
    echo "=========================================================="
    exit 0
else
    echo " VERIFICATION FAILED ($FAILED failure(s), $WARNINGS warning(s))"
    echo " Each line names the rule of SKILL.md that fixes it."
    echo "=========================================================="
    exit 1
fi
