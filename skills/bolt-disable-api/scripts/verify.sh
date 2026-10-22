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

echo "=========================================================="
echo " Bolt CMS API & GraphQL Lockdown Verification"
echo " Project root: $BASE_DIR"
echo " Environment: ${APP_ENV:-dev}"
echo "=========================================================="

FAILED=0

# 1. API Platform routes must stay registered: Bolt's admin listings generate IRIs from them
#    ("Unable to generate an IRI for the item of type Bolt\Entity\Content" otherwise).
#    The API is blocked by the firewall rule (check 4), not by removing routes.
echo -n "[1/5] Checking that API Platform routes stay registered (needed by the admin)... "
API_ROUTE_COUNT=$(php bin/console debug:router 2>/dev/null | grep -c " _api_" || true)

if [ "${API_ROUTE_COUNT:-0}" -gt 0 ]; then
    echo "PASSED ($API_ROUTE_COUNT _api_* routes registered)"
else
    echo "FAILED"
    echo "  No _api_* routes found. The api_platform route loader in config/routes/api_platform.yaml"
    echo "  is probably commented out, which breaks the Bolt admin listings (\"Unable to generate an IRI\")."
    echo "  Restore the loader (Step 1); the firewall rule keeps the API closed."
    FAILED=1
fi

# 2. Check YAML Linting
echo -n "[2/5] Validating YAML configuration files... "
if php bin/console lint:yaml config --parse-tags > /dev/null 2>&1; then
    echo "PASSED"
else
    echo "FAILED (YAML syntax error detected)"
    FAILED=1
fi

# 3. Check Configuration Flags
echo -n "[3/5] Checking api_platform configuration flags... "
# debug:config with a path prints the resolved value alone (independent of key order).
config_value() {
    php bin/console debug:config api_platform "$1" 2>/dev/null | grep -vE '^[[:space:]]*(=+|Current configuration.*)?[[:space:]]*$' | tail -n 1 | tr -d '[:space:]' || true
}
DOCS_FLAG=$(config_value enable_docs)
GRAPHIQL_FLAG=$(config_value graphql.graphiql.enabled)

if [ "$DOCS_FLAG" = "false" ] && [ "$GRAPHIQL_FLAG" = "false" ]; then
    echo "PASSED (docs: disabled, graphiql: disabled)"
else
    echo "WARNING / NOTICE"
    echo "  enable_docs: '$DOCS_FLAG' (expected: false)"
    echo "  graphiql.enabled: '$GRAPHIQL_FLAG' (expected: false)"
    FAILED=1
fi

# CORS headers belong to the API only; Bolt's stock nelmio_cors applies them to every path.
if [ -f config/packages/nelmio_cors.yaml ] && grep -qE "^[[:space:]]+'\^/':" config/packages/nelmio_cors.yaml; then
    echo "  WARNING: config/packages/nelmio_cors.yaml applies CORS to every path ('^/') — limit it to '^/api/' (Step 5)."
fi

