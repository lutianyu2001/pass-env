# pass-env for bash: keeps the variables a directory's .env.pass names in the environment (see bin/pass-env).
#
#   ~/.bashrc    . '<PREFIX>/share/pass-env/hook.bash'      (or: eval "$(pass-env hook bash)")
#                interactive shells: checked before each prompt, and after each cd, pushd and popd unless the user
#                already has a function or alias of that name
#   BASH_ENV     the path `pass-env hook bash --path` prints (Claude Code: settings.json "env"): non-interactive bash,
#                such as each command an agent runs, checks at its start and after each cd, pushd and popd in it.
#                Programs the command starts inherit the variables, not the hook.
#
# Where no .env.pass is found and none was loaded, the check runs no program. The check keeps $? as it was, and turns
# off xtrace and verbose while it runs, so that `set -x` never prints a value.

_PASS_ENV_CMD=${BASH_SOURCE[0]%/*}/../../bin/pass-env
[[ -x $_PASS_ENV_CMD ]] || _PASS_ENV_CMD=$(command -v pass-env) || _PASS_ENV_CMD=pass-env

_pass_env_hook() {
    local ret=$? d=$PWD s flags=$-
    if [[ -z ${_PASS_ENV_STAMP-} ]]; then
        while [[ -n $d && $d != / ]] && ! [[ -f $d/.env.pass && -O $d/.env.pass ]]; do d=${d%/*}; done
        [[ -n $d && $d != / ]] || return $ret
    fi
    set +xv
    if s=$("$_PASS_ENV_CMD" export); then eval "$s" || true; fi
    [[ $flags != *v* ]] || set -v
    [[ $flags != *x* ]] || set -x
    return $ret
}

_pass_env_wrap_cd() {
    local f
    for f in cd pushd popd; do
        # shellcheck disable=SC2140  # one function definition built for each name
        declare -F "$f" >/dev/null || alias "$f" >/dev/null 2>&1 ||
            eval "$f() { builtin $f \"\$@\" || return; _pass_env_hook || true; }"
    done
}

if [[ $- == *i* ]]; then
    if [[ $(declare -p PROMPT_COMMAND 2>/dev/null) == 'declare -a'* ]]; then
        [[ " ${PROMPT_COMMAND[*]} " == *' _pass_env_hook '* ]] || PROMPT_COMMAND+=(_pass_env_hook)
    elif [[ ";${PROMPT_COMMAND-};" != *';_pass_env_hook;'* ]]; then
        # shellcheck disable=SC2178,SC2128  # this branch runs only when PROMPT_COMMAND is a string
        PROMPT_COMMAND="_pass_env_hook${PROMPT_COMMAND:+;$PROMPT_COMMAND}"
    fi
    _pass_env_wrap_cd
else
    unset BASH_ENV
    _pass_env_wrap_cd
    _pass_env_hook || true
fi
