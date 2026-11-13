#!/bin/sh
# Installs pass-env for the current user, with no root: the program into <PREFIX>/bin, the shell hooks into
# <PREFIX>/share/pass-env. It changes no shell startup file; it prints the lines to add.
#
#   ./install.sh [--prefix <PREFIX>]              install (PREFIX defaults to ~/.local)
#   ./install.sh [--prefix <PREFIX>] --uninstall  remove exactly what install put there
#
# The installed program carries its version: the one PASS_ENV_VERSION gives (as the conda recipe does), or the one a
# release archive already has, or what `git describe` says of this checkout, or "unknown".
#
# POSIX sh.
set -eu
prefix=${PREFIX:-$HOME/.local}
uninstall=0
while [ $# -gt 0 ]; do
    case $1 in
        --prefix) [ $# -ge 2 ] || { echo "install.sh: --prefix needs a directory" >&2; exit 2; }; prefix=$2; shift 2 ;;
        --uninstall) uninstall=1; shift ;;
        -h | --help) sed -n '2,8p' "$0"; exit 0 ;;
        *) echo "install.sh: unknown argument $1" >&2; exit 2 ;;
    esac
done
here=$(cd "$(dirname "$0")" && pwd -P)
files='bin/pass-env share/pass-env/hook.bash share/pass-env/hook.zsh share/pass-env/hook.fish'

if [ "$uninstall" = 1 ]; then
    for f in $files; do
        if [ -e "$prefix/$f" ]; then rm -f "$prefix/$f"; echo "removed $prefix/$f"; fi
    done
    rmdir "$prefix/share/pass-env" 2>/dev/null || true
    echo "Remove the pass-env lines from ~/.bashrc, ~/.zshenv, ~/.config/fish/conf.d and BASH_ENV, if you added them."
    exit 0
fi

version=${PASS_ENV_VERSION:-}
if [ -z "$version" ] && grep -q "^PASS_ENV_VERSION='\$Format" "$here/bin/pass-env"; then
    version=$(git -C "$here" describe --tags --match 'v[0-9]*' 2>/dev/null) || version=unknown
fi
for f in $files; do
    mkdir -p "$prefix/$(dirname "$f")"
    case $f in bin/*) mode=755 ;; *) mode=644 ;; esac
    if [ "$f" = bin/pass-env ] && [ -n "$version" ]; then
        sed "s|^PASS_ENV_VERSION=.*|PASS_ENV_VERSION='${version#v}'|" "$here/$f" >"$prefix/$f.tmp.$$"
    else
        cp "$here/$f" "$prefix/$f.tmp.$$"
    fi
    chmod "$mode" "$prefix/$f.tmp.$$" && mv -f "$prefix/$f.tmp.$$" "$prefix/$f"
    echo "installed $prefix/$f"
done

case :$PATH: in *:"$prefix/bin":*) ;; *) echo "Note: $prefix/bin is not on PATH; add it before the lines below." ;; esac
# The hook lines name the files themselves, so they work before $prefix/bin is on PATH (on macOS, PATH is often
# extended only after ~/.zshenv has run).
cat <<EOF

To hook pass-env into your shells, add:
  ~/.bashrc:  . '$prefix/share/pass-env/hook.bash'
  ~/.zshenv:  . '$prefix/share/pass-env/hook.zsh'
  fish:       source '$prefix/share/pass-env/hook.fish'   (in ~/.config/fish/conf.d/pass-env.fish)
For commands run by tools that start non-interactive bash (such as Claude Code), set BASH_ENV to:
  $prefix/share/pass-env/hook.bash
EOF