# 4. Firewall: the first access_control rule matching /api must deny everyone. It is the only
#    thing that blocks API requests, since the routes stay registered.
echo -n "[4/5] Checking the ^/api(/|\$) firewall rule... "
FIRST_API_RULE=$(php bin/console debug:config security access_control 2>/dev/null | awk '
    /^[[:space:]]*path:/ { path = $2; inrule = (path ~ /^\^\/api/); next }
    inrule && /^[[:space:]]*- / { sub(/^[[:space:]]*- /, ""); print path " " $0; exit }
' || true)

if [ "$FIRST_API_RULE" = "^/api(/|\$) ROLE_NO_ACCESS" ]; then
    echo "PASSED (first /api rule denies all: $FIRST_API_RULE)"
else
    echo "FAILED"
    echo "  Expected the first access_control rule matching /api to be"
    echo "  { path: '^/api(/|\$)', roles: ROLE_NO_ACCESS } (Step 4); found: '${FIRST_API_RULE:-none}'"
    FAILED=1
fi

# 5. Check HTTP Endpoints if server is reachable
BASE_URL="${BOLT_BASE_URL:-http://127.0.0.1:8000}"  # set BOLT_BASE_URL to this project's running site
echo -n "[5/5] Checking HTTP endpoints against $BASE_URL... "
# 10 s: a production site on a cold cache (or behind a CDN) often needs more than 2 s; a closed
# port still fails at once.
if curl -s --max-time 10 "$BASE_URL" > /dev/null 2>&1; then
    echo ""
    # Data endpoints must be refused by the firewall (401/403). 404 there would mean the
    # routes are gone, which breaks the admin (check 1). Documentation and GraphiQL may
    # also answer 404, because they are switched off as features; so does the bare /api
    # (the entrypoint is disabled, and routing answers 404 before the firewall runs).
    DATA_ENDPOINTS=(
        "/api/contents"
        "/api/contents/1"
        "/api/fields"
        "/api/relations"
    )
    DOC_ENDPOINTS=(
        "/api"
        "/api/docs.html"
        "/api/docs.jsonopenapi"
        "/api/graphql/graphiql"
    )

    check_endpoint() {
        local ep="$1" allowed="$2" status
        status=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL$ep" || true)
        if [[ " $allowed " == *" $status "* ]]; then
            echo "  $ep -> HTTP $status (BLOCKED/PASSED)"
        else
            echo "  $ep -> HTTP $status (FAILED - expected one of: $allowed)"
            FAILED=1
        fi
    }

    for ep in "${DATA_ENDPOINTS[@]}"; do
        check_endpoint "$ep" "401 403"
    done
    for ep in "${DOC_ENDPOINTS[@]}"; do
        check_endpoint "$ep" "401 403 404"
    done

    # Front-controller path: refused, or redirected to /api/contents (bolt-htaccess redirects
    # /index.php/… to the clean path, which is checked above). A 200 is a leak only when it
    # carries API data; an HTML page means /index.php/… is not redirected (bolt-htaccess Pitfall 10).
    # Requested only when public/.htaccess redirects /index.php/… (bolt-htaccess Pitfall 10):
    # otherwise the request reaches Symfony, whose base URL then becomes the script path and lands
    # in Bolt's cached links (canonical, llms.txt) for the cache lifetime. The API firewall matches
    # the same path info as the router, so this path cannot bypass it.
    if grep -qE '^\s*RewriteCond\s+%\{THE_REQUEST\}.*index\\\.php' public/.htaccess 2>/dev/null; then
        FC_RESULT=$(curl -s -o /dev/null -w "%{http_code}|%{content_type}|%{redirect_url}" "$BASE_URL/index.php/api/contents" || true)
    else
        FC_RESULT="skip||"
    fi
    IFS="|" read -r FC_STATUS FC_TYPE FC_LOCATION <<< "$FC_RESULT"
    case "$FC_STATUS" in
        skip) echo "  /index.php/api/contents -> not requested (no /index.php/… redirect in public/.htaccess, so the"
              echo "    request would poison Bolt's cached links — bolt-htaccess Pitfall 10)" ;;
        401|403) echo "  /index.php/api/contents -> HTTP $FC_STATUS (BLOCKED/PASSED)" ;;
        301|302|307|308)
            if [[ "$FC_LOCATION" == */api/contents && "$FC_LOCATION" != *index.php* ]]; then
                echo "  /index.php/api/contents -> HTTP $FC_STATUS to /api/contents (REDIRECTED/PASSED)"
            else
                echo "  /index.php/api/contents -> HTTP $FC_STATUS to $FC_LOCATION (FAILED - expected a redirect to /api/contents)"
                FAILED=1
            fi ;;
        200)
            if [[ "$FC_TYPE" == *json* ]]; then
                echo "  /index.php/api/contents -> HTTP 200 $FC_TYPE (FAILED - the API answers through the front controller)"
                FAILED=1
            else
                echo "  /index.php/api/contents -> HTTP 200 $FC_TYPE (API not exposed; WARNING: /index.php/… renders a"
                echo "    page instead of redirecting — fix it with bolt-htaccess Pitfall 10)"
            fi ;;
        *) echo "  /index.php/api/contents -> HTTP $FC_STATUS (FAILED - expected 401, 403 or a redirect to /api/contents)"
           FAILED=1 ;;
    esac

    # Test GraphQL POST
    GQL_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE_URL/api/graphql" \
        -H "Content-Type: application/json" -d '{"query":"{ contents { edges { node { id } } } }"}' || true)
    if [ "$GQL_STATUS" = "401" ] || [ "$GQL_STATUS" = "403" ]; then
        echo "  /api/graphql (POST) -> HTTP $GQL_STATUS (BLOCKED/PASSED)"
    else
        echo "  /api/graphql (POST) -> HTTP $GQL_STATUS (FAILED - expected 401 or 403)"
        FAILED=1
    fi
else
    echo "SKIPPED (Web server not running on $BASE_URL)"
fi

echo "=========================================================="
if [ "$FAILED" -eq 0 ]; then
    echo " RESULT: All checks passed successfully! API & GraphQL are disabled."
    exit 0
else
    echo " RESULT: Verification encountered failures."
    exit 1
fi
