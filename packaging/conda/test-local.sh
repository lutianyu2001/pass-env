#!/bin/sh
# Tests the conda package as `pixi global` installs it, without touching the user's own pixi or startup files: builds
# the package from this checkout, installs it with PIXI_HOME and HOME pointing into a temporary directory, and checks
# that the hooks are found through pixi's launcher, that `init` points the shells at the installed hooks, and that an
# update keeps that path and an uninstall leaves a shell that still starts. Removes everything at the end.
#
#   packaging/conda/test-local.sh
#
# Needs pixi (it fetches rattler-build with `pixi exec`; RATTLER_BUILD=rattler-build==<VERSION> pins it) and bash;
# POSIX sh, Linux and macOS.
set -u
repo=$(cd "$(dirname "$0")/../.." && pwd -P)
T=$(mktemp -d /tmp/pass-env-pixi.XXXXXX)
T=$(cd "$T" && pwd -P)
trap 'cd /; rm -rf "$T"' EXIT INT TERM
PIXI=$(command -v pixi || echo "$HOME/.pixi/bin/pixi")
failures=0
ok() { echo "ok    $1"; }
bad() { echo "FAIL  $1"; [ $# -lt 2 ] || printf '      %s\n' "$2"; failures=$((failures + 1)); }
expect() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "got [$3], want [$2]"; fi; }

build() {   # build VERSION: the package into $T/channel
    PASS_ENV_VERSION=$1 "$PIXI" exec -s "${RATTLER_BUILD:-rattler-build}" rattler-build build \
        --recipe "$repo/packaging/conda/recipe.yaml" \
        --output-dir "$T/channel" >"$T/build-$1.log" 2>&1 || { cat "$T/build-$1.log"; exit 1; }
}
H=$T/home
mkdir -p "$H" "$T/fakebin"
printf '#!/bin/sh\nexit 0\n' >"$T/fakebin/pass" && chmod +x "$T/fakebin/pass"   # init only checks it is there
# px: pixi with its own home; inside: a fresh environment with that home
px() { PIXI_HOME="$T/pixi" "$PIXI" "$@"; }
inside() { env -i HOME="$H" PATH="$T/pixi/bin:$T/fakebin:$PATH" SHLVL=1 "$@"; }

build 0.1.0
px global install --channel "file://$T/channel" pass-env >"$T/install.log" 2>&1 || { cat "$T/install.log"; exit 1; }
expect "pixi global install puts pass-env on PATH" "pass-env 0.1.0" "$(inside pass-env version)"
hook=$(inside pass-env hook bash --path 2>&1)
expect "the hook is found through pixi's launcher" "$T/pixi/envs/pass-env/share/pass-env/hook.bash" "$hook"

inside pass-env init bash zsh fish >"$T/init.log" 2>&1
case $(uname -s) in Darwin) brc=$H/.bash_profile login=-l ;; *) brc=$H/.bashrc login= ;; esac
expect "init points bash at the installed hook" "1" "$(grep -cF "$T/pixi/envs/pass-env/share/pass-env/hook.bash" "$brc")"
# shellcheck disable=SC2086,SC2016  # $login is -l or nothing; the inner bash expands $_PASS_ENV_CMD
expect "a new bash loads the installed hook" "$T/pixi/envs/pass-env/bin/pass-env" \
    "$(cd "$T" && inside bash $login -ic 'echo "$_PASS_ENV_CMD"' 2>/dev/null | tail -n 1 | sed 's#/share/pass-env/\.\./\.\./#/#')"

build 0.1.1
px global update pass-env >"$T/update.log" 2>&1 || { cat "$T/update.log"; exit 1; }
expect "pixi global update brings the new version" "pass-env 0.1.1" "$(inside pass-env version)"
expect "the hook keeps its path after the update" "$hook" "$(inside pass-env hook bash --path 2>&1)"

px global uninstall pass-env >"$T/uninstall.log" 2>&1 || { cat "$T/uninstall.log"; exit 1; }
# shellcheck disable=SC2086
expect "after an uninstall, a new bash starts with no error from the block" "started" \
    "$(cd "$T" && inside bash $login -ic 'echo started' 2>&1 | grep -v 'job control\|process group' | tail -n 1)"

echo
if [ "$failures" -eq 0 ]; then echo "all checks passed"; else echo "$failures check(s) failed"; exit 1; fi
