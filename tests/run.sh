#!/bin/sh
# shellcheck disable=SC2016,SC2164  # single quotes are for the inner shells; a failed cd fails its check
# Tests pass-env in isolation: a throwaway GnuPG home, key and pass store in a temporary directory, removed at the end;
# the user's own keys and store are never touched.
#
#   tests/run.sh            (zsh and fish from PATH; set ZSH=<path> or FISH=<path> to use others; the tests of a shell
#                            that is not there are skipped)
#
# Prints one line per check and exits 1 when any failed. POSIX sh; needs gpg and bash, runs on Linux and macOS.
set -u
repo=$(cd "$(dirname "$0")/.." && pwd -P)
P=$repo/bin/pass-env
HB=$repo/share/pass-env/hook.bash
ZSH=${ZSH:-$(command -v zsh || true)}
FISH=${FISH:-$(command -v fish || true)}
# Under /tmp, not $TMPDIR: gpg-agent puts its socket in GNUPGHOME, and macOS limits a socket path to 104 bytes.
T=$(mktemp -d /tmp/pass-env-test.XXXXXX)
T=$(cd "$T" && pwd -P)
# The cache needs an owner-only directory that, on Linux, is a tmpfs: a fresh one under the real XDG_RUNTIME_DIR.
RUN=$T/run
if [ -n "${XDG_RUNTIME_DIR-}" ] && [ -d "$XDG_RUNTIME_DIR" ] && [ -w "$XDG_RUNTIME_DIR" ]; then
    RUN=$(mktemp -d "$XDG_RUNTIME_DIR/pass-env-test.XXXXXX")
fi
# pass-env caches only where GNU stat says the directory is a tmpfs or ramfs (not on macOS).
case $(stat -f -c %T "$RUN" 2>/dev/null) in tmpfs | ramfs) CACHES=yes ;; *) CACHES=no ;; esac
export GNUPGHOME="$T/gnupg" PASSWORD_STORE_DIR="$T/store"
cleanup() { gpgconf --kill gpg-agent 2>/dev/null; cd /; chmod -R u+rwX "$T" 2>/dev/null; rm -rf "$T" "$RUN"; }
trap cleanup EXIT INT TERM

