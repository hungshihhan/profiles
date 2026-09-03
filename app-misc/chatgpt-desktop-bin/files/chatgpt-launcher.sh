#!/bin/sh
# Gentoo wrapper for the ChatGPT desktop app.
#
# Flags are assembled in this order and prepended to the command line:
#   1. Wayland/IME flags (when built with USE=wayland; disable at runtime
#      with CHATGPT_NO_WAYLAND_FLAGS=1)
#   2. one flag per line from ${XDG_CONFIG_HOME:-~/.config}/chatgpt-flags.conf
#      (blank lines and lines starting with '#' are ignored)
# then control passes to upstream's own launcher, so nothing it does is lost.

APPDIR="@APPDIR@"
USE_WAYLAND=@WAYLAND@

flags_file="${XDG_CONFIG_HOME:-${HOME}/.config}/chatgpt-flags.conf"
cr="$(printf '\r')"
argc=$#

if [ "${USE_WAYLAND}" = true ] && [ -z "${CHATGPT_NO_WAYLAND_FLAGS}" ] \
	&& [ -n "${WAYLAND_DISPLAY}" ]; then
	set -- "$@" --ozone-platform-hint=auto --enable-wayland-ime
fi

if [ -r "${flags_file}" ]; then
	while IFS= read -r flag || [ -n "${flag}" ]; do
		flag=${flag%"${cr}"}
		# trim surrounding whitespace
		lead=${flag%%[![:space:]]*}; flag=${flag#"${lead}"}
		trail=${flag##*[![:space:]]}; flag=${flag%"${trail}"}
		case ${flag} in
			'' | '#'*) continue ;;
		esac
		set -- "$@" "${flag}"
	done < "${flags_file}"
fi

# Rotate the original arguments to the end, behind the injected flags.
while [ "${argc}" -gt 0 ]; do
	arg=$1; shift
	set -- "$@" "${arg}"
	argc=$((argc - 1))
done

if [ -x "${APPDIR}/codex-launcher" ]; then
	exec "${APPDIR}/codex-launcher" "$@"
fi
exec "${APPDIR}/ChatGPT" "$@"
