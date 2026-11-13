# pass-env for fish: keeps the variables a directory's .env.pass names in the environment (see bin/pass-env).
#
#   ~/.config/fish/conf.d/pass-env.fish    source '<PREFIX>/share/pass-env/hook.fish'
#                                          (or: pass-env hook fish | source)
#   fish reads conf.d in every fish, interactive or not, so this covers terminals, scripts and each command an agent
#   runs: checked when the shell starts, after each change of directory, and in an interactive shell also before each
#   prompt.
#
# Where no .env.pass is found and none was loaded, the check runs no program. fish_trace is off while it runs, so that
# tracing never prints a value. Written for fish 3.0 and later (no `path`, which came in 3.5).

set -g _pass_env_cmd (string replace -r '/[^/]*$' '' -- (status current-filename))/../../bin/pass-env
if not test -x $_pass_env_cmd
    set _pass_env_cmd (command -s pass-env); or set _pass_env_cmd pass-env
end

function _pass_env_hook --on-variable PWD
    set -l fish_trace
    if test -z "$_PASS_ENV_STAMP"
        set -l d $PWD
        while test -n "$d" -a "$d" != /
            if test -f "$d/.env.pass" -a -O "$d/.env.pass"
                break
            end
            set d (string replace -r '/[^/]*$' '' -- $d)
        end
        if test -z "$d" -o "$d" = /
            return
        end
    end
    $_pass_env_cmd export fish | source
end

function _pass_env_prompt --on-event fish_prompt
    _pass_env_hook
end

_pass_env_hook