failures=0
ok() { echo "ok    $1"; }
bad() { echo "FAIL  $1"; [ $# -lt 2 ] || printf '      %s\n' "$2"; failures=$((failures + 1)); }
expect() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "got [$3], want [$2]"; fi; }
contains() { case $3 in *"$2"*) ok "$1" ;; *) bad "$1" "[$3] lacks [$2]" ;; esac; }
lacks() { case $3 in *"$2"*) bad "$1" "[$3] has [$2]" ;; *) ok "$1" ;; esac; }
# clean: a command with only the environment a fresh shell would have, plus the test's store and key. SHLVL is kept:
# without it, bash run with a socket as stdin (as some tools give it) takes itself for a command from rshd and skips
# BASH_ENV.
clean() {
    env -i HOME="$HOME" PATH="$PATH" SHLVL=1 GNUPGHOME="$GNUPGHOME" PASSWORD_STORE_DIR="$PASSWORD_STORE_DIR" "$@"
}
mode_of() { stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1"; }

# --- a throwaway key and store
mkdir -p "$GNUPGHOME" && chmod 700 "$GNUPGHOME"
gpg --batch --pinentry-mode loopback --passphrase '' --quick-gen-key 'pass-env test <test@invalid>' ed25519 cert 1d \
    >/dev/null 2>&1
FPR=$(gpg --list-keys --with-colons 'pass-env test' | awk -F: '$1=="fpr"{print $10; exit}')
gpg --batch --pinentry-mode loopback --passphrase '' --quick-add-key "$FPR" cv25519 encr 1d >/dev/null 2>&1
[ -n "$FPR" ] || { echo "cannot make a test key"; exit 1; }
mkdir -p "$PASSWORD_STORE_DIR" && echo "$FPR" >"$PASSWORD_STORE_DIR/.gpg-id"      # what `pass init` writes
enc() {
    mkdir -p "$(dirname "$PASSWORD_STORE_DIR/$1")"
    printf '%s\nsecond line\n' "$2" |
        gpg -e -r "$FPR" --trust-model always --quiet --yes --batch -o "$PASSWORD_STORE_DIR/$1.gpg"
}
SPECIAL="two words \$HOME 'q' \"dq\" \`bt\` \\back it's"
enc k/one one; enc k/two "$SPECIAL"; enc k/three three; enc k/xt SECRET-XTRACE-VALUE
# shellcheck disable=SC1003  # the value ends with a backslash on purpose
BS1='trailing backslash\'
BS2="two \\\\ backslashes, a quote ' and \$X"
enc k/bs1 "$BS1"; enc k/bs2 "$BS2"
echo garbage >"$PASSWORD_STORE_DIR/k/broken.gpg"
i=1; while [ $i -le 30 ]; do enc many/k$i "v$i"; i=$((i + 1)); done

mkdir -p "$T/A/sub" "$T/B" "$T/C" "$T/none" "$T/many" "$T/zdot" "$T/xt" "$T/uid" "$T/esc" "$T/dup" "$T/unread" \
    "$T/zspecial" "$T/bsl" "$T/fishconf/fish/conf.d"
[ "$RUN" != "$T/run" ] || { mkdir -p "$RUN"; chmod 700 "$RUN"; }
printf '# comment\nX=k/one\nexport Y = k/three  # trailing\n' >"$T/A/.env.pass"
printf '%s\n' 'X=k/two' 'PATH=k/one' 'lower=k/one' 'TMOUT=k/one' 'ANTHROPIC_API_KEY=k/one' 'Z' 'W=k/nope' \
    'V=k/broken' 'U=../../etc/x' >"$T/B/.env.pass"
i=1; while [ $i -le 30 ]; do printf 'K%s=many/k%s\n' $i $i >>"$T/many/.env.pass"; i=$((i + 1)); done
echo 'S=k/xt' >"$T/xt/.env.pass"
printf 'EUID=k/one\nX=k/one\n' >"$T/uid/.env.pass"
printf 'ARGV0=k/one\nTTYIDLE=k/one\nX=k/one\n' >"$T/zspecial/.env.pass"
printf 'X\033]0;pwned\007\033[2J=k/one\n' >"$T/esc/.env.pass"
printf 'X=k/one\nX=k/two\n' >"$T/dup/.env.pass"
echo 'X=k/one' >"$T/unread/.env.pass"
echo ". '$repo/share/pass-env/hook.zsh'" >"$T/zdot/.zshenv"
echo "source '$repo/share/pass-env/hook.fish'" >"$T/fishconf/fish/conf.d/pass-env.fish"
printf 'BS1=k/bs1\nBS2=k/bs2\n' >"$T/bsl/.env.pass"
# fishc: fish with the hook in its conf.d, as ~/.config/fish/conf.d would have it
fishc() { clean XDG_CONFIG_HOME="$T/fishconf" "$FISH" "$@"; }

# --- bash must read BASH_ENV at all, or every check that relies on it fails for a reason outside pass-env
echo 'echo probe-read' >"$T/probe"
probe=$(clean BASH_ENV="$T/probe" bash -c true 2>&1)
expect "bash reads BASH_ENV here (if not, the BASH_ENV checks below say nothing about pass-env)" "probe-read" "$probe"
if [ "$probe" != probe-read ]; then
    echo "      bash: $(command -v bash), flags inside: $(clean bash -c 'echo "$-"'), stdin: $([ -S /dev/stdin ] && echo socket || echo "not a socket")"
    grep -E '^(Uid|Gid|NoNewPrivs|Seccomp):' /proc/self/status 2>/dev/null | sed 's/^/      /'
fi

# --- the hooks: entering, nesting, switching, leaving, coming back
WALK='printf "A:%s,%s|" "$X" "$Y"; cd sub; printf "sub:%s|" "$X"; cd ../../B
printf "B:%s|W=%s V=%s T=%s AK=%s|" "$X" "${W-u}" "${V-u}" "${TMOUT-u}" "${ANTHROPIC_API_KEY-u}"; cd ../none
printf "none:%s n=%s p=%s|" "$X" "${_PASS_ENV_NAMES-u}" "${_PASS_ENV_PREV_X-u}"; cd ../A; printf "A:%s\n" "$X"'
WANT="A:one,three|sub:one|B:$SPECIAL|W=u V=u T=u AK=u|none:orig n=u p=u|A:one"
for xdg in no yes; do
    x=''; [ $xdg = yes ] && x="XDG_RUNTIME_DIR=$RUN"
    cd "$T/A"
    # shellcheck disable=SC2086  # $x is one assignment or nothing
    expect "bash hook walk (XDG_RUNTIME_DIR: $xdg)" "$WANT" "$(clean $x X=orig BASH_ENV="$HB" bash -c "$WALK" 2>/dev/null)"
    if [ -n "$ZSH" ]; then
        # shellcheck disable=SC2086
        expect "zsh hook walk (XDG_RUNTIME_DIR: $xdg)" "$WANT" \
            "$(clean $x X=orig ZDOTDIR="$T/zdot" "$ZSH" -c "$WALK" 2>/dev/null)"
    else
        echo "SKIP  zsh hook walk (XDG_RUNTIME_DIR: $xdg): no zsh"
    fi
done
if [ -n "$FISH" ]; then
    FWALK='printf "%s|" "$X" "$Y"; cd sub; printf "%s|" "$X"; cd ../../B; printf "%s|" "$X"; cd ../none
printf "%s|" "$X"; set -q _PASS_ENV_NAMES; and echo set; or echo u'
    for xdg in no yes; do
        x=''; [ $xdg = yes ] && x="XDG_RUNTIME_DIR=$RUN"
        cd "$T/A"
        # shellcheck disable=SC2086  # $x is one assignment or nothing
        expect "fish hook walk (XDG_RUNTIME_DIR: $xdg)" "one|three|one|$SPECIAL|orig|u" \
            "$(clean $x X=orig XDG_CONFIG_HOME="$T/fishconf" "$FISH" -c "$FWALK" 2>/dev/null)"
    done
else
    echo "SKIP  fish hook walk: no fish"
fi
cd "$T/bsl"
expect "bash: values with backslashes and quotes" "$BS1|$BS2" \
    "$(clean BASH_ENV="$HB" bash -c 'printf "%s|%s" "$BS1" "$BS2"')"
[ -z "$ZSH" ] || expect "zsh: values with backslashes and quotes" "$BS1|$BS2" \
    "$(clean ZDOTDIR="$T/zdot" "$ZSH" -c 'printf "%s|%s" "$BS1" "$BS2"')"
[ -z "$FISH" ] || expect "fish: values with backslashes and quotes" "$BS1|$BS2" \
    "$(fishc -c 'printf "%s|%s" "$BS1" "$BS2"')"

cd "$T/B"
msgs=$(clean BASH_ENV="$HB" bash -c true 2>&1)
contains "refuses PATH" "PATH may not be set from a secret (a shell, a loader or a common tool acts on it)" "$msgs"
contains "refuses lower case" "lower may not be set from a secret (names are upper case)" "$msgs"
contains "refuses TMOUT" "TMOUT may not be set" "$msgs"
contains "refuses ANTHROPIC_API_KEY" "ANTHROPIC_API_KEY may not be set from a secret (it would make every Claude Code" "$msgs"
contains "reports a line that is not a mapping" "not NAME=ENTRY (Z)" "$msgs"
contains "reports a missing entry" "W: no entry k/nope" "$msgs"
contains "reports an entry it cannot decrypt" "V: cannot decrypt k/broken" "$msgs"
contains "reports a line naming a path outside the store" "not NAME=ENTRY (U)" "$msgs"
lacks "prints no value" "$SPECIAL" "$msgs"

cd "$T/none"
expect "bash with set -euo pipefail" "one|unset" \
    "$(clean BASH_ENV="$HB" bash -c 'set -euo pipefail; cd ../A; printf "%s|" "$X"; cd ../C; echo "${X-unset}"')"
[ -z "$ZSH" ] || expect "zsh with err_exit and no_unset" "one|unset" \
    "$(clean ZDOTDIR="$T/zdot" "$ZSH" -c 'setopt err_exit no_unset; cd ../A; printf "%s|" "$X"; cd ../C; echo "${X-unset}"')"
expect "a program the command starts inherits the variables, not the hook" "one|builtin" \
    "$(cd "$T/A" && clean BASH_ENV="$HB" bash -c 'bash -c "printf \"%s|\" \"\$X\"; type -t cd"')"

# --- xtrace never shows a value
cd "$T/xt"
lacks "bash -x prints no value" "SECRET-XTRACE" "$(clean BASH_ENV="$HB" bash -x -c 'test -n "${S:+x}"' 2>&1)"
lacks "set -x then cd prints no value" "SECRET-XTRACE" \
    "$(cd "$T/none" && clean BASH_ENV="$HB" bash -c 'set -x; cd ../xt; test -n "${S:+x}"' 2>&1)"
expect "xtrace is back on after the hook" "on" \
    "$(cd "$T/none" && clean BASH_ENV="$HB" bash -c 'set -x; cd ../xt; case $- in *x*) echo on ;; esac' 2>/dev/null)"
[ -z "$ZSH" ] || lacks "zsh -x prints no value" "SECRET-XTRACE" \
    "$(clean ZDOTDIR="$T/zdot" "$ZSH" -x -c 'test -n "${S:+x}"' 2>&1)"
[ -z "$FISH" ] || lacks "fish_trace prints no value" "SECRET-XTRACE" \
    "$(cd "$T/none" && fishc -c 'set -g fish_trace 1; cd ../xt; set -q S' 2>&1)"
[ -z "$FISH" ] || expect "fish_trace is still on after the hook" "1" \
    "$(cd "$T/none" && fishc -c 'set -g fish_trace 1; cd ../xt; set -g fish_trace; echo 1' 2>/dev/null)"

# --- names a shell sets itself are refused, and a script with err_exit goes on
cd "$T/none"
[ -z "$ZSH" ] || expect "zsh err_exit survives a .env.pass naming EUID" "reached one" \
    "$(clean ZDOTDIR="$T/zdot" "$ZSH" -c 'setopt err_exit; cd ../uid; echo "reached $X"' 2>/dev/null)"
expect "bash survives a .env.pass naming EUID" "reached one" \
    "$(clean BASH_ENV="$HB" bash -c 'set -e; cd ../uid; echo "reached $X"' 2>/dev/null)"
contains "refuses ARGV0 and TTYIDLE (zsh)" "TTYIDLE may not be set" \
    "$(cd "$T/zspecial" && clean BASH_ENV="$HB" bash -c 'echo "ARGV0=${ARGV0-unset}"' 2>&1)"
[ -z "$ZSH" ] || expect "zsh with ARGV0 and TTYIDLE in .env.pass still loads the rest" "one" \
    "$(clean ZDOTDIR="$T/zdot" "$ZSH" -c 'setopt err_exit; cd ../zspecial; echo "$X"' 2>/dev/null)"

# --- no terminal control from .env.pass reaches stderr
esc=$(printf '\033')
lacks "escape sequences in .env.pass are not echoed" "$esc" "$(cd "$T/esc" && clean BASH_ENV="$HB" bash -c true 2>&1)"
escdir="$T/x$(printf '\033]0;pwned\007')"
mkdir -p "$escdir" && printf 'Z\n' >"$escdir/.env.pass"
lacks "escape sequences in a directory name are not echoed" "$esc" \
    "$(cd "$escdir" && clean BASH_ENV="$HB" bash -c true 2>&1)"

# --- a name mapped twice
cd "$T/dup"
expect "a name mapped twice keeps its first line" "one" "$(clean BASH_ENV="$HB" bash -c 'echo "$X"' 2>/dev/null)"
contains "a name mapped twice is reported" "X is mapped more than once" "$(clean BASH_ENV="$HB" bash -c true 2>&1)"
contains "run refuses a name mapped twice" "nothing ran" "$(clean "$P" run sh -c 'echo RAN' 2>&1)"

# --- an unreadable .env.pass
if [ "$(id -u)" != 0 ]; then
    chmod 000 "$T/unread/.env.pass"
    out=$(cd "$T/unread" && clean BASH_ENV="$HB" bash -c 'echo "went on X=${X-unset}"' 2>&1)
    contains "an unreadable .env.pass is reported" "cannot read it" "$out"
    contains "an unreadable .env.pass loads nothing and stops nothing" "went on X=unset" "$out"
    chmod 644 "$T/unread/.env.pass"
fi

cd "$T"
expect "interactive bash: before each prompt" "one|unset" "$(clean bash --norc -ic ". '$HB'
cd A; eval \"\$PROMPT_COMMAND\"; printf '%s|' \"\$X\"; cd ../none; eval \"\$PROMPT_COMMAND\"; echo \"\${X-unset}\"" \
    2>/dev/null | tail -n 1)"
