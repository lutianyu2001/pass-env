# pass-env

<p align="right">
    <strong>English</strong> | <a href="./README/README_CN.md">中文</a>
</p>

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)<br>
[![CI](https://github.com/lutianyu2001/pass-env/actions/workflows/ci.yml/badge.svg)](https://github.com/lutianyu2001/pass-env/actions/workflows/ci.yml)

A lightweight tool that gives each project the secrets its `.env.pass` names, decrypted from the [pass](https://www.passwordstore.org/) store when the shell enters the project and taken away when it leaves.

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Usage](#usage)
- [How It Works](#how-it-works)
- [Testing](#testing)
- [Compatibility](#compatibility)
- [Disclaimer](#disclaimer)
- [License](#license)
- [Author](#author)

## Overview

Every secret stays in one place, the pass store, where each one is a GPG-encrypted file. A project says which of them it needs in a `.env.pass` at its root, by name only:

```bash
# .env.pass: the name the project reads = the entry in the pass store
OPENAI_API_KEY=API_KEY/openai/work
NCBI_API_KEY=API_KEY/ncbi
```

The variable and entry names here are only examples: use the names your project reads and your store holds.

With the shell hook in place, `cd` into the project and those variables are set; `cd` out and they are gone, and any variable of the same name gets its old value back. Programs read them from the environment as usual, so no command needs a wrapper, and no plaintext `.env` sits in the project to be committed, synced or copied. Two projects can map the same name to different entries.

The same hook works for each command an AI coding agent runs, through `BASH_ENV`, `~/.zshenv` or fish's `conf.d`: the agent gets the keys of the project it works in, also when it moves to another one.

## Features

- Loads and unloads a project's secrets on `cd`, in bash, zsh and fish, before each prompt and in non-interactive shells
- Maps the project's variable names to pass entries, so names never clash between projects
- Reads `.env.pass` as data and never runs it: a cloned repository's file cannot execute code
- Refuses names a shell, a loader or a common tool acts on (`PATH`, `LD_*`, `BASH_*`, `PROMPT*`, `TMOUT`, `UID`, `JAVA_TOOL_OPTIONS`, ...) and the ones Claude Code authenticates with
- Decrypts entries in parallel, and on Linux caches them for 24 hours in memory (`$XDG_RUNTIME_DIR`)
- Runs a single command with secrets (`pass-env run`), serves tools that ask a command for a credential (`pass-env get`), and acts as a git credential helper
- POSIX sh, no build step; Linux and macOS

## Prerequisites

- A pass store (`~/.password-store`, or `PASSWORD_STORE_DIR`) and the GnuPG key that decrypts it. The `pass` command manages the entries; pass-env itself only reads them with `gpg`.
- `gpg`, a POSIX `sh` and `awk`, and the usual `xargs` (with `-0` and `-P`), `stat`, `find`, and `sha256sum` or `shasum`, as Linux and macOS ship them
- bash, zsh or fish (3.0 or later) for the hooks
- [pixi](https://pixi.sh/) for the recommended installation

## Installation

### Using pixi (Recommended)

1. Install it for your user, with no root, from the prefix.dev channel (this needs [pixi](https://pixi.sh/)):

   ```bash
   pixi global install -c https://prefix.dev/tianyulu/main pass-env
   ```

   `pixi global update pass-env` brings later versions; `pixi global uninstall pass-env` removes it.

2. Hook it into your shells:

   ```bash
   pass-env init
   ```

   It checks that `gpg` and `pass` are installed (and says how to install them when they are not), then adds a block to the startup file of each of bash, zsh and fish that is installed, or of those named (`pass-env init zsh`): `~/.bashrc` (on macOS `~/.bash_profile`, which its terminals read), `~/.zshenv` (read by every zsh, so scripts and agents get it too) and `~/.config/fish/conf.d/pass-env.fish`. The block sits between `# >>> pass-env init >>>` and `# <<< pass-env init <<<`, at the end of the file; the block does not change `PATH`, so it can follow lines that ask to come last (SDKMAN's, for one); if you move it, `init` keeps it where you put it. Running `init` again changes nothing, `pass-env init --dry-run` shows what it would write, and `pass-env init --undo` takes the blocks out again. An update keeps the hooks where they were, so there is nothing to run again.

### Building from Source

1. Get the source:

   ```bash
   git clone https://github.com/lutianyu2001/pass-env.git
   cd pass-env
   ```

2. Install it for your user, with no root, into `~/.local` (or `--prefix <DIR>`):

   ```bash
   ./install.sh
   ```

   `~/.local/bin` must be on `PATH`. To remove what it installed: `./install.sh --uninstall`.

3. Hook it into your shells with `pass-env init`, as above, or by hand with the line `install.sh` printed, such as `. "<HOME>/.local/share/pass-env/hook.bash"` in `~/.bashrc` (fish: `source ".../hook.fish"` in `conf.d`).

### Tools That Run Non-interactive bash

For tools that run each command in a non-interactive bash (Claude Code, for one), set `BASH_ENV` to the hook file, which `pass-env hook bash --path` prints. In Claude Code's `~/.claude/settings.json`:

```json
{ "env": { "BASH_ENV": "<PATH PRINTED BY pass-env hook bash --path>" } }
```

Note: bash skips `BASH_ENV` when its standard input is a socket and `SHLVL` is unset or 0, taking itself for a command run by a remote shell daemon (see INVOCATION in `man bash`). A tool that starts bash with a cleared environment and a socket for stdin should keep `SHLVL`.

## Usage

```bash
pass-env <command> [arguments]
```

| Command | Description |
|---|---|
| `export [sh\|fish]` | Print the statements that bring this shell's environment up to date for the current directory, for bash and zsh or for fish; the hooks evaluate them |
| `run [-f FILE] [NAME=ENTRY ...] [--] COMMAND [ARG ...]` | Run `COMMAND` with secrets: those `NAME=ENTRY` name and those `FILE` maps, or with neither, those of the nearest `.env.pass`. Nothing runs when a mapping cannot be satisfied |
| `get ENTRY` | Print an entry's first line |
| `status` | Show which `.env.pass` applies here, what it maps and what the shell has loaded, without printing a value |
| `hook bash\|zsh\|fish [--path]` | Print the line that loads the hook in the shell's startup file, or with `--path` the hook file's path |
| `init [bash] [zsh] [fish] [--dry-run]` | Check that `gpg` and `pass` are installed, then load the hooks from the shells' startup files, in a marked block |
| `init --undo [bash] [zsh] [fish] [--dry-run]` | Remove those blocks |
| `git-credential ENTRY get` | Answer git's credential request with `ENTRY` |
| `version`, `help` | |

`.env.pass` takes one `NAME=ENTRY` a line; an `export ` prefix, comments and blank lines are allowed. A variable gets the first line of its entry, as `pass show -c` copies it.

Examples:

```bash
# one command, with a key no file mentions
pass-env run <NAME>=<ENTRY> -- <COMMAND>

# a tool that runs a command for its credential: cargo, in ~/.cargo/config.toml
#   [registry]
#   global-credential-providers = ["cargo:token-from-stdout pass-env get <ENTRY>"]

# git, for one host only
git config --global --replace-all credential.https://<HOST>.helper ""
git config --global --add credential.https://<HOST>.helper "!pass-env git-credential <ENTRY>"
```

Note: never map `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN` or `CLAUDE_CODE_OAUTH_*`. Claude Code authenticates with them, so every `claude -p` started in the project would bill that key instead of your subscription; pass-env refuses them. Have the project read its key under a name of its own, such as `<PROJECT>_ANTHROPIC_API_KEY`.

## How It Works

- **Which file**: the nearest `.env.pass` from the current directory upward, and only that one. A `.env.pass` that is not yours is ignored (`pass-env status` names it), and none is looked for in `/`.
- **Data only**: each line is matched against `NAME=ENTRY`; nothing in the file is evaluated, and an entry may not leave the store. Lines that do not fit, refused names, missing entries and a name mapped twice (its first line applies) are reported on stderr with a `pass-env:` prefix and skipped, with any control characters replaced.
- **State**: the hooks keep what they loaded in `_PASS_ENV_NAMES`, `_PASS_ENV_STAMP` and `_PASS_ENV_PREV_<NAME>`, so that leaving a project sets back the values it replaced. Programs started from the shell inherit the variables but not the hook.
- **Checks**: before each prompt, after `cd`, `pushd` and `popd` (in interactive bash, unless you already have a function or alias of that name), and when a non-interactive shell starts; in fish, at every change of directory and before each prompt. Where no `.env.pass` is found and none was loaded, the check runs no program. It keeps `$?` as it was, and turns off xtrace and verbose (fish: `fish_trace`) while it runs, so that tracing never prints a value. An entry that could not be read is tried again at the first check a minute later (`PASS_ENV_RETRY_SECONDS`).
- **Decryption**: entries are read with `gpg` directly, eight at a time. Values travel through pipes and variables, never through process arguments or files. Each comes back framed by its index; when the parallel output does not add up, every entry is decrypted again one by one.
- **Cache**: with `XDG_RUNTIME_DIR`, when it is yours, owner only and (on Linux) a tmpfs, values are cached there for 24 hours under `pass-env/`, in files named after a hash of the mapping and of the entries' contents: editing an entry gives a new name, so a stale value is never read. Otherwise (and on macOS, which has no such directory) nothing is cached.

## Testing

```bash
tests/run.sh
```

It runs in isolation, with a throwaway GnuPG home, key and pass store that it removes afterwards, and checks the hooks in bash, zsh and fish (with and without `XDG_RUNTIME_DIR`), the refused names, every command, `init` and `install.sh`. `packaging/conda/test-local.sh` builds the conda package and checks it as `pixi global` installs, updates and uninstalls it, in a scratch `PIXI_HOME` and home. Set `ZSH=<path>` or `FISH=<path>` to choose the shells; the checks of a shell that is not there are skipped.

## Compatibility

Tested on:

- Ubuntu 24.04.4 LTS
  - bash 5.2.21, dash 0.5.12, zsh 5.9.2 and fish 4.9.3 (conda-forge)
  - mawk 1.3.4, BusyBox awk 1.36.1, GNU Awk 5.4.1 (conda-forge)
  - GnuPG 2.4.4
- macOS 15.8.2 (Mac mini 2018, Intel)
  - bash 3.2.57, zsh 5.9, fish 4.9.3 (conda-forge), awk 20200816
  - GnuPG 2.5.24

## Disclaimer

This project is not affiliated with, endorsed by, or sponsored by pass or its maintainers. "pass" refers to the software developed by Jason A. Donenfeld (https://www.passwordstore.org/) and is referenced here solely for descriptive purposes.

## License

Copyright 2026 Tianyu (Sky) Lu

The entire repository is licensed under the Apache License, Version 2.0 
(the "License"); you may not use any file in this repository except in 
compliance with the License. You may obtain a copy of the License at

```plaintext
http://www.apache.org/licenses/LICENSE-2.0
```

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

## Author

Tianyu (Sky) Lu
