#!/usr/bin/env bash
set -e

# bolt-audit: read-only audit of an existing Bolt CMS 6 project against every skill.
#
#   bash audit.sh [--project=PATH] [--base-url=URL] [--out=DIR] [--skip=a,b] [--only=a,b] [--strict]
#
# Writes only to the report directory (default: <project>/var/bolt-audit/<timestamp>/). Bolt's
# .gitignore covers only var/cache, var/log and var/data, so the default directory is added to the
# clone's local .git/info/exclude (never to the committed .gitignore). It never runs a scaffold, an
# installer or a cache clear. The
# skills' verify scripts read the project; their `bin/console lint:*` calls and the kernel boot
# may warm var/cache, which is runtime data.
#
# Report directory:
#   profile.md        what the project is (Bolt version, theme, locales, web server, tooling, git)
#   summary.md        one row per skill: status, failures, warnings, example drift
#   summary.tsv       the same, machine-readable
#   logs/<skill>.log  full output of the skill's verify.sh
#   examples.md       project files compared with each skill's examples (references/example-map.tsv)
#   diffs/<skill>/    unified diffs for the files that differ
#
# Live HTTP checks run only with --base-url (never against a default port, which might be
# another project). --strict exits 1 when a skill fails (for CI).

usage() {
    sed -n '4,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

PROJECT=""
BASE_URL=""
OUT=""
SKIP_LIST=""
ONLY_LIST=""
STRICT=0
for arg in "$@"; do
    case "$arg" in
        --project=*) PROJECT="${arg#*=}" ;;
        --base-url=*) BASE_URL="${arg#*=}" ;;
        --out=*) OUT="${arg#*=}" ;;
        --skip=*) SKIP_LIST="${arg#*=}" ;;
        --only=*) ONLY_LIST="${arg#*=}" ;;
        --strict) STRICT=1 ;;
        --help|-h) usage; exit 0 ;;
        *) echo "Unknown argument: $arg"; usage; exit 1 ;;
    esac
done

PROJECT="${PROJECT:-$(pwd)}"
if [ ! -f "$PROJECT/config/services.yaml" ]; then
    echo "ERROR: $PROJECT is not a Bolt CMS project root (config/services.yaml not found)."
    exit 1
fi
PROJECT="$(cd "$PROJECT" && pwd)"
AUDIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILLS_DIR="$(cd "$AUDIT_DIR/.." && pwd)"
MAP="$AUDIT_DIR/references/example-map.tsv"
STAMP="$(date +%Y%m%d-%H%M%S)"
DEFAULT_OUT=0
[ -z "$OUT" ] && DEFAULT_OUT=1
OUT="${OUT:-$PROJECT/var/bolt-audit/$STAMP}"
# Keep the default report directory out of `git status` without touching the committed .gitignore.
if [ $DEFAULT_OUT -eq 1 ] && git -C "$PROJECT" rev-parse --git-dir > /dev/null 2>&1 \
    && ! git -C "$PROJECT" check-ignore -q "var/bolt-audit/$STAMP" 2>/dev/null; then
    EXCLUDE="$(git -C "$PROJECT" rev-parse --git-path info/exclude)"
    case "$EXCLUDE" in /*) ;; *) EXCLUDE="$PROJECT/$EXCLUDE" ;; esac
    mkdir -p "$(dirname "$EXCLUDE")"
    echo "/var/bolt-audit/" >> "$EXCLUDE"
    echo "Added /var/bolt-audit/ to $EXCLUDE (local git ignore, not committed)."
fi
mkdir -p "$OUT/logs" "$OUT/diffs"
OUT="$(cd "$OUT" && pwd)"

if [ -n "$BASE_URL" ]; then
    export BOLT_BASE_URL="$BASE_URL"
    LIVE="on ($BASE_URL)"
else
    # A closed local port: every live check reports "not reachable" and is skipped.
    export BOLT_BASE_URL="http://127.0.0.1:9"
    LIVE="off (pass --base-url=… to enable)"
fi

in_list() { case ",$2," in *",$1,"*) return 0 ;; esac; return 1; }

# ---------------------------------------------------------------- profile
cd "$PROJECT"

param() {
    grep -E "^[[:space:]]*$1:" config/services.yaml | head -n 1 \
        | sed -E 's/^[^:]*:[[:space:]]*//; s/[[:space:]]*#.*$//' | tr -d "\"' "
}
lock_version() {
    [ -f composer.lock ] || return 0
    php -r '$l = json_decode(file_get_contents("composer.lock"), true);
        foreach (array_merge($l["packages"] ?? [], $l["packages-dev"] ?? []) as $p) { if ($p["name"] === $argv[1]) { echo $p["version"]; } }' "$1" 2>/dev/null || true
}