expect "interactive bash: a command after cd on the same line has the new values" "one" \
    "$(clean bash --norc -ic ". '$HB'; cd A && echo \"\$X\"" 2>/dev/null | tail -n 1)"
expect "interactive bash: the prompt hook keeps \$?" "status=1" \
    "$(clean bash --norc -ic "show() { echo status=\$?; }; PROMPT_COMMAND=show; . '$HB'; false; eval \"\$PROMPT_COMMAND\"" \
    2>/dev/null | tail -n 1)"
[ -z "$ZSH" ] || expect "interactive zsh: chpwd, and precmd after an edit" "one|three|unset" \
    "$(clean ZDOTDIR="$T/zdot" "$ZSH" -ic 'cd A; printf "%s|" "$X"; cp .env.pass ../A.bak
printf "X=k/three\n" > .env.pass; for f in $precmd_functions; do $f; done; printf "%s|" "$X"; cp ../A.bak .env.pass
cd ../none; echo "${X-unset}"' 2>/dev/null | tail -n 1)"

# The fish_prompt handler is called directly: emitting fish_prompt also runs fish's own handlers, which print.
[ -z "$FISH" ] || expect "fish: PWD event, and the fish_prompt handler after an edit" "one|three|unset" \
    "$(cd "$T" && fishc -c 'cd A; printf "%s|" "$X"; cp .env.pass ../A.bak; printf "X=k/three\n" > .env.pass
