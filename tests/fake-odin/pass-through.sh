# Sourced by each fake-odin/<mode>/odin. Every command but `check` goes to the real compiler, so
# odx's version and root probes pass. Control returns to the mode script only for `check`.
if [ "${1-}" != check ]; then
	fakes=$(cd "$(dirname "$0")/.." && pwd -P)
	real=
	IFS=:
	for dir in $PATH; do
		dir=$(cd "${dir:-.}" 2>/dev/null && pwd -P) || continue
		# Skip every fake, not only this one, so two fakes on PATH can't exec each other forever.
		case $dir/ in "$fakes"/*) continue ;; esac
		if [ -f "$dir/odin" ] && [ -x "$dir/odin" ]; then
			real=$dir/odin
			break
		fi
	done
	unset IFS
	if [ -z "$real" ]; then
		echo "fake-odin: no real odin on PATH" >&2
		exit 127
	fi
	if [ "${1-}" = version ]; then
		# The compiler names itself by argv[0], and odx checks the name it ran.
		out=$("$real" version) || exit
		printf '%s version %s\n' "$0" "${out#"$real version "}"
		exit 0
	fi
	exec "$real" "$@"
fi
