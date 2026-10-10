#!/usr/bin/env bash

# bolt-build preflight: checks everything the autonomous run needs before Phase 1, so the build
# does not stop half-way on a missing tool. Read-only.
#
#   bash preflight.sh [--project=PATH] [--base-url=URL]
#
# --project   the Bolt project directory (default: current directory). A directory that does not
#             exist yet, or is empty, is fine: Phase 1 creates it with composer create-project.
# --base-url  the local URL of this project (BOLT_BASE_URL) to test that it answers.
#
# Prints OK / WARN / BLOCKER lines; exits 1 when a blocker remains.

PROJECT="$(pwd)"
BASE_URL=""
for arg in "$@"; do
    case "$arg" in
        --project=*) PROJECT="${arg#*=}" ;;
        --base-url=*) BASE_URL="${arg#*=}" ;;
        --help|-h) sed -n '3,13p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown argument: $arg"; exit 1 ;;
    esac
done

BLOCKERS=0
WARNINGS=0
ok() { echo "  OK       $1"; }
warn() { echo "  WARN     $1"; WARNINGS=$((WARNINGS + 1)); }
block() { echo "  BLOCKER  $1"; BLOCKERS=$((BLOCKERS + 1)); }

version_ge() { [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n 1)" = "$2" ]; }

echo "bolt-build preflight"
echo "Tools"
if command -v php > /dev/null; then
    PHP_V=$(php -r 'echo PHP_VERSION;')
    version_ge "$PHP_V" "8.2.0" && ok "php $PHP_V" || block "php $PHP_V — Bolt 6 needs PHP 8.2 or newer"
    for ext in pdo intl gd mbstring fileinfo; do
        php -m 2>/dev/null | grep -qi "^$ext$" || block "PHP extension '$ext' missing"
    done
    php -m 2>/dev/null | grep -qi "^pdo_sqlite$" || block "PHP extension 'pdo_sqlite' missing (the build uses SQLite from Bolt's default .env)"
else
    block "php not found"
fi
command -v composer > /dev/null && ok "composer $(composer --version 2>/dev/null | awk '{print $3}')" || block "composer not found"
if command -v node > /dev/null; then
    NODE_V=$(node -v | tr -d v)
    version_ge "$NODE_V" "20.0.0" && ok "node $NODE_V" || block "node $NODE_V — the theme build (Tailwind v4, Rollup) needs Node 20 or newer"
else
    block "node not found (needed from Phase 4)"
fi
command -v npm > /dev/null && ok "npm $(npm -v)" || block "npm not found"
command -v git > /dev/null && ok "git $(git --version | awk '{print $3}')" || block "git not found"
command -v curl > /dev/null && ok "curl" || block "curl not found (live checks)"
command -v symfony > /dev/null && ok "symfony CLI (local server)" || warn "symfony CLI not found — run the site another way (Docker, Valet, php -S) and record it as E4"

echo "Project ($PROJECT)"
if [ ! -d "$PROJECT" ] || [ -z "$(ls -A "$PROJECT" 2>/dev/null)" ]; then
    ok "new project — Phase 1 runs: composer create-project bolt/project $PROJECT"
elif [ ! -f "$PROJECT/config/services.yaml" ]; then
    block "$PROJECT exists, is not empty and is not a Bolt project — pick another directory"
else
    cd "$PROJECT" || exit 1
    BOLT_V=$(php -r '$l = json_decode(@file_get_contents("composer.lock"), true);
        foreach ($l["packages"] ?? [] as $p) { if ($p["name"] === "bolt/core") { echo ltrim($p["version"], "v"); } }' 2>/dev/null)
    case "$BOLT_V" in
        6.*) ok "bolt/core $BOLT_V" ;;
        "") block "bolt/core not in composer.lock — run composer install" ;;
        *) block "bolt/core $BOLT_V — the skills target Bolt CMS 6" ;;
    esac
    [ -f vendor/autoload.php ] && ok "vendor/ installed" || block "vendor/ missing — composer install"
    if php bin/console about > /dev/null 2>&1; then
        ok "bin/console boots"
        # bolt:info --tablesInitialised answers through its exit code (0 = tables exist).
        if php bin/console bolt:info --tablesInitialised > /dev/null 2>&1; then
            ok "database initialised"
        else
            warn "database not initialised — in Phase 1 the user runs: php bin/console bolt:setup --no-fixtures (interactive, once)"
        fi
    else
        block "bin/console does not boot — check .env / .env.local (php bin/console about)"
    fi
    if [ -d vendor/tomvondracek/bolt-skills/skills ]; then
        ok "skills installed (vendor/tomvondracek/bolt-skills)"
    else
        warn "skills not installed in the project — Phase 1 runs: composer require --dev tomvondracek/bolt-skills"
    fi
    THEME=$(grep -E "^theme:" config/bolt/config.yaml 2>/dev/null | awk '{print $2}' | tr -d "\"'")
    [ -n "$THEME" ] && [ -d "public/theme/$THEME" ] && warn "active theme '$THEME' already exists — decide (E8) whether to build a new theme folder or continue this one"
    [ -w var ] || [ ! -e var ] && ok "var/ writable" || block "var/ not writable"
    if git rev-parse --git-dir > /dev/null 2>&1; then
        DIRTY=$(git status --porcelain | wc -l | tr -d ' ')
        [ "$DIRTY" = "0" ] && ok "git clean" || warn "$DIRTY uncommitted change(s) — commit a baseline first so every gate can be rolled back"
    else
        warn "not a git repository — Phase 1 runs: git init and a baseline commit"
    fi
fi

if [ -n "$BASE_URL" ]; then
    echo "Local site"
    CODE=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 5 "$BASE_URL/" || true)
    case "$CODE" in
        2*|3*) ok "$BASE_URL answers ($CODE)" ;;
        000) warn "$BASE_URL not reachable — start the server before Phase 1 (live checks need it)" ;;
        *) warn "$BASE_URL answers $CODE" ;;
    esac
fi

echo ""
if [ $BLOCKERS -gt 0 ]; then
    echo "PREFLIGHT: $BLOCKERS blocker(s), $WARNINGS warning(s) — resolve the blockers before Phase 1."
    exit 1
fi
echo "PREFLIGHT: ready ($WARNINGS warning(s) — handled by Phase 1 or recorded in the site plan)."
exit 0