_pass_env_prompt; printf "%s|" "$X"; cp ../A.bak .env.pass; cd ../none; set -q X; and echo $X; or echo unset' \
    2>/dev/null)"

# --- a failed decryption is tried again at the next check
mkdir -p "$T/fakegpg"
cat >"$T/fakegpg/gpg" <<EOF
#!/bin/sh
[ -e '$T/fail' ] && exit 2
exec '$(command -v gpg)' "\$@"
EOF
chmod +x "$T/fakegpg/gpg"
for wait in default 0; do
    : >"$T/fail"
    extra=''
    if [ $wait = 0 ]; then want="unset|one" what="is tried again at the next prompt with PASS_ENV_RETRY_SECONDS=0"
        extra=PASS_ENV_RETRY_SECONDS=0
    else want="unset|unset" what="is not tried again within the minute"; fi
    # shellcheck disable=SC2086  # $extra is one assignment or nothing
    expect "a failed decryption $what" "$want" \
        "$(cd "$T" && env -i HOME="$HOME" PATH="$T/fakegpg:$PATH" SHLVL=1 GNUPGHOME="$GNUPGHOME" \
        PASSWORD_STORE_DIR="$PASSWORD_STORE_DIR" $extra \
        bash --norc -ic ". '$HB'; cd A; eval \"\$PROMPT_COMMAND\"; printf '%s|' \"\${X-unset}\"; command rm -f '$T/fail'
