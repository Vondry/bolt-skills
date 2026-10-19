#!/usr/bin/env bash
set -e

# Master verification runner. Executes every skill's scripts/verify.sh against a Bolt CMS
# project in workflow order (see WORKFLOWS.md, Appendix A).

usage() {
    echo "Usage: ./scripts/verify-all.sh [--project=/path/to/bolt-project] [--skip=skill-a,skill-b]"
    echo "                               [--locales=en,de] [--base-url=http://localhost:8080] [--verbose]"
    echo ""
    echo "Options:"
    echo "  --project=PATH    Path to the target Bolt CMS root directory (default: current directory if it contains config/services.yaml)"
    echo "  --skip=LIST       Comma-separated skills that do not apply to this site (e.g. bolt-htaccess on Nginx)."
    echo "                    Reported as SKIP."
    echo "  --locales=LIST    Secondary locales to verify with bolt-add-language (default: every code in app_locales"
    echo "                    from config/services.yaml except the default 'locale'; none = skip)"
    echo "  --base-url=URL    URL of this project's running site for live HTTP checks (exported as BOLT_BASE_URL)"
    echo "  --verbose, -v     Print the full output of every verify.sh"
    echo "  --help, -h        Show this help message"
}

TARGET_DIR=""
VERBOSE=0
SKIP_LIST=""
LOCALES_ARG=""

for arg in "$@"; do
    case "$arg" in
        --help|-h)
            usage
            exit 0
            ;;
        --project=*)
            TARGET_DIR="${arg#*=}"
            ;;
        --skip=*)
            SKIP_LIST="${arg#*=}"
            ;;
        --locales=*)
            LOCALES_ARG="${arg#*=}"
            ;;
        --base-url=*)
            export BOLT_BASE_URL="${arg#*=}"
            ;;
        --verbose|-v)
            VERBOSE=1
            ;;
        *)
            if [ -d "$arg" ] && [ -f "$arg/config/services.yaml" ]; then
                TARGET_DIR="$arg"
            else
                echo "Error: unknown argument '$arg'"
                echo ""
                usage
                exit 1
            fi
            ;;
    esac
done

if [ -z "$TARGET_DIR" ]; then
    if [ -f "./config/services.yaml" ]; then
        TARGET_DIR="$(pwd)"
    else
        usage
        echo ""
        echo "Error: Target Bolt CMS project not specified or config/services.yaml not found in current directory."
        exit 1
    fi
fi

TARGET_DIR="$(cd "$TARGET_DIR" && pwd)"
SKILLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../skills" && pwd)"

# Skills in workflow (phase) order. bolt-add-language runs last: it is applied across
# Phases 1-7 and verified once per secondary locale.
SKILLS=(
    "bolt-timezone"            # Phase 1
    "bolt-disable-api"         # Phase 1
    "bolt-code-quality"        # Phase 1 (setup), Phase 8 (run)
    "bolt-htaccess"            # Phase 2 [Apache]
    "bolt-asset-caching"       # Phase 2
    "bolt-security-hardening"  # Phases 1-2 (configuration), 7 (deployment), 8 (live checks)
    "bolt-performance"         # Phase 6 [optional fragment cache; passes when unused]
    "bolt-extension-setup"     # Phases 3 + 6
    "bolt-runtime-extensions"  # Phase 3
    "bolt-theme-init"          # Phase 4
    "bolt-tailwind-theme"      # Phase 4
    "bolt-contenttypes"        # Phase 5
    "bolt-menu"                # Phases 4 + 5
    "bolt-theme-templates"     # Phase 6
    "bolt-helper-pages"        # Phase 6
    "bolt-cookie-consent"      # Phase 6 [privacy page always, banner if trackers or embeds]
    "bolt-legal-cz"            # Phase 6 [identity always, consumer parts per the intake]
    "bolt-add-language"        # Phases 1-7, per secondary locale [multilingual]
)

is_skipped() {
    case ",$SKIP_LIST," in
        *",$1,"*) return 0 ;;
    esac
    return 1
}

