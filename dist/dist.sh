#!/bin/bash
# Writes the release tarball build/dist/odx-<release>-<os>-<arch>.tar.gz and its .sha256, from the
# release odx and the odinfmt that tests/e2e/odinfmt.sh builds. <release> is what the built odx
# prints. <os>-<arch> is in the words mise uses when it picks a release asset.
# The archive has no top directory, so its bin/ is the bin/ of wherever it is unpacked.
# Exit codes: 1 the formatter build failed, the two READMEs disagree, odx can't print its release,
# or a binary's minimum macOS/Linux isn't met; 2 no release binary, a host that isn't macOS/Linux on
# arm64, a missing tool or no MACOS_MIN; 3 the formatter's source could not be fetched. A cp, tar
# or shasum that fails ends the script with that command's own code.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd -P)
out=$root/${OUT:-build}
odx=$out/release/odx
if [ ! -x "$odx" ]; then
  echo "dist: no release binary; run 'mise run release'" >&2
  exit 2
fi
case "$(uname -s) $(uname -m)" in
"Darwin arm64") platform=macos-arm64 ;;
"Linux x86_64") platform=linux-amd64 ;;
"Linux aarch64") platform=linux-arm64 ;;
*)
  echo "dist: a release is built on macOS on arm64 or on Linux, and this is $(uname -s) $(uname -m)" >&2
  exit 2
  ;;
esac

# First, so a run that fails below can't leave an earlier tarball behind.
rm -rf "$out/dist"

"$root/tests/e2e/odinfmt.sh"

# A toolchain that ignores -minimum-os-version stamps the build host's macOS, and must not ship.
if [ "$(uname -s)" = Darwin ]; then
  for binary in "$odx" "$out/e2e/bin/odinfmt"; do
    minos=$(otool -l "$binary" | awk '$1 == "minos" { print $2; exit }')
    if [ "$minos" != "$MACOS_MIN" ]; then
      echo "dist: $binary runs on macOS ${minos:-unknown} and later, and MACOS_MIN is $MACOS_MIN" >&2
      exit 1
    fi
  done
fi

version=$("$odx" --version)
facts=$(echo "$version" |
  sed -n -E 's/^odx ([0-9]+\.[0-9]+\.[0-9]+), rule set ([0-9]+), odin ([^ ,]+)$/\1 \2 \3/p')
if [ -z "$facts" ]; then
  echo "dist: can't read the release from 'odx --version': $version" >&2
  exit 1
fi
read -r release rule_set compiler <<EOF
$facts
EOF
read -r ols_commit _ _ _ odinfmt_compiler <"$out/e2e/odinfmt.built"

name=odx-$release-$platform.tar.gz
stage=$out/dist/stage
mkdir -p "$stage/bin"
cp "$odx" "$out/e2e/bin/odinfmt" "$stage/bin/"
cp "$root/odinfmt.json" "$stage/odinfmt.json"
cp "$root/odx/ols_printer/LICENSE" "$stage/LICENSE-ols"
cat >"$stage/VERSIONS" <<EOF
odx release: $release
rule set: $rule_set
compiler odx supports: odin $compiler
odinfmt source: https://github.com/DanielGavin/ols at commit $ols_commit
odinfmt built with: odin $odinfmt_compiler
platform: $platform
EOF
if [ "$(uname -s)" = Darwin ]; then
  echo "minimum macOS: $MACOS_MIN" >>"$stage/VERSIONS"
fi

# TODO-UPDATE-COMMENT: the GNU tar branch below sets the owner and group with other flags
# ---
# The same two binaries always give the same bytes: a fixed order, fixed modes, one mtime, no owner
# names, and no name or time in the gzip header. bsdtar 3.5 has no --mtime, so the files are touched.
(
  cd "$stage"
  set -- bin bin/odinfmt bin/odx LICENSE-ols VERSIONS odinfmt.json
  chmod 755 bin bin/odinfmt bin/odx
  chmod 644 LICENSE-ols VERSIONS odinfmt.json
  TZ=UTC touch -t 200001010000.00 "$@"
  if [ "$(uname -s)" = Linux ]; then
    tar -cf - --format=ustar --no-recursion --owner=0 --group=0 --numeric-owner \
      "$@" | gzip -n -9 >"../$name"
  else
    COPYFILE_DISABLE=1 tar -cf - --format ustar --no-recursion --uid 0 --gid 0 --uname '' --gname '' \
      "$@" | gzip -n -9 >"../$name"
  fi
)
rm -rf "$stage"
if command -v shasum >/dev/null; then
  (cd "$out/dist" && shasum -a 256 "$name" >"$name.sha256")
else
  (cd "$out/dist" && sha256sum "$name" >"$name.sha256")
fi
echo "$out/dist/$name"