eval \"\$PROMPT_COMMAND\"; echo \"\${X-unset}\"" 2>/dev/null | tail -n 1)"
done
command rm -f "$T/fail"

# --- many entries, decrypted in parallel, keep their order; the cache
cd "$T/many"
expect "30 entries in order" "v1 v15 v30 30" \
    "$(clean XDG_RUNTIME_DIR="$RUN" BASH_ENV="$HB" bash -c 'echo "$K1 $K15 $K30 $(echo $_PASS_ENV_NAMES | wc -w | tr -d " ")"')"
if [ $CACHES = yes ]; then
    expect "cache directory and files are owner only" "700 600" \
        "$(mode_of "$RUN/pass-env") $(for f in "$RUN/pass-env"/*; do mode_of "$f"; done | sort -u | tr '\n' ' ' | sed 's/ $//')"
else
    expect "no cache where the file system cannot be told to be in memory" "no" \
        "$([ -e "$RUN/pass-env" ] && echo yes || echo no)"
fi
# the parallel path is the one used: one gpg call per entry
cat >"$T/fakegpg/gpg" <<EOF
#!/bin/sh
echo call >>'$T/gpgcalls'
exec '$(command -v gpg)' "\$@"
EOF
: >"$T/gpgcalls"
cd "$T/many" && clean env PATH="$T/fakegpg:$PATH" "$P" run sh -c true
expect "30 entries take 30 gpg calls (the parallel output is accepted)" "30" "$(wc -l <"$T/gpgcalls" | tr -d ' ')"
expect "no build files left behind" "0" "$(find "$RUN" -name '*.tmp.*' | wc -l | tr -d ' ')"
mkdir -p "$T/opendir" && chmod 755 "$T/opendir"
clean XDG_RUNTIME_DIR="$T/opendir" BASH_ENV="$HB" bash -c true 2>/dev/null
expect "no cache in a directory others can read" "0" "$(find "$T/opendir" -type f | wc -l | tr -d ' ')"
cd "$T/A"
before=$(clean XDG_RUNTIME_DIR="$RUN" BASH_ENV="$HB" bash -c 'echo "$X"')
enc k/one ONE-NEW
expect "an edited entry is not answered from the cache" "one ONE-NEW" \
    "$before $(clean XDG_RUNTIME_DIR="$RUN" BASH_ENV="$HB" bash -c 'echo "$X"')"
