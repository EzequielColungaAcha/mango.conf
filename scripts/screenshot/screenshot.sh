#!/usr/bin/env bash
set -euo pipefail

# Ignore duplicate key events / reload-stacked binds firing twice.
LOCK_FILE="${XDG_RUNTIME_DIR:-/tmp}/mango-screenshot.lock"
exec 200>"$LOCK_FILE"
flock -n 200 || exit 0

mkdir -p "$HOME/Pictures/Screenshots"
filepath="$HOME/Pictures/Screenshots/$(date +%Y%m%d%H%M%S).png"

copy_image() {
	cat "$1" | wl-copy --type image/png
}

capture_region() {
	local geometry
	geometry=$(slurp -d) || return 1
	[[ -z "$geometry" ]] && return 1
	grim -g "$geometry" - | tee "$filepath" | wl-copy --type image/png
}

capture_region_annotate() {
	local geometry
	geometry=$(slurp -d) || return 1
	[[ -z "$geometry" ]] && return 1
	grim -g "$geometry" "$filepath"
	satty \
		--filename "$filepath" \
		--output-filename "$filepath" \
		--floating-hack \
		--copy-command 'wl-copy --type image/png' \
		--actions-on-enter save-to-file,save-to-clipboard \
		--early-exit
}

# Mango/dwl stacks new layer surfaces under existing ones, so capture in
# before-freeze-cmd (see wayfreeze README for under-layer compositors).
run_frozen_capture() {
	local capture_cmd=$1
	wayfreeze --before-freeze-timeout 100 --before-freeze-cmd \
		"${capture_cmd}; killall wayfreeze 2>/dev/null" || true
}

case "${1:-fullscreen}" in
region)
	capture_region
	;;
region-annotate)
	capture_region_annotate
	;;
window)
	geometry=$(mmsg get focusing-client | jq -r '"\(.x),\(.y) \(.width)x\(.height)"')
	[[ -z "$geometry" || "$geometry" == "null,null nullxnull" ]] && exit 1
	grim -g "$geometry" "$filepath"
	copy_image "$filepath"
	;;
freeze)
	run_frozen_capture "grim '${filepath}'"
	copy_image "$filepath"
	;;
freeze-region)
	run_frozen_capture "g=\$(slurp -d); [ -n \"\$g\" ] && grim -g \"\$g\" '${filepath}'"
	copy_image "$filepath"
	;;
annotate)
	grim "$filepath"
	satty --filename "$filepath" --output-filename "$filepath" \
		--actions-on-enter save-to-file --early-exit
	copy_image "$filepath"
	;;
*)
	grim "$filepath"
	copy_image "$filepath"
	;;
esac
