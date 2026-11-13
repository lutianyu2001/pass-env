# pass-env for zsh: keeps the variables a directory's .env.pass names in the environment (see bin/pass-env).
#
#   ~/.zshenv    . '<PREFIX>/share/pass-env/hook.zsh'       (or: eval "$(pass-env hook zsh)")
#                zsh reads ~/.zshenv in every shell, interactive or not, so this covers terminals, scripts and each
#                command an agent runs: checked when the shell starts, after each change of directory, and in an
#                interactive shell also before each prompt.
#
# Where no .env.pass is found and none was loaded, the check runs no program. The check keeps $? as it was, and turns
# off xtrace and verbose while it runs, so that `set -x` never prints a value.

typeset -g _PASS_ENV_CMD=${${(%):-%x}:A:h}/../../bin/pass-env
[[ -x $_PASS_ENV_CMD ]] || _PASS_ENV_CMD=${commands[pass-env]:-pass-env}

_pass_env_hook() {
    local ret=$? d=$PWD s
    setopt local_options no_xtrace no_verbose
    if [[ -z ${_PASS_ENV_STAMP-} ]]; then
        while [[ -n $d && $d != / ]] && ! [[ -f $d/.env.pass && -O $d/.env.pass ]]; do d=${d%/*}; done
        [[ -n $d && $d != / ]] || return $ret
    fi
    if s=$("$_PASS_ENV_CMD" export); then eval "$s" || true; fi
    return $ret
}

autoload -Uz add-zsh-hook
add-zsh-hook chpwd _pass_env_hook
[[ -o interactive ]] && add-zsh-hook precmd _pass_env_hook
_pass_env_hook || true