enc k/one one
mkdir -p "$T/same" && echo 'X=k/same' >"$T/same/.env.pass"
enc k/same OLD-VALUE1
before=$(cd "$T/same" && clean XDG_RUNTIME_DIR="$RUN" BASH_ENV="$HB" bash -c 'echo "$X"')
enc k/same NEW-VALUE1
expect "an entry rewritten to the same size within a second is not answered from the cache" "OLD-VALUE1 NEW-VALUE1" \
    "$before $(cd "$T/same" && clean XDG_RUNTIME_DIR="$RUN" BASH_ENV="$HB" bash -c 'echo "$X"')"

# --- long values: more than a pipe takes in one write (20 kB each: macOS limits a process's arguments and
# environment together to 1 MB)
long=''
i=1; while [ $i -le 16 ]; do
    v=$(printf "%020000d" $i)
    enc long/k$i "$v"; long=$long$v
    printf 'L%s=long/k%s\n' $i $i >>"$T/long.pass"
    i=$((i + 1))
done
want=$(printf '%s' "$long" | cksum)
i=1; while [ $i -le 3 ]; do
    expect "16 values of 20 kB, run $i" "$want" "$(clean "$P" run -f "$T/long.pass" sh -c \
        'printf "%s" "$L1$L2$L3$L4$L5$L6$L7$L8$L9$L10$L11$L12$L13$L14$L15$L16" | cksum')"
    i=$((i + 1))
done

# --- run
cd "$T"
expect "run with NAME=ENTRY" "$SPECIAL" "$(clean "$P" run S=k/two -- sh -c 'printf "%s" "$S"')"
expect "run with -f" "one three" "$(clean "$P" run -f A/.env.pass sh -c 'echo "$X $Y"')"
expect "run with the nearest .env.pass" "one" "$(cd A/sub && clean "$P" run sh -c 'echo "$X"')"
out=$(clean "$P" run W=k/nope sh -c 'echo RAN' 2>&1); st=$?
contains "run refuses a missing entry and runs nothing" "nothing ran" "$out"
lacks "run did not run the command" "RAN" "$out"
expect "run's exit status when it refuses" "1" "$st"
out=$(cd "$T/none" && clean "$P" run sh -c 'echo RAN' 2>&1)
contains "run with no mapping at all" "no .env.pass here or above it" "$out"
expect "run passes the command's exit status" "7" "$(clean "$P" run X=k/one sh -c 'exit 7'; echo $?)"

# --- get, git-credential, status, hook
expect "get prints the first line" "three" "$(clean "$P" get k/three)"
contains "get refuses a path out of the store" "not an entry name" "$(clean "$P" get ../x 2>&1)"
contains "get reports a missing entry" "no entry k/nope" "$(clean "$P" get k/nope 2>&1)"
expect "git-credential answers get" "password=three" \
    "$(printf 'protocol=https\nhost=example.org\n\n' | clean "$P" git-credential k/three get)"
expect "git-credential ignores store" "" "$(printf 'password=x\n\n' | clean "$P" git-credential k/three store)"
st=$(cd "$T/A/sub" && clean "$P" status)
contains "status names the file" "applies here: $T/A/.env.pass" "$st"
contains "status lists the mapping" "Y = k/three" "$st"
lacks "status prints no value" "one" "$(printf '%s' "$st" | grep -v 'k/one')"
expect "hook --path" "$repo/share/pass-env/hook.bash" "$(clean "$P" hook bash --path)"
[ -z "$FISH" ] || expect "the fish hook line works when sourced" "one" \
    "$(cd "$T/A" && clean "$FISH" -c "'$P' hook fish | source; echo \$X" 2>/dev/null)"