for skipped in ${SKIP_LIST//,/ }; do
    known=0
    for skill in "${SKILLS[@]}"; do
        [ "$skill" = "$skipped" ] && known=1
    done
    if [ $known -eq 0 ]; then
        echo "Error: --skip contains unknown skill '$skipped'"
        exit 1
    fi
done

# Secondary locales: --locales, or app_locales minus the default locale from config/services.yaml.
read_parameter() {
    grep -E "^[[:space:]]*$1:" "$TARGET_DIR/config/services.yaml" | head -n 1 \
        | sed -E 's/^[^:]*:[[:space:]]*//; s/[[:space:]]*#.*$//' | tr -d "\"' "
}

if [ -n "$LOCALES_ARG" ]; then
    SECONDARY_LOCALES="${LOCALES_ARG//,/ }"
else
    DEFAULT_LOCALE="$(read_parameter locale || true)"
    APP_LOCALES="$(read_parameter app_locales || true)"
    SECONDARY_LOCALES=""
    for code in ${APP_LOCALES//|/ }; do
        [ "$code" != "$DEFAULT_LOCALE" ] && SECONDARY_LOCALES="$SECONDARY_LOCALES $code"
    done
    SECONDARY_LOCALES="${SECONDARY_LOCALES# }"
fi

echo "================================================================================"
echo " Bolt CMS Master Verification Suite (${#SKILLS[@]} skills, workflow order)"
echo " Target Project:    $TARGET_DIR"
echo " Skills Source:     $SKILLS_DIR"
echo " Secondary locales: ${SECONDARY_LOCALES:-none (bolt-add-language skipped)}"
echo " Live checks URL:   ${BOLT_BASE_URL:-http://127.0.0.1:8000 (default; set --base-url for this project)}"
[ -n "$SKIP_LIST" ] && echo " Skipped by request: $SKIP_LIST"
echo "================================================================================"

PASSED=0
WARNINGS=0
FAILED=0
SKIPPED=0

declare -a REPORT

# A run counts as a warning when it exits 0 but reports warnings. Lines such as
# "PASSED (0 warning(s))" are ignored so a clean run is not mistaken for a warning.
has_warnings() {
    printf '%s\n' "$1" | grep -vE '(^|[^0-9])0 warning' | grep -qiE 'warn|⚠|\[!\]'
}

run_check() {
    local label="$1"
    shift
    local script="$1"
    shift
    local output status=0

    output=$(cd "$TARGET_DIR" && bash "$script" "$@" 2>&1) || status=$?

    if [ $status -ne 0 ]; then
        REPORT+=("[FAIL] $label (failed critical checks)")
        FAILED=$((FAILED + 1))
    elif has_warnings "$output"; then
        REPORT+=("[WARN] $label (passed with warnings)")
        WARNINGS=$((WARNINGS + 1))
    else
        REPORT+=("[PASS] $label (all checks green)")
        PASSED=$((PASSED + 1))
    fi

    if [ $VERBOSE -eq 1 ]; then
        echo "--------------------------------------------------------------------------------"
        echo "Output for $label:"
        echo "$output"
        echo "--------------------------------------------------------------------------------"
    fi
}

for skill in "${SKILLS[@]}"; do
    SCRIPT="$SKILLS_DIR/$skill/scripts/verify.sh"

    if is_skipped "$skill"; then
        REPORT+=("[SKIP] $skill (not applicable, skipped by --skip)")
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    if [ ! -f "$SCRIPT" ]; then
        REPORT+=("[FAIL] $skill (verification script missing)")
        FAILED=$((FAILED + 1))
        continue
    fi

    if [ "$skill" = "bolt-add-language" ]; then
        if [ -z "$SECONDARY_LOCALES" ]; then
            REPORT+=("[SKIP] $skill (single-language site: no secondary locale in app_locales)")
            SKIPPED=$((SKIPPED + 1))
            continue
        fi
        for code in $SECONDARY_LOCALES; do
            run_check "$skill ($code)" "$SCRIPT" "$code"
        done
        continue
    fi

    run_check "$skill" "$SCRIPT"
done

TOTAL=$((PASSED + WARNINGS + FAILED + SKIPPED))

echo ""
echo "============================ VERIFICATION SUMMARY ============================"
for line in "${REPORT[@]}"; do
    case "$line" in
        \[PASS\]*)
            echo -e "\033[0;32m$line\033[0m"
            ;;
        \[WARN\]*)
            echo -e "\033[0;33m$line\033[0m"
            ;;
        \[FAIL\]*)
            echo -e "\033[0;31m$line\033[0m"
            ;;
        \[SKIP\]*)
            echo -e "\033[0;36m$line\033[0m"
            ;;
    esac
done
echo "================================================================================"
echo " Checks Evaluated:       $TOTAL"
echo " Passed (Clean):         $PASSED"
echo " Passed (With Warnings): $WARNINGS"
echo " Failed:                 $FAILED"
echo " Skipped:                $SKIPPED"
echo "================================================================================"

if [ $FAILED -gt 0 ]; then
    echo -e "\033[0;31mRESULT: VERIFICATION FAILED ($FAILED check(s) failed).\033[0m"
    echo "Run with --verbose or run the individual verify.sh for details."
    exit 1
elif [ $WARNINGS -gt 0 ]; then
    echo -e "\033[0;33mRESULT: VERIFICATION PASSED ($WARNINGS check(s) reported warnings).\033[0m"
    echo "Fix each warning or list it under 'Expected verification warnings' in the site plan (WORKFLOWS.md, Phase 0)."
    exit 0
else
    echo -e "\033[0;32mRESULT: VERIFICATION 100% GREEN (all applicable checks passed cleanly).\033[0m"
    exit 0
fi
