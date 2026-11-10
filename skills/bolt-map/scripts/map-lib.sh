#!/usr/bin/env bash
# Shared by scaffold.sh and verify.sh.

# shellcheck disable=SC2034  # used by verify.sh, which sources this file
MAP_TRANSLATION_KEYS="map.directions map.title map.marker map.zoom_in map.zoom_out map.reset_view map.attribution map.feedback map.scroll_windows map.scroll_mac map.two_fingers"

# Finds the Bolt project root from the current directory upwards; prints nothing when there is none.
find_project_root() {
    local dir
    dir="$(pwd)"
    while [ "$dir" != "/" ]; do
        if [ -f "$dir/config/services.yaml" ]; then
            echo "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
}

active_theme() {
    grep -E '^theme:' "$1/config/bolt/config.yaml" | head -n 1 \
        | sed -E 's/^theme:[[:space:]]*//; s/[[:space:]]*#.*$//' | tr -d "\"' "
}

# Value of a key one level below a top-level block in theme.yaml.
yaml_block_value() {
    awk -v block="$2" -v key="$3" '
        $0 ~ "^" block ":" { inside = 1; next }
        inside && /^[^[:space:]#]/ { inside = 0 }
        inside && $0 ~ "^[[:space:]]+" key ":" {
            sub("^[[:space:]]+" key ":[[:space:]]*", "")
            sub("[[:space:]]*#.*$", "")
            gsub(/["\047[:space:]]/, "")
            print
            exit
        }
    ' "$1"
}