expect "the hook line works when evaluated" "one" \
    "$(cd "$T/A" && clean bash --norc -ic "eval \"\$('$P' hook bash)\"; eval \"\$PROMPT_COMMAND\"; echo \"\$X\"" 2>/dev/null | tail -n 1)"

# --- init: a block in each shell's startup file, in a home of its own
H=$T/home
mkdir -p "$H" "$T/fakebin" "$T/minbin"
printf '#!/bin/sh\nexit 0\n' >"$T/fakebin/pass" && chmod +x "$T/fakebin/pass"
printf '# my own line\nalias ll="ls -l"\n' >"$H/.rcorig"
case $(uname -s) in Darwin) BRC=$H/.bash_profile BLOGIN=-l ;; *) BRC=$H/.bashrc BLOGIN= ;; esac
cp "$H/.rcorig" "$BRC"
home() { env -i HOME="$H" PATH="$T/fakebin:$PATH" SHLVL=1 GNUPGHOME="$GNUPGHOME" PASSWORD_STORE_DIR="$PASSWORD_STORE_DIR" "$@"; }
# without pass on PATH (only what init needs before it checks)
for c in sh awk uname dirname cat sed tr grep gpg; do ln -sf "$(command -v $c)" "$T/minbin/$c"; done
out=$(env -i HOME="$H" PATH="$T/minbin" SHLVL=1 sh "$P" init bash 2>&1); st=$?
contains "init refuses when pass is not installed" "not installed: pass" "$out"
expect "init without pass changes nothing" "1 same" "$st $(cmp -s "$H/.rcorig" "$BRC" && echo same)"
home "$P" init bash zsh fish --dry-run >/dev/null
expect "init --dry-run changes nothing" "same no no" \
    "$(cmp -s "$H/.rcorig" "$BRC" && echo same) $([ -e "$H/.zshenv" ] && echo yes || echo no) $([ -e "$H/.config/fish/conf.d/pass-env.fish" ] && echo yes || echo no)"
home "$P" init bash zsh fish >/dev/null
expect "init writes one block per startup file" "1 1 1" \
    "$(grep -c '^# >>> pass-env init >>>$' "$BRC") $(grep -c '^# >>> pass-env init >>>$' "$H/.zshenv") $(grep -c '^# >>> pass-env init >>>$' "$H/.config/fish/conf.d/pass-env.fish")"
contains "init keeps what the file had" 'alias ll="ls -l"' "$(cat "$BRC")"
before=$(cksum <"$BRC")
contains "init a second time changes nothing" "already set up" "$(home "$P" init bash)"
expect "a second init leaves the file as it was" "$before" "$(cksum <"$BRC")"
# shellcheck disable=SC2086  # $BLOGIN is -l or nothing
expect "after init, a new bash has the project's keys" "one" \
    "$(cd "$T/A" && home bash $BLOGIN -ic 'eval "$PROMPT_COMMAND"; echo "$X"' 2>/dev/null | tail -n 1)"
[ -z "$ZSH" ] || expect "after init, a new zsh has the project's keys" "one" \
    "$(cd "$T/A" && home "$ZSH" -c 'echo "$X"' 2>/dev/null)"
[ -z "$FISH" ] || expect "after init, a new fish has the project's keys" "one" \
    "$(cd "$T/A" && home "$FISH" -c 'echo $X' 2>/dev/null)"
# a block moved by the user stays where it is; a begin line without an end line loses nothing
awk -v b='# >>> pass-env init >>>' -v e='# <<< pass-env init <<<' '
    $0 == b { skip = 1 } skip { blk = blk $0 "\n"; if ($0 == e) skip = 0; next } { body = body $0 "\n" }
    END { printf "%s", blk; printf "%s", body; print "# last line" }' "$BRC" >"$T/moved" && cp "$T/moved" "$BRC"
home "$P" init bash >/dev/null
expect "init replaces a block where it stands" "1 # last line" \
    "$(grep -nxF '# >>> pass-env init >>>' "$BRC" | cut -d: -f1) $(tail -n 1 "$BRC")"
