#!/usr/bin/env bash
set -e

# bolt-edit-links scaffold: adds or upgrades the `edit` macro in macros.twig (the only file it
# writes), then prints the list of places in the theme that still need a pencil.
# Run it from the root of the Bolt project; safe to repeat.

if [ ! -f "./config/services.yaml" ]; then
    echo "ERROR: run this from the root of the Bolt project (config/services.yaml not found)."
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

php "$SCRIPT_DIR/edit-links.php" install "$(pwd)"
echo ""
php "$SCRIPT_DIR/edit-links.php" scan "$(pwd)" "$@"
