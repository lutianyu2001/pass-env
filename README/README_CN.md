# pass-env

<p align="right">
    <a href="../README.md">English</a> | <strong>中文</strong>
</p>

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)<br>
[![CI](https://github.com/lutianyu2001/pass-env/actions/workflows/ci.yml/badge.svg)](https://github.com/lutianyu2001/pass-env/actions/workflows/ci.yml)

一个轻量的工具：每个项目用 `.env.pass` 写明自己要哪些密钥，shell 进入项目时从 [pass](https://www.passwordstore.org/) 密码库解密加载，离开时撤掉。

## 目录

- [概述](#概述)
- [功能特性](#功能特性)
- [前置要求](#前置要求)
- [安装](#安装)
- [用法](#用法)
- [工作原理](#工作原理)
- [测试](#测试)
- [兼容性](#兼容性)
- [免责声明](#免责声明)
- [许可证](#许可证)
- [作者](#作者)

## 概述

所有密钥只存在一个地方，即 pass 密码库，每个密钥是一个 GPG 加密的文件。项目在根目录的 `.env.pass` 里只写名字，说明要哪些密钥：

```bash
# .env.pass: the name the project reads = the entry in the pass store
OPENAI_API_KEY=API_KEY/openai/work
NCBI_API_KEY=API_KEY/ncbi
```

这里的变量名和条目名只是示例，请换成你的项目实际读取的变量名和密码库里实际的条目。

接好 shell hook 以后，`cd` 进项目，这些变量就设好了；`cd` 出去，它们就被撤掉，原来同名的变量恢复原值。程序照常从环境变量读取，所以任何命令都不需要包一层；项目里也没有明文的 `.env`，不会被提交、同步或复制出去。两个项目可以把同一个变量名映射到不同的条目。

同一个 hook 也作用于 AI 编程 agent 执行的每条命令（通过 `BASH_ENV`、`~/.zshenv` 或 fish 的 `conf.d`）：agent 在哪个项目里干活，就拿到那个项目的密钥，中途换到别的项目也一样。

## 功能特性

- `cd` 时加载和卸载项目的密钥，支持 bash、zsh 和 fish，在每次显示提示符前和非交互式 shell 里都生效
- 把项目里的变量名映射到 pass 条目，不同项目之间的变量名不会冲突
- 只把 `.env.pass` 当数据读，从不执行：clone 下来的仓库里的这个文件不能执行任何代码
- 拒绝 shell、加载器或常用工具会用到的变量名（`PATH`、`LD_*`、`BASH_*`、`PROMPT*`、`TMOUT`、`UID`、`JAVA_TOOL_OPTIONS` 等），以及 Claude Code 用来认证的变量名
- 并行解密条目；在 Linux 上把值在内存里（`$XDG_RUNTIME_DIR`）缓存 24 小时
- 可以只给一条命令注入密钥（`pass-env run`），为通过命令获取凭证的工具提供值（`pass-env get`），也可以作为 git 的凭证 helper
- POSIX sh，无需构建；支持 Linux 和 macOS

## 前置要求

- 一个 pass 密码库（`~/.password-store`，或 `PASSWORD_STORE_DIR` 指定的位置），以及能解密它的 GnuPG 密钥。条目用 `pass` 命令管理；pass-env 本身只用 `gpg` 读取它们。
- `gpg`、POSIX 的 `sh` 和 `awk`，以及 Linux 和 macOS 自带的 `xargs`（需支持 `-0` 和 `-P`）、`stat`、`find`、`sha256sum` 或 `shasum`
- hook 需要 bash、zsh 或 fish（3.0 及以上）
- 推荐的安装方式需要 [pixi](https://pixi.sh/)

## 安装

### 使用 pixi（推荐）

1. 从 prefix.dev 的 channel 为当前用户安装，不需要 root（需要先装好 [pixi](https://pixi.sh/)）：

   ```bash
   pixi global install -c https://prefix.dev/tianyulu/main pass-env
   ```

   以后用 `pixi global update pass-env` 升级，`pixi global uninstall pass-env` 卸载。

2. 接入 shell：

   ```bash
   pass-env init
   ```

   它先检查 `gpg` 和 `pass` 有没有安装（没装时会告诉你怎么装），然后为本机装了的 bash、zsh、fish（或你指定的，比如 `pass-env init zsh`）各自的启动文件加一个块：`~/.bashrc`（macOS 上是 `~/.bash_profile`，那里的终端读的是它）、`~/.zshenv`（每个 zsh 都会读，脚本和 agent 也包括在内）和 `~/.config/fish/conf.d/pass-env.fish`。这个块夹在 `# >>> pass-env init >>>` 和 `# <<< pass-env init <<<` 之间，加在文件末尾；这个块不改 `PATH`，可以放在要求排最后的行（比如 SDKMAN 的）后面；你要是把块挪到别处，`init` 以后会让它留在那里。再运行一次 `init` 不会有任何改动，`pass-env init --dry-run` 只显示将要写入的内容，`pass-env init --undo` 会把这些块移除。升级后 hook 的位置不变，不需要重新运行。

### 从源码构建

1. 获取源码：

   ```bash
   git clone https://github.com/lutianyu2001/pass-env.git
   cd pass-env
   ```

2. 为当前用户安装到 `~/.local`（或用 `--prefix <DIR>` 指定），不需要 root：

   ```bash
   ./install.sh
   ```

   `~/.local/bin` 需要在 `PATH` 上。卸载它装上的文件：`./install.sh --uninstall`。

3. 用 `pass-env init` 接入 shell（同上），或者手动加上 `install.sh` 打印出的那一行，比如在 `~/.bashrc` 里加 `. "<HOME>/.local/share/pass-env/hook.bash"`（fish 则是在 `conf.d` 里加 `source ".../hook.fish"`）。

### 用非交互式 bash 运行命令的工具

对于用非交互式 bash 执行每条命令的工具（比如 Claude Code），把 `BASH_ENV` 设为 hook 文件，路径由 `pass-env hook bash --path` 给出。在 Claude Code 的 `~/.claude/settings.json` 里：

```json
{ "env": { "BASH_ENV": "<PATH PRINTED BY pass-env hook bash --path>" } }
```

注意：bash 的标准输入是 socket、并且 `SHLVL` 没有设置或为 0 时，它会认为自己是被远程 shell 守护进程调起的，从而跳过 `BASH_ENV`（见 `man bash` 的 INVOCATION 一节）。如果某个工具用清空的环境、以 socket 作为标准输入启动 bash，应当保留 `SHLVL`。

## 用法

```bash
pass-env <command> [arguments]
```

| 命令 | 说明 |
|---|---|
| `export [sh\|fish]` | 输出让当前 shell 的环境与当前目录相符的语句，分 bash/zsh 和 fish 两种写法，由 hook 执行 |
| `run [-f FILE] [NAME=ENTRY ...] [--] COMMAND [ARG ...]` | 带着密钥运行 `COMMAND`：用 `NAME=ENTRY` 指定的和 `FILE` 映射的，两者都没有时用最近的 `.env.pass`。有任何一条映射无法满足时，什么都不运行 |
| `get ENTRY` | 输出一个条目的第一行 |
| `status` | 显示这里适用哪个 `.env.pass`、它映射了什么、当前 shell 加载了什么，不输出任何值 |
| `hook bash\|zsh\|fish [--path]` | 输出放进 shell 启动文件、用来加载 hook 的那一行；加 `--path` 时输出 hook 文件的路径 |
| `init [bash] [zsh] [fish] [--dry-run]` | 检查 `gpg` 和 `pass` 已安装，然后在各 shell 的启动文件里以带标记的块加载 hook |
| `init --undo [bash] [zsh] [fish] [--dry-run]` | 移除这些块 |
| `git-credential ENTRY get` | 用 `ENTRY` 回答 git 的凭证请求 |
| `version`、`help` | |

`.env.pass` 每行一个 `NAME=ENTRY`，可以带 `export ` 前缀，也可以有注释和空行。变量的值是对应条目的第一行，和 `pass show -c` 复制的内容相同。

示例：

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

注意：不要映射 `ANTHROPIC_API_KEY`、`ANTHROPIC_AUTH_TOKEN` 或 `CLAUDE_CODE_OAUTH_*`。Claude Code 用它们认证，所以在这个项目里启动的每个 `claude -p` 都会改用这个 key 计费，而不是你的订阅；pass-env 会拒绝它们。让项目用自己的名字读 key，例如 `<PROJECT>_ANTHROPIC_API_KEY`。

## 工作原理

- **用哪个文件**：从当前目录往上找到的最近的 `.env.pass`，只用这一个。不属于你的 `.env.pass` 会被忽略（`pass-env status` 会列出它），根目录 `/` 不查找。
- **只读数据**：每一行按 `NAME=ENTRY` 匹配，文件里的任何内容都不会被执行，条目也不能指向密码库之外。格式不对的行、被拒绝的变量名、不存在的条目，以及重复映射的变量名（以第一行为准），都会在 stderr 上报告（以 `pass-env:` 开头）并跳过，其中的控制字符会被替换掉。
- **状态**：hook 把加载过的内容记在 `_PASS_ENV_NAMES`、`_PASS_ENV_STAMP` 和 `_PASS_ENV_PREV_<NAME>` 里，离开项目时据此恢复被替换的值。从这个 shell 启动的程序会继承这些变量，但不会继承 hook。
- **检查时机**：每次显示提示符前，`cd`、`pushd`、`popd` 之后（交互式 bash 中，前提是你没有自己定义同名的函数或别名），以及非交互式 shell 启动时；fish 里是每次目录变化时和每次显示提示符前。附近没有 `.env.pass`、也没有加载过任何东西时，检查不会启动任何程序。检查会保留原来的 `$?`，运行期间关闭 xtrace 和 verbose（fish 里是 `fish_trace`），所以开启跟踪时也不会打印出任何值。读取失败的条目会在一分钟后的第一次检查时重试（`PASS_ENV_RETRY_SECONDS`）。
- **解密**：直接用 `gpg` 读取条目，每次并行 8 个。值只经过管道和变量传递，从不出现在进程参数或文件里。每个值返回时首尾都带着自己的序号；并行输出对不上时，改为逐个重新解密。
- **缓存**：有 `XDG_RUNTIME_DIR`、它属于你、只有你能访问，并且（在 Linux 上）是 tmpfs 时，值会在其下的 `pass-env/` 里缓存 24 小时，文件名由映射和条目内容的哈希决定：修改条目后文件名就变了，所以不会读到过期的值。否则（包括没有这种目录的 macOS）不缓存。

## 测试

```bash
tests/run.sh
```

测试在隔离环境里进行，使用一次性的 GnuPG 目录、密钥和 pass 密码库，结束后全部删除。它检查 bash、zsh 和 fish 下的 hook（有无 `XDG_RUNTIME_DIR` 两种情况）、被拒绝的变量名、每个命令、`init` 以及 `install.sh`。`packaging/conda/test-local.sh` 会构建 conda 包，并在临时的 `PIXI_HOME` 和 home 里，按 `pixi global` 安装、升级、卸载的流程检查它。用 `ZSH=<path>` 或 `FISH=<path>` 指定使用的 shell；没有的 shell 会跳过对应的检查。

## 兼容性

测试环境：

- Ubuntu 24.04.4 LTS
  - bash 5.2.21、dash 0.5.12，以及 zsh 5.9.2 和 fish 4.9.3（conda-forge）
  - mawk 1.3.4、BusyBox awk 1.36.1、GNU Awk 5.4.1（conda-forge）
  - GnuPG 2.4.4
- macOS 15.8.2（Mac mini 2018，Intel）
  - bash 3.2.57、zsh 5.9、fish 4.9.3（conda-forge）、awk 20200816
  - GnuPG 2.5.24

## 免责声明

This project is not affiliated with, endorsed by, or sponsored by pass or its maintainers. "pass" refers to the software developed by Jason A. Donenfeld (https://www.passwordstore.org/) and is referenced here solely for descriptive purposes.

## 许可证

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

## 作者

Tianyu (Sky) Lu