printf '# >>> pass-env init >>>\nexport KEEP=1\n' >"$T/broken"
before=$(cat "$T/broken")
cp "$T/broken" "$T/broken.rc"
expect "a begin line without an end line keeps what follows it" "$before" \
    "$(env -i HOME="$H" PATH="$T/fakebin:$PATH" ZDOTDIR="$T/zd" sh -c 'mkdir -p "$ZDOTDIR" && cp "$1" "$ZDOTDIR/.zshenv" && "$2" init zsh >/dev/null && "$2" init --undo zsh >/dev/null && cat "$ZDOTDIR/.zshenv"' - "$T/broken.rc" "$P")"
printf '%s\n' '# my own line' 'alias ll="ls -l"' >"$BRC"
home "$P" init bash >/dev/null
home "$P" init --undo >/dev/null
expect "init --undo gives the startup file back as it was" "same" "$(cmp -s "$H/.rcorig" "$BRC" && echo same)"
expect "init --undo removes the files that held only its block" "no no" \
    "$([ -e "$H/.zshenv" ] && echo yes || echo no) $([ -e "$H/.config/fish/conf.d/pass-env.fish" ] && echo yes || echo no)"
: >"$T/linked.zshenv" && ln -s "$T/linked.zshenv" "$H/.zshenv"
lacks "init without bash does not speak of BASH_ENV" "BASH_ENV" "$(home "$P" init zsh)"
home "$P" init --undo zsh >/dev/null
expect "init --undo keeps a startup file that is a symbolic link" "link" "$([ -L "$H/.zshenv" ] && echo link || echo gone)"
rm -f "$H/.zshenv"

# --- the version: git describe in a checkout, written by git archive into a release archive, and by install.sh
if command -v git >/dev/null 2>&1; then
    V=$T/vrepo
    mkdir -p "$V" "$T/varch"
    cp -R "$repo/bin" "$repo/share" "$repo/install.sh" "$repo/.gitattributes" "$V/"
    g() { git -C "$V" -c user.name=test -c user.email=test@invalid -c commit.gpgsign=false -c tag.gpgsign=false "$@"; }
    g init -q && g add -A && g commit -qm one && g tag v9.8.7
    expect "version in a checkout, from git describe" "pass-env 9.8.7" "$(clean "$V/bin/pass-env" version)"
    g archive v9.8.7 | tar -x -C "$T/varch"
    expect "version in a release archive, written by git archive" "pass-env 9.8.7" \
        "$(clean "$T/varch/bin/pass-env" version)"
    "$V/install.sh" --prefix "$T/vpfx1" >/dev/null
    expect "install.sh from a checkout writes its version" "pass-env 9.8.7" "$(clean "$T/vpfx1/bin/pass-env" version)"
    "$T/varch/install.sh" --prefix "$T/vpfx2" >/dev/null
    expect "install.sh from an archive keeps its version" "pass-env 9.8.7" "$(clean "$T/vpfx2/bin/pass-env" version)"
    PASS_ENV_VERSION=1.2.3 "$T/varch/install.sh" --prefix "$T/vpfx3" >/dev/null
    expect "PASS_ENV_VERSION decides the installed version" "pass-env 1.2.3" "$(clean "$T/vpfx3/bin/pass-env" version)"
    g commit -q --allow-empty -m two
    contains "a commit after the tag shows in the version" "pass-env 9.8.7-1-g" "$(clean "$V/bin/pass-env" version)"
else
    echo "SKIP  version: no git"
fi

# --- install.sh
inst=$T/prefix
"$repo/install.sh" --prefix "$inst" >/dev/null
expect "install puts the program and hooks in place" "755 644 644 644" \
    "$(mode_of "$inst/bin/pass-env") $(mode_of "$inst/share/pass-env/hook.bash") $(mode_of "$inst/share/pass-env/hook.zsh") $(mode_of "$inst/share/pass-env/hook.fish")"
expect "the installed hook finds the installed program" "one" \
    "$(cd "$T/A" && clean BASH_ENV="$("$inst/bin/pass-env" hook bash --path)" bash -c 'echo "$X"')"
[ -z "$FISH" ] || expect "the installed fish hook finds the installed program" "one" \
    "$(cd "$T/A" && clean "$FISH" -c "source '$inst/share/pass-env/hook.fish'; echo \$X" 2>/dev/null)"
"$repo/install.sh" --prefix "$inst" --uninstall >/dev/null
expect "uninstall removes what install put there" "0" "$(find "$inst" -type f | wc -l | tr -d ' ')"

echo
if [ "$failures" -eq 0 ]; then echo "all checks passed"; else echo "$failures check(s) failed"; exit 1; fi
