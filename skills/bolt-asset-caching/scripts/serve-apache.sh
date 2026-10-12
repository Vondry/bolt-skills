#!/usr/bin/env bash
# Serve a Bolt CMS project locally the way an Apache production host does: Apache with the project's
# own .htaccess files (root + public/) and PHP-FPM. `symfony serve` and PHP's built-in server ignore
# .htaccess, so they can't show whether thumbnails come from disk or which cache headers they get.
#
# usage: serve-apache.sh start|stop [--project=PATH] [--port=8090] [--env=prod]
#
# start prints the base URL and the PHP-FPM access log for scripts/check-delivery.php. Nothing in the
# project changes except var/serve-apache/ (configs, logs, pid files); Symfony builds var/cache/<env>
# on the first request.
set -eu

ACTION=${1:-}
shift || true
PROJECT=""
PORT=8090
APP_ENV_VALUE=prod
for arg in "$@"; do
    case $arg in
        --project=*) PROJECT="${arg#*=}" ;;
        --port=*) PORT="${arg#*=}" ;;
        --env=*) APP_ENV_VALUE="${arg#*=}" ;;
        *) echo "Unknown option: $arg"; exit 2 ;;
    esac
done
if [ "$ACTION" != start ] && [ "$ACTION" != stop ]; then
    echo "usage: serve-apache.sh start|stop [--project=PATH] [--port=8090] [--env=prod]"
    exit 2
fi

PROJECT=$(cd "${PROJECT:-.}" && pwd)
if [ ! -f "$PROJECT/config/services.yaml" ]; then
    echo "ERROR: $PROJECT is not a Bolt CMS project root (config/services.yaml not found)."
    exit 1
fi
STATE="$PROJECT/var/serve-apache"
FPMPORT=$((PORT + 1000))

HTTPD=$(command -v httpd || command -v apache2 || true)

if [ "$ACTION" = stop ]; then
    [ -f "$STATE/httpd.pid" ] && [ -n "$HTTPD" ] && "$HTTPD" -f "$STATE/httpd.conf" -k stop 2>/dev/null || true
    [ -f "$STATE/php-fpm.pid" ] && kill "$(cat "$STATE/php-fpm.pid")" 2>/dev/null || true
    sleep 1
    rm -f "$STATE/httpd.pid" "$STATE/php-fpm.pid"
    echo "Stopped Apache and PHP-FPM for $PROJECT"
    exit 0
fi

# --- locate Apache, its modules, mime.types and PHP-FPM -------------------------------------------
[ -n "$HTTPD" ] || { echo "ERROR: Apache (httpd / apache2) not found."; exit 1; }
MODULES=""
for d in /usr/libexec/apache2 /opt/homebrew/lib/httpd/modules /usr/local/lib/httpd/modules \
         /usr/lib/apache2/modules /usr/lib64/httpd/modules /usr/lib/httpd/modules; do
    [ -f "$d/mod_rewrite.so" ] && { MODULES=$d; break; }
done
[ -n "$MODULES" ] || { echo "ERROR: Apache module directory (with mod_rewrite.so) not found."; exit 1; }
MIME=""
for f in /private/etc/apache2/mime.types /opt/homebrew/etc/httpd/mime.types /usr/local/etc/httpd/mime.types \
         /etc/httpd/conf/mime.types /etc/mime.types; do
    [ -f "$f" ] && { MIME=$f; break; }
done
FPM=$(command -v php-fpm || ls /opt/homebrew/sbin/php-fpm /usr/local/sbin/php-fpm /usr/sbin/php-fpm* 2>/dev/null | tail -1 || true)
[ -n "$FPM" ] || { echo "ERROR: php-fpm not found."; exit 1; }

BUILTIN=$("$HTTPD" -l 2>/dev/null || true)
load() {
    local name=$1 file=$2
    echo "$BUILTIN" | grep -q "mod_${name}.c" && return
    [ -f "$MODULES/$file" ] && echo "LoadModule ${name}_module $MODULES/$file"
}

# Shared hosting points the domain at the project root (root .htaccess forwards to public/);
# otherwise the document root is public/.
if [ -f "$PROJECT/.htaccess" ]; then DOCROOT=$PROJECT; else DOCROOT=$PROJECT/public; fi

mkdir -p "$STATE/logs" "$STATE/tmp"
# Keep the state folder out of `git status` (Bolt's .gitignore only covers var/cache, var/log, var/data).
echo '*' > "$STATE/.gitignore"
{
    echo "ServerRoot \"$STATE\""
    echo "Listen 127.0.0.1:$PORT"
    echo "$BUILTIN" | grep -qE 'prefork|worker|event' || load mpm_prefork mod_mpm_prefork.so
    for m in authz_core authz_host access_compat unixd dir mime rewrite expires headers env setenvif alias proxy proxy_fcgi log_config filter deflate; do
        load "$m" "mod_$m.so"
    done
    cat <<EOF
ServerName localhost
DefaultRuntimeDir "$STATE"
Mutex file:$STATE default
PidFile "$STATE/httpd.pid"
ErrorLog "$STATE/logs/error.log"
LogFormat "%{X-Probe-Id}i %>s \"%r\"" probe
CustomLog "$STATE/logs/access.log" probe
${MIME:+TypesConfig $MIME}
DirectoryIndex index.php index.html
DocumentRoot "$DOCROOT"
<Directory "/">
    AllowOverride None
    Require all denied
</Directory>
<Directory "$PROJECT">
    Options FollowSymLinks
    AllowOverride All
    Require all granted
</Directory>
<FilesMatch "\.php$">
    SetHandler "proxy:fcgi://127.0.0.1:$FPMPORT"
</FilesMatch>
EOF
} > "$STATE/httpd.conf"

cat > "$STATE/php-fpm.conf" <<EOF
[global]
pid = $STATE/php-fpm.pid
error_log = $STATE/logs/php-fpm.log
daemonize = yes
[www]
listen = 127.0.0.1:$FPMPORT
pm = static
pm.max_children = 4
clear_env = no
catch_workers_output = yes
env[APP_ENV] = $APP_ENV_VALUE
env[TMPDIR] = $STATE/tmp
; every request the probe sends carries X-Probe-Id: a probe id in this log means PHP answered it
access.log = $STATE/logs/php-fpm-access.log
access.format = "%{HTTP_X_PROBE_ID}e %s %{REQUEST_URI}e"
php_admin_value[memory_limit] = 512M
php_admin_value[max_execution_time] = 120
EOF

"$0" stop --project="$PROJECT" --port="$PORT" > /dev/null
: > "$STATE/logs/php-fpm-access.log"
"$FPM" -y "$STATE/php-fpm.conf" -p "$STATE"
"$HTTPD" -f "$STATE/httpd.conf" -k start
sleep 1

echo "Apache:   $HTTPD (modules $MODULES), document root $DOCROOT"
echo "PHP-FPM:  $FPM, APP_ENV=$APP_ENV_VALUE"
echo "Base URL: http://127.0.0.1:$PORT"
echo "FPM log:  $STATE/logs/php-fpm-access.log"
echo ""
echo "Check:    php $(cd "$(dirname "$0")" && pwd)/check-delivery.php --base-url=http://127.0.0.1:$PORT --fpm-log=$STATE/logs/php-fpm-access.log"
echo "Stop:     $0 stop --project=$PROJECT"