THEME=$(grep -E "^theme:" config/bolt/config.yaml 2>/dev/null | head -n 1 | awk '{print $2}' | tr -d "\"'")
THEME="${THEME:-default}"
THEME_DIR="public/theme/$THEME"
DEFAULT_LOCALE="$(param locale || true)"
APP_LOCALES="$(param app_locales || true)"
SECONDARY=""
for code in ${APP_LOCALES//|/ }; do
    [ "$code" != "$DEFAULT_LOCALE" ] && SECONDARY="$SECONDARY $code"
done
SECONDARY="${SECONDARY# }"

BOLT_VERSION="$(lock_version bolt/core)"
WEB_SERVER="unknown"
NGINX_CONF="$(find . -path ./vendor -prune -o -path ./node_modules -prune -o -path ./public/theme -prune -o -name '*.conf' -print 2>/dev/null | xargs grep -l "server_name\|fastcgi_pass" 2>/dev/null | head -n 1 || true)"
if [ -n "$NGINX_CONF" ] && [ -f public/.htaccess ]; then
    WEB_SERVER="Apache and Nginx configuration both present ($NGINX_CONF)"
elif [ -n "$NGINX_CONF" ]; then
    WEB_SERVER="Nginx ($NGINX_CONF)"
elif [ -f public/.htaccess ]; then
    WEB_SERVER="Apache (public/.htaccess)"
fi
DOCKER="no"
for compose in compose.yaml compose.yml docker-compose.yml docker-compose.yaml; do
    [ -f "$compose" ] && DOCKER="yes ($compose)"
done
GIT_INFO="not a git repository"
if git rev-parse --git-dir > /dev/null 2>&1; then
    DIRTY=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    GIT_INFO="$(git rev-parse --abbrev-ref HEAD 2>/dev/null) @ $(git rev-parse --short HEAD 2>/dev/null), $DIRTY uncommitted change(s)"
fi
TAILWIND="$(grep -oE '"tailwindcss"[^,}]*' "$THEME_DIR/package.json" 2>/dev/null | head -n 1 | sed -E 's/.*: *//' | tr -d '"' || true)"
CT_COUNT=$(grep -cE "^[a-z_][a-z0-9_-]*:" config/bolt/contenttypes.yaml 2>/dev/null || echo 0)
# Templates and TypeScript sources only (built bundles repeat them); cookie-consent.ts is the
# consent-gated loader itself.
TRACKERS=$(grep -ohE "googletagmanager\.com|gtag\(|c\.seznam\.cz/js/rc\.js|connect\.facebook\.net|hotjar|clarity\.ms" -r "$THEME_DIR" --include="*.twig" --include="*.ts" --exclude="cookie-consent.ts" --exclude-dir=node_modules 2>/dev/null | sort -u | tr '\n' ' ' || true)
PRIVACY_BLOCK="no"
grep -qE "^privacy:" "$THEME_DIR/theme.yaml" 2>/dev/null && PRIVACY_BLOCK="yes"

BOLT_MAJOR="${BOLT_VERSION#v}"
BOLT_MAJOR="${BOLT_MAJOR%%.*}"
VERSION_NOTE=""
if [ -z "$BOLT_VERSION" ]; then
    VERSION_NOTE=" — not found in composer.lock"
elif [ "$BOLT_MAJOR" != "6" ]; then
    VERSION_NOTE=" — the skills target Bolt CMS 6; upgrade first or read every finding with that in mind"
fi

cat > "$OUT/profile.md" <<EOF
# Project profile

| | |
| :--- | :--- |
| Project | \`$PROJECT\` |
| Audited | $(date '+%Y-%m-%d %H:%M') |
| Git | $GIT_INFO |
| Bolt CMS (bolt/core) | ${BOLT_VERSION:-unknown}$VERSION_NOTE |
| PHP (CLI) | $(php -r 'echo PHP_VERSION;' 2>/dev/null) |
| Theme | \`$THEME\` ($THEME_DIR$([ -d "$THEME_DIR" ] || echo ' — missing')) |
| Locales | default \`${DEFAULT_LOCALE:-?}\`, app_locales \`${APP_LOCALES:-?}\` |
| ContentTypes | $CT_COUNT top-level keys in config/bolt/contenttypes.yaml |
| Web server | $WEB_SERVER |
| Docker | $DOCKER |
| Tailwind CSS | ${TAILWIND:-not found in $THEME_DIR/package.json} |
| Tracking found in theme sources | ${TRACKERS:-none} |
| theme.yaml privacy: block (bolt-cookie-consent data model) | $PRIVACY_BLOCK |
| vendor/ installed | $([ -f vendor/autoload.php ] && echo yes || echo 'no — several checks need composer install') |
| Live HTTP checks | $LIVE |
EOF

# ---------------------------------------------------------------- run the skills
SKILLS=(bolt-timezone bolt-disable-api bolt-code-quality bolt-htaccess bolt-asset-caching
        bolt-extension-setup bolt-runtime-extensions bolt-theme-init bolt-tailwind-theme
        bolt-contenttypes bolt-menu bolt-theme-templates bolt-helper-pages bolt-cookie-consent
        bolt-add-language)

printf "skill\tstatus\tfailures\twarnings\tnote\n" > "$OUT/summary.tsv"

record() { printf "%s\t%s\t%s\t%s\t%s\n" "$1" "$2" "$3" "$4" "$5" >> "$OUT/summary.tsv"; }

run_skill() {
    local label="$1" script="$2" log="$3"
    shift 3
    local status=0
    ( cd "$PROJECT" && bash "$script" "$@" ) > "$log" 2>&1 || status=$?
    # Lines that report a problem; formats differ between the skills' scripts.
    local fails warns
    fails=$(grep -ciE "(^|[^a-z])(failed|fail|error|missing)([^a-z]|$)" "$log" | tr -d ' ' || true)
    warns=$(grep -ciE "(^|[^a-z])(warning|warn|notice)([^a-z]|$)" "$log" | tr -d ' ' || true)
    # The final summary lines repeat the counts; do not count them twice.
    fails=$(( fails - $(grep -ciE "VERIFICATION (FAILED|PASSED)" "$log" || true) ))
    [ $fails -lt 0 ] && fails=0
    if [ $status -ne 0 ]; then
        record "$label" "FAIL" "$fails" "$warns" ""
    # Same rule as verify-all.sh: lines like "PASSED (0 warning(s))" are not warnings.
    elif grep -vE '(^|[^0-9])0 warning' "$log" | grep -qiE 'warn|notice|⚠|\[!\]'; then
        record "$label" "WARN" 0 "$warns" ""
    else
        record "$label" "PASS" 0 0 ""
    fi
    echo "  $label: $(tail -n 1 "$OUT/summary.tsv" | cut -f2)"
}

echo "bolt-audit: $PROJECT"
echo "Report: $OUT"
for skill in "${SKILLS[@]}"; do
    if [ -n "$ONLY_LIST" ] && ! in_list "$skill" "$ONLY_LIST"; then continue; fi
    if in_list "$skill" "$SKIP_LIST"; then
        record "$skill" "SKIP" 0 0 "skipped by --skip"
        continue
    fi
    SCRIPT="$SKILLS_DIR/$skill/scripts/verify.sh"
    case "$skill" in
        bolt-htaccess)
            if [ ! -f public/.htaccess ] && [ ! -f .htaccess ] && [ -n "$NGINX_CONF" ]; then
                record "$skill" "N/A" 0 0 "Nginx site (no .htaccess)"
                continue
            fi
            run_skill "$skill" "$SCRIPT" "$OUT/logs/$skill.log"
            ;;
        bolt-add-language)
            if [ -z "$SECONDARY" ]; then
                record "$skill" "N/A" 0 0 "single-language site"
                continue
            fi
            for code in $SECONDARY; do
                run_skill "$skill ($code)" "$SCRIPT" "$OUT/logs/$skill-$code.log" "$code"
            done
            ;;
        *)
            # bolt-cookie-consent runs without --draft: an audit judges the production state.
            run_skill "$skill" "$SCRIPT" "$OUT/logs/$skill.log"
            ;;
    esac
done

# ---------------------------------------------------------------- examples vs. project
{
    echo "# Project files compared with the skills' examples"
    echo ""
    echo "\`logic\` files should match the example apart from deliberate changes — review every drift."
    echo "\`design\` files are expected to differ (design, content); check that the contract (hooks,"
    echo "includes, rules) survived. \`snippet\` files are merged into a larger file — review by hand."
    echo ""
    echo "| Skill | Project file | Kind | State | Diff |"
    echo "| :--- | :--- | :--- | :--- | :--- |"
} > "$OUT/examples.md"

declare -a DRIFT_SKILLS=()
while IFS=$'\t' read -r skill example target kind; do
    case "$skill" in ''|\#*) continue ;; esac
    if [ -n "$ONLY_LIST" ] && ! in_list "$skill" "$ONLY_LIST"; then continue; fi
    in_list "$skill" "$SKIP_LIST" && continue
    target="${target//\{theme\}/$THEME_DIR}"
    src="$SKILLS_DIR/$skill/examples/$example"
    state="" diff_link=""
    if [ "$kind" = "snippet" ] || [ "$kind" = "variant" ]; then
        if [ -f "$target" ]; then state="present — review by hand"; else state="file missing"; fi
    elif [ ! -f "$target" ]; then
        state="missing"
    elif diff -q "$src" "$target" > /dev/null 2>&1; then
        state="identical"
    else
        mkdir -p "$OUT/diffs/$skill"
        diff_file="$OUT/diffs/$skill/$(echo "$target" | tr '/' '_').diff"
        diff -u "$src" "$target" > "$diff_file" 2>/dev/null || true
        added=$(grep -c '^+[^+]' "$diff_file" || true)
        removed=$(grep -c '^-[^-]' "$diff_file" || true)
        state="differs (+$added / −$removed lines)"
        diff_link="[diff](diffs/$skill/$(basename "$diff_file"))"
        [ "$kind" = "logic" ] && DRIFT_SKILLS+=("$skill")
    fi
    echo "| $skill | \`$target\` | $kind | $state | $diff_link |" >> "$OUT/examples.md"
done < "$MAP"

# ---------------------------------------------------------------- summary
{
    echo "# bolt-audit summary"
    echo ""
    echo "Project profile: [profile.md](profile.md) · Example comparison: [examples.md](examples.md)"
    echo ""
    echo "| Skill | Status | Problem lines | Warning lines | Logic drift vs. examples | Log |"
    echo "| :--- | :--- | ---: | ---: | :--- | :--- |"
    tail -n +2 "$OUT/summary.tsv" | while IFS=$'\t' read -r skill status fails warns note; do
        base="${skill%% *}"
        code="${skill#* (}"; code="${code%)}"
        log="logs/$base.log"; [ "$code" != "$skill" ] && log="logs/$base-$code.log"
        drift=""
        for d in "${DRIFT_SKILLS[@]}"; do [ "$d" = "$base" ] && drift="yes"; done
        link="[log]($log)"; [ "$status" = "N/A" ] || [ "$status" = "SKIP" ] && link="$note"
        echo "| $skill | $status | $fails | $warns | $drift | $link |"
    done
    echo ""
    echo "Status comes from each skill's verify.sh (exit code and warnings). The line counts are a rough"
    echo "size indicator — read the log. Next: the per-skill review in SKILL.md, step 4."
} > "$OUT/summary.md"

echo ""
cat "$OUT/summary.md" | sed -n '5,$p' | head -n 25
echo ""
echo "Report written to $OUT"

if [ $STRICT -eq 1 ] && cut -f2 "$OUT/summary.tsv" | grep -q "^FAIL$"; then
    exit 1
fi
exit 0
