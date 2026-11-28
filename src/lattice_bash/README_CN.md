[English](README.md) | 简体中文

# lattice_bash

一个用于 tmux 的纯 Bash TUI 工作台。无需离开工作台，即可浏览文件并把配置好的快捷命令派发到专用的执行器窗格。

当前版本：**v1.0.0.0**

```bash
./src/lattice_bash/lattice.sh --version
```

开发者架构、设计权衡与常见陷阱：[DEVELOP_CN.md](DEVELOP_CN.md)。

## 布局

```text
┌──────────────────────────┬────────────────────┐
│ Lattice TUI              │ executor shell     │
│ file tree                │ command output     │
└──────────────────────────┴────────────────────┘
```

TUI 位于左侧窗格；命令会粘贴到右侧窗格。默认分割比例为 30/70：TUI 约占 30%，执行器约占 70%（TUI 最小 24 列）。执行器通过 tmux 窗格选项 `@lattice_role=executor` 发现，而不是按窗格索引识别。`auto`/`pane` 目标目前都会解析到该执行器。

## 调整窗格大小

使用 tmux 原生按键绑定：

```text
Ctrl-b Ctrl-Left/Right   resize by 1 column
Ctrl-b Alt-Left/Right    resize by 5 columns
Ctrl-b z                 zoom pane (asks y/n)
Ctrl-b Space             cycle layouts
```

鼠标单击/选择/滚轮已启用。边框拖拽被禁用，因为 tmux 没有最小窗格宽度限制，可能在 WINCH 恢复之前就毁掉 TUI 窗格。请改用键盘调整绑定。

边框拖拽控制：

```bash
# Verify the current binding (no output means disabled)
tmux list-keys -n | grep MouseDrag1Border

# Disable (the launcher's default)
tmux unbind -n MouseDrag1Border

# Enable mouse border dragging (risk: a hard drag can kill the TUI pane)
tmux bind -n MouseDrag1Border resize-pane -M
```

启动器会在启动时执行 `unbind`，因此在 `lattice` 之前启用它没有效果。请在工作台运行之后，从另一个终端或 tmux 命令提示符中启用。这是一个 tmux 服务器级全局绑定，会一直保留，直到被解除绑定或服务器重启。

如需精确宽度，可在会话内部执行：

```bash
tmux resize-pane -t "$(tmux display-message -p '#{session_name}'):work.0" -x 60%
```

该尺寸由对应的 tmux 会话记住。鼠标单击/选择/滚轮已启用；边框拖拽被有意禁用，因为 tmux 无法强制最小窗格宽度。

长文件名会用 `...` 截断；页脚显示所选条目的完整路径。树形视图有意不折行，因为折行会破坏每行一个条目的选择模型。执行器提示符使用 `PROMPT_DIRTRIM=2`，因此深层目录会以蓝色的 `.../parent/leaf$` 显示，并带有绿色提示符符号。
而不是占用整行输入。

在左侧树中，单击鼠标可选中一行。双击目录进入该目录，双击 `..` 返回上级目录，双击文件则用 `LATTICE_OPEN_CMD` 打开它。在文件上按 Enter 同样会打开编辑器；`o` 会在文件管理器中打开所选目录。滚轮会滚动列表视口而不改变选中条目；一页内就能显示完的列表会忽略滚轮。右侧窗格仍使用 tmux 复制模式来处理滚轮历史和选择。

## 快速开始

```bash
cd /path/to/qq_bash
./src/lattice_bash/lattice.sh --root "$PWD"
```

## 启动器函数

对于便携式 USB 部署，可把 Lattice 用户数据放在 U 盘上并显式传入。推荐使用以下启动器：

```bash
# ~/.bashrc
unalias lattice 2>/dev/null

lattice() {
    local root=${1:-/d/code}
    local usb=${LATTICE_USB:-/x}
    local session="lattice-$(date +%s)"

    [[ -d "$usb" ]] || {
        printf 'lattice: USB not mounted: %s\n' "$usb" >&2
        return 1
    }
    mkdir -p "$usb/.lattice/env.d" || return 1

    LATTICE_STATE_DIR="$usb/.lattice" \
    LATTICE_CONFIG="$usb/.lattice/commands.conf" \
        /d/code/qq_bash/src/lattice_bash/lattice.sh \
        --root "$root" --session "$session"
}
```

U 盘上的首次设置：

```bash
mkdir -p /x/.lattice/env.d
cp /d/code/qq_bash/src/lattice_bash/config/commands.conf \
   /x/.lattice/commands.conf
```

然后重新加载并启动：

```bash
source ~/.bashrc
lattice
lattice /d/code/other-project
```

便携式布局如下：

```text
/x/.lattice/
├── commands.conf
├── commands.user.conf
├── commands.disabled
├── command-order.tsv
├── history.tsv
├── env.conf
└── env.d/
    ├── <machine-a>.conf
    └── <machine-b>.conf
```

`LATTICE_STATE_DIR` 和 `LATTICE_CONFIG` 故意写成内联环境变量赋值：它们只作用于 Lattice 进程及其启动的 tmux TUI。不要把 `LATTICE_CONFIG` 指回仓库；那个文件只是一个冻结的示例。

如果不想把这个函数放进 `.bashrc`，可以放到单独的文件中：

```bash
# ~/.bashrc
[ -r ~/.config/lattice/launcher.bash ] && \
    . ~/.config/lattice/launcher.bash
```

并把上面的 `lattice()` 函数放入 `~/.config/lattice/launcher.bash`。

每次调用都会创建不同的 tmux 会话。时间戳对交互式使用来说已经足够：手动再开一个工作台远不止一秒。用 `Ctrl-g` 退出每个会话；它会关闭自己拥有的那个会话。

无需 `cd`；`lattice.sh` 通过 `BASH_SOURCE` 解析自己的库目录。不要使用 `--root_$(date +%s)`：那是一个未知选项。正确的选项是 `--root /path/to/project`。

如果只需要在本地配置上使用一个可复用的工作台，固定别名同样可行：

```bash
alias lattice='/d/code/qq_bash/src/lattice_bash/lattice.sh --root /d/code'
```

重复运行该别名会附加到同一个 `lattice` 会话。若希望每次都新建会话，请使用上面的函数。

请在外层 UCRT64 shell 中运行，而不是在已有的 Lattice 执行器窗格内运行。如果你用 `Ctrl-b d` 分离了会话，`tmux list-sessions` 仍会显示旧会话；`Ctrl-g` 才是预期的干净退出方式。

运行要求：Bash 5.x 和 `tmux`（Linux：使用你的包管理器；MSYS2/UCRT64：`pacman -S tmux`）。没有假定盘符或 Windows 专有路径；运行时路径使用 `HOME`、`TMPDIR` 和 `BASH_SOURCE`。

在 tmux 内部：

```bash
./src/lattice_bash/lattice.sh --tui --root "$PWD"
```

如果没有执行器窗格，TUI 会报告错误，而不是从 TUI 内部进行分割。

## 按键

```text
j/k, ↑/↓     move
Home / End   first / last entry
Enter        enter directory / open file in the editor
h            parent directory
Backspace    parent directory
r            refresh
.            toggle hidden files
o            open selected directory in the system file manager
y            copy selected path to the clipboard
@a / @b / @c copy selected full path into WB_A/WB_B/WB_C
:            quick command palette
/            filter file/dir names in tree; search commands in palette
H            history
p            preview selected history/recent command
Ctrl-r       focus recent commands (then 0-9 or Enter)
/            search history (in history mode)
R            reload commands (tree or palette)
?            help
Ctrl-g       quit and close the Lattice session
```

## 用户环境与机器标识

用户特定的路径应放在仓库之外：

```text
~/.lattice/env.conf                  shared by all machines
~/.lattice/env.d/<machine-id>.conf   one machine
```

这些文件是受信任的 Bash 文件，Lattice 启动时读取一次。

### 首次设置

```bash
cd /path/to/qq_bash
./src/lattice_bash/lattice.sh --machine-id
```

示例输出：

```text
machine: 72a9e8a6-0709-41fa-bdad-f5bbaa3cc9d8
common:  /home/me/.lattice/env.conf
machine: /home/me/.lattice/env.d/72a9e8a6-0709-41fa-bdad-f5bbaa3cc9d8.conf
```

创建机器专属文件：

```bash
mkdir -p ~/.lattice/env.d
$EDITOR ~/.lattice/env.d/72a9e8a6-0709-41fa-bdad-f5bbaa3cc9d8.conf
```

典型的机器文件：

```bash
# ~/.lattice/env.d/<machine-id>.conf
LATTICE_EDITOR=/d/programes/vim/vim91/gvim.exe
LATTICE_OPEN_CMD='/d/programes/vim/vim91/gvim.exe --remote-silent'
```

典型的公共文件：

```bash
# ~/.lattice/env.conf
LATTICE_EDITOR=/d/programes/vim/vim91/gvim.exe
```

修改这些文件后重启 Lattice：

```text
Ctrl-g
lattice
```

### 机器 id

该 id 来源于：

```text
Linux:   /etc/machine-id
MSYS2:   HKLM\SOFTWARE\Microsoft\Cryptography\MachineGuid
fallback: $HOSTNAME
```

id 在每次运行时都会重新推导，且**不会**写入 `LATTICE_STATE_DIR`。该目录可能位于多台机器共用的 U 盘上；若把 id 缓存在那里，它就会在每台机器上被复用，从而选中错误的机器文件。

所有机器文件可以一起放在同一个便携目录中：

```text
/mnt/usb/lattice/env.conf
/mnt/usb/lattice/env.d/<machine-a>.conf
/mnt/usb/lattice/env.d/<machine-b>.conf
```

显式设置便携根目录：

```bash
LATTICE_STATE_DIR=/mnt/usb/lattice lattice
```

每台机器仍然只读取自己的 `<machine-id>.conf`。

仅在测试时覆盖 id：

```bash
LATTICE_MACHINE_ID=test-machine lattice
```

### 优先级

```text
explicit environment variable
> machine-specific file
> common env.conf
> built-in defaults
```

例如：

```bash
LATTICE_EDITOR=/tmp/test-editor lattice
```

会覆盖这两个文件。

### 用户通常需要配置的内容

大多数用户只需要这些：

```text
LATTICE_EDITOR          editor binary; default gvim
LATTICE_RECENT_LIMIT    recent-command count; default 10
LATTICE_ROOT            optional initial tree root
```

`LATTICE_OPEN_CMD` 是高级覆盖项。默认情况下它由以下方式推导：

```bash
LATTICE_OPEN_CMD="$LATTICE_EDITOR --remote-silent"
```

只有在编辑器需要不同参数时才显式设置它。

其他一切都是内部使用或面向开发的：

```text
LATTICE_CONFIG          use --config instead
LATTICE_STATE_DIR       advanced profile/state relocation
LATTICE_ENV_CONF        advanced env-file relocation
LATTICE_ENV_DIR         advanced env-file relocation
LATTICE_HISTORY_FILE    derived from state dir
LATTICE_HISTORY_LIMIT   history entry cap; default 512
LATTICE_ORDER_FILE      derived from state dir
LATTICE_USER_COMMANDS_FILE  user-added commands
LATTICE_DISABLED_FILE   hidden command names
LATTICE_EXECUTOR_RC     internal shell hook
LATTICE_TMUX_BIN        tmux auto-detection
LATTICE_TMUX_SESSION    use --session instead
LATTICE_MACHINE_ID      testing override
```

上面列出的所有 `LATTICE_*` 变量都是受支持的覆盖项；“内部”的意思是“不建议作为用户可调项”，而不是“会被忽略”。如果你设置了它，Lattice 就会使用它。诸如 `--root`、`--config` 和 `--session` 的 CLI 选项仍然优先于环境变量值。

如果你希望引导变量 `LATTICE_ENV_CONF`、`LATTICE_ENV_DIR` 和 `LATTICE_MACHINE_ID` 决定加载哪些文件，就必须在启动之前把它们设置在进程环境中。把它们设置在本应由它们定位的文件内部就太晚了。

常规机器文件：

```bash
# ~/.lattice/env.d/<machine-id>.conf
LATTICE_EDITOR=/d/programes/vim/vim91/gvim.exe
```

不要把所有内部变量都暴露为用户可调项。如果某个路径或会话很重要，请优先使用 CLI（`--root`、`--config`、`--session`）。

### 动态值：只使用占位符

命令使用显式占位符：

```text
{{WB_ROOT}}     project root
{{WB_DIR}}      current tree directory
{{WB_FILE}}     selected file; empty for a directory
{{WB_CLIP}}     current system clipboard
{{WB_A}}        register A
{{WB_B}}        register B
{{WB_C}}        register C
```

发送之前，Lattice 会把每个占位符替换为经过 shell 引用的字面量：

```bash
lattice_command 'cd here' 'dir'  'pane' 'cd {{WB_DIR}}'
lattice_command 'view'    'file' 'pane' 'gvim {{WB_FILE}}'
lattice_command 'diff A C' 'dir' 'pane' 'diff -u {{WB_A}} {{WB_C}}'
```

寄存器与执行器共享：

```text
tree:       @a / @b / @c   copy selected full path into WB_A/B/C
executor:   Ctrl-b a/b/c   copy system clipboard into WB_A/B/C
executor:   Ctrl-b v       refresh WB_CLIP preview from the clipboard
```

`Ctrl-b c` 会在 Lattice 会话内覆盖 tmux 的 new-window。  
状态栏左侧预览按 `DIR`、`A`、`B`、`C`、`CLIP`、`FILE` 的顺序显示。寄存器和 `CLIP` 只使用其最后十个字符，更长时会加上 `...` 前缀。空值会被省略。当寄存器或剪贴板缓存发生变化时预览会刷新；任意的外部剪贴板变化需要等待 `Ctrl-b v` 或下一条剪贴板命令。

`CLIP` 预览缓存只存储最后十个字符；完整的剪贴板内容会在需要 `{{WB_CLIP}}` 时按需读取，且不会被缓存写入器持久化。寄存器则有意存储完整值，因为它们是用户显式放进去的。

剪贴板读取超时属于失败，而不是部分内容：暂存文件会被丢弃，缓存/寄存器保持不变，使用 `{{WB_CLIP}}` 的命令也不会被发送。真正为空的剪贴板仍然是一次成功的读取，并会变成一个空参数。

不要在命令模板中使用 `$WB_DIR`、`$WB_FILE`、`$WB_ROOT`、`$WB_A/B/C`、`$WB_CLIP` 或 `$LP_*`。它们会在派发时被拒绝。执行器收到的是最终的字面命令，不带任何环境前缀或隐藏上下文。

不要把这些值放进 `env.conf`；它们是运行时上下文，不是用户设置。

## 配置

`config/commands.conf` 是**冻结的示例**，不是用户的命令目录。请把它复制到你自己的配置（例如 `/x/.lattice/commands.conf`）并维护那份副本。Lattice 仓库不会持续添加示例命令。

可直接复制的用户命令示例是 `config/commands.user.example.conf`；它不会被自动加载。

该示例文件是受信任的 Bash 配置：

```bash
lattice_command 'git status' 'dir'  'pane' 'GIT_TERMINAL_PROMPT=0 git -C {{WB_DIR}} status --short --branch' '只查看当前目录。'
lattice_command 'git check all' 'dir' 'pane' 'GIT_TERMINAL_PROMPT=0 timeout 60 git_check_status.sh -o {{WB_DIR}}' '扫描所有仓库，较慢。'
lattice_command 'git diff'   'file' 'pane' 'git diff -- {{WB_FILE}}' '查看选中文件的 diff。'
```

命令没有快捷键。打开 `:` 面板，用 `j/k` 或方向键选择，按 `/` 进入搜索并输入以过滤，然后按 Enter 发送；派发之后面板保持打开。搜索激活时，`p`、`D`、`R` 等可打印键会输入到查询中；它们的命令快捷键只在搜索未激活时才生效。Esc 退出搜索（清空查询），再按 Esc 退出面板。打开搜索时会把查询同步到 tmux 状态栏，并用 `search>` 行替换标题，因此查询保持可见，又不会遮住执行器窗格。退出搜索会恢复先前的状态栏。PageUp/PageDown 和鼠标滚轮可在长列表中移动；标题会显示当前可见范围。`*` 标记带快照的命令，`+` 标记用户添加的命令。每行显示命令名、作用域和目标。列表下方的一行预览只显示所选命令正文。命令正文不会在列表本身中渲染，但仍然可以被搜索。按 `p` 或右键单击某行可查看完整命令正文；如果命令有快照，两段都会显示。弹窗没有标题或页脚。移动到另一行、点击别处，或按 Esc/q 会自动关闭它。按 `D` 可禁用所选命令。在 `commands.user.conf` 中手动添加命令，然后在面板中按 `R` 重新加载，或重启 Lattice。

可选的第五个 `lattice_command` 参数是由 `p` 或右键单击显示的快照。可选的第六个参数是以空白分隔的参数列表。快照会参与搜索，并且可以包含中文。`scope` 在 1.0 中仅作说明用途。`target` 是传输策略（`pane`、`auto`、`pane:<id>`、……）。

### 带参数的命令

```bash
lattice_command 'grep current tree' 'dir' 'pane' \
  'grep -n --color=auto -- {{PATTERN}} {{WB_DIR}}' \
  '按模式搜索当前文件树' \
  'PATTERN'
```

选择该命令并按 Enter 会打开一个表单，而不是立即发送。值是普通输入字符串，不是 shell 片段。Lattice 会用 `${value@Q}` 运算符为每个值加引号，并在发送前替换。

```text
PATTERN   -> placeholder {{PATTERN}}
NAME=def  -> default value def
```

不存在 `LP_` 命名空间，也不存在 `eval`。名为 `PATTERN` 的参数只能通过以下形式引用：

```bash
{{PATTERN}}
```

最终的字面命令会存入历史，因此可以直接重新运行。

快照之后的所有实参都按参数处理，一个实参一个参数：

```bash
lattice_command 'grep in target' 'dir' 'pane' \
  'grep -nHE --color=auto -- {{PATTERN}} {{TARGET_DIR}}' \
  '搜索指定目录' \
  'PATTERN' 'TARGET_DIR=.'
```

第一个 `=` 之后的全部内容都是默认值，原样保留。空格在配置层需要加引号；ANSI-C 默认值可以直接写：

```bash
lattice_command 'defaults' 'dir' 'pane' \
  'printf "%s\n" {{A}} {{B}}' \
  '' \
  'A=hello world' B=$'a\tb'
```

没有第二层转义：`B=$'a\tb'` 到 Lattice 时已经是真实制表符。不要把真实换行写进默认值；参数表单是单行输入。

不要把多个参数声明塞进一个字符串；一个实参就是一个参数。

占位符必须位于单/双引号之外：

```bash
grep -- {{PATTERN}} {{WB_DIR}}      # correct
grep -- "{{PATTERN}}" {{WB_DIR}}    # wrong
```

占位符名称遵循 `[A-Za-z_][A-Za-z0-9_]*`，区分大小写，并且必须在参数列表中声明。以下名称保留给动态上下文，不能作为参数：

```text
WB_ROOT WB_DIR WB_FILE WB_CLIP WB_A WB_B WB_C
```

未声明的名称会报错，命令不会被发送。同一个占位符可以出现多次，而且始终得到相同的值：

```bash
lattice_command 'same twice' 'dir' 'pane' \
  'diff -u {{A}} {{A}}' \
  '' \
  'A'
```

裸写占位符使用方括号：

```text
[{NAME}]
```

值会原样插入，不加 `@Q`。任何包含裸写占位符的命令都会强制变成仅插入：绝不自动执行，会以预览文本进入历史，并把焦点切到执行器供审查。值不做校验，可以来自参数或动态变量。

裸写占位符用于 glob 和 shell 花括号展开：

```bash
lattice_command 'list txt' 'dir' 'pane' \
  'printf "%s\n" [{PATTERN}]' \
  '' \
  'PATTERN'

lattice_command 'brace range' 'dir' 'pane' \
  'echo {[{START}]..[{END}]}' \
  '' \
  'START' 'END'
```

不要写 `{{{NAME}}}`：它不是合法语法，会被当成畸形的普通占位符。不是完整 `[{NAME}]` 标记的文本，例如 JSON `[{"a":1}]`，会保持字面量。

快照文本仅用于显示，永远不会做占位符展开。

以 `@` 开头的命令名是**仅插入**命令。Lattice 会粘贴命令骨架但不按 Enter，也不会把它加入历史：

```bash
lattice_command '@ssh' 'dir' 'pane' 'ssh ' '插入 SSH 骨架；不会自动执行。'
```

状态行会报告骨架已插入。Lattice 会自动把焦点切换到执行器；使用 `Ctrl-b ←` 返回 TUI。命令准备好后由你自己按 Enter。这是 SSH、REPL 和提示符等交互式命令的预期模式。

第五个参数为空表示没有快照。参数仍然可以跟在它后面：

```bash
lattice_command 'grep in target' 'dir' 'pane' \
  'grep -nHE --color=auto -- {{PATTERN}} {{TARGET_DIR}}' \
  '' \
  'PATTERN' 'TARGET_DIR=.'
```

快照为空的命令在弹窗中仍会显示其命令正文；`p` / 右键单击只会报告 `COMMAND`。

表单几乎使用整个 TUI 窗格宽度，以便长值保持可读。每个参数显示一个字段；默认值会预填。活动字段使用终端光标而不是插入下划线，因此光标不会占用或移动字符单元；终端自身的光标形状会保留。Enter 移动到下一个字段，并在最后一个字段之后发送。

```text
Tab       next field
Shift-Tab previous field
Ctrl-u    clear current field
Ctrl-d    restore its default value
Esc       cancel
```

Enter 移动到下一个字段，并在最后一个字段之后发送。Tab 和 Shift-Tab 只在字段之间移动；它们不会插入字面制表符。若要传入字面制表符作为参数值，请使用 ANSI-C 形式，例如 `$'a\tb'`；它会成为仅在预览中可见的值，由你按 Enter 确认。

### 显式 ANSI-C 值

如果某个参数是完整的单个 `$'...'` 词，Lattice 会把它视为已加引号的字面量并原样插入。随后命令会**在不按 Enter 的情况下插入**，焦点移到执行器，你可以在按 Enter 之前检查它。

```text
$'a b'
$'line1\nline2'
$'it\'s 中文'
```

该值必须恰好是一个完整的 ANSI-C 词。诸如 `$'a'; id` 或 `$'a'$'b'` 的畸形尝试会被重新加引号为普通字面文本，仍然采用预览插入。这不是 shell 求值：`$'...'` 永远不会执行命令替换。

来自有效 `$'...'` 参数的预览命令会以插入的文本形式记入 Lattice 历史，这是在任何手动编辑之前。重新运行它们时使用该编辑前的文本；用户有责任检查它。畸形的 `$'...'` 尝试和 `@` 骨架不会被记录，因为它们是残缺或无效的命令文本。

模板使用 `{{WB_CLIP}}` 的命令会以其展开后的字面量存入历史，因此历史中可能包含剪贴板文本。如果这些内容敏感，请清除 `history.tsv`；寄存器则始终完整存储，因为它们是明确的用户状态。

带参数的命令会以其完全展开后的字面命令写入历史。值中的特殊字符无需用户转义：按字面输入值，Lattice 会为 shell 加引号。

### 命令正文中的引号

命令是一个 Bash 字符串。外层引号属于配置文件；其中的引号属于执行器 shell。

首选的外层形式是单引号：

```bash
lattice_command 'printf one' 'dir' 'pane' \
  'printf "%s\n" "hello"'
```

若要包含字面单引号，请闭合再重新打开外层字符串：

```bash
lattice_command 'it works' 'dir' 'pane' \
  'printf "%s\n" "it'\''s fine"'
```

当正文中没有 `$` 或反引号时，外层双引号通常更易读，尤其是在配合单引号的 printf 格式字符串时：

```bash
lattice_command 'snapshot metachars' 'dir' 'pane' \
  "printf '%s\\n' 'snapshot demo'" \
  'snapshot text'
```

`\\n` 在配置文件被 source 时会变成 `\n`；`printf` 会解释它。占位符仍然要放在 shell 引号之外：

```bash
lattice_command 'echo path' 'file' 'pane' \
  'printf "%s\n" {{WB_FILE}}'
```

### 命令正文中的终端控制序列

允许：

```text
plain UTF-8 text
\n and \t produced by printf
SGR color/style: ESC [ ... m
  reset, bold, dim, italic, underline, reverse
  basic, 256-color and truecolor foreground/background
```

示例：

```bash
lattice_command 'red text' 'dir' 'pane' \
  "printf '\033[31mred\033[0m\n'"

lattice_command 'bold red' 'dir' 'pane' \
  "printf '\033[1;31mbold red\033[0m\n'"
```

命令正文中不允许（`<...>` 表示占位符，而不是字面文本）：

```text
ESC[200~ ; ESC[201~              bracketed-paste start/end
ESC[?2004h ; ESC[?2004l          bracketed-paste mode
ESC[?1000h/l                     mouse press/release
ESC[?1002h/l                     mouse button drag
ESC[?1003h/l                     mouse any motion
ESC[?1006h/l                     SGR mouse encoding
ESC[?1015h/l                     urxvt mouse encoding
ESC[?1049h/l                     alternate screen + cursor
ESC[?1047h/l                     alternate screen
ESC[?47h/l                       legacy alternate screen
ESC[?25h/l                       cursor visible/hidden
ESC[<n> q                        cursor shape
ESC[<n>A/B/C/D                    cursor up/down/right/left
ESC[<n>H / ESC[<n>f              cursor position
ESC[2J / ESC[K                   erase display/line
ESC[<n>J / ESC[<n>K              erase display/line variants
ESC 7 / ESC 8                    save/restore cursor
ESC]0;<title>BEL                 window/icon title
ESC]2;<title>BEL                 window title
ESC]8;<params>;<uri>ST           hyperlink
ESC]52;<params>;<data>ST         clipboard access
ESC[6n ; ESC[c                   terminal queries
```

经验法则：

```text
SGR color/style -> allowed
anything that changes terminal state, input mode, cursor or screen -> script
```

这些会改变状态的序列可能干扰 TUI，或干扰用于投递命令的括起粘贴。如果某个命令需要这种程度的终端操作，请把它包进脚本，改为运行脚本。

### 字面换行和制表符

`commands.conf` 和 `commands.user.conf` 是 Bash 文件，因此对字面控制字符请使用 Bash 的 ANSI-C 引用：

```bash
# Two output lines
lattice_command 'two lines' 'dir' 'pane' \
  $'printf "one\ntwo\n"' \
  '打印两行'

# A literal newline as one argument
lattice_command 'printf nl' 'dir' 'pane' \
  $'printf "%s" "\n"' \
  '打印一个换行符'

# Tab characters
lattice_command 'printf tab' 'dir' 'pane' \
  $'printf "a\tb\n"' \
  '打印制表符'
```

`$'...'` 在配置文件被 source 时由 Bash 处理。等到 `lattice_command` 收到命令时，`\n` 和 `\t` 已经是真正的字节。TUI 会存储该字符串并通过 tmux 粘贴缓冲区发送，因此换行和制表符能在传输中保留下来。

对外部命令来说这是安全的，因为执行器 shell 会正常解析所存储的命令。引号内的换行会成为同一个参数的一部分：

```bash
printf "%s" "
"
```

引号外的换行会分隔命令，这是有意为之：

```bash
lattice_command 'two commands' 'dir' 'pane' \
  $'echo one\necho two' \
  '执行两条命令'
```

`$'...'` 不会绕过引号处理。动态值应放在占位符中：

```bash
lattice_command 'echo value' 'dir' 'pane' \
  'printf "%s\n" {{PATTERN}}' \
  '打印参数' \
  'PATTERN'
```

历史会把制表符和换行规范化为空格；请用于那些精确多行历史并不重要的命令。

### 添加和删除命令

面板中没有添加表单。请用文本编辑器添加命令：

```bash
$EDITOR /x/.lattice/commands.user.conf
```

示例：

```bash
lattice_command 'ps xf' 'dir' 'pane' 'ps -xf' '读取进程树'
```

保存，然后在面板中按 `R`，或重启 Lattice。重启很快。

从面板中删除：

```text
D        disable selected command (writes commands.disabled)
y        confirm deletion
```

文件：

```text
commands.user.conf    manually maintained user commands
commands.disabled     names hidden from the registry
```

`commands.conf` 是源文件，永远不会被 TUI 重写。基础命令是被禁用而不是删除。用户命令仍保留在用户文件中，但会被禁用列表隐藏。`R` 会重新加载所有内容。

### 重名命令

名称应当唯一。

```text
commands.user.conf overrides commands.conf
duplicate inside the same file is ignored
```

重名会在 stderr 和 TUI 状态中报告：

```text
lattice: duplicate command: name
config: 1 duplicate name(s) ignored
```

Lattice 仍会启动。畸形的配置不应让用户无法打开工作台；修正文件后按 `R`。

如果某个名称列在 `commands.disabled` 中，请先把它从该文件移除，再复用这个名称。

命令会收到：

```text
{{WB_ROOT}}    project root
{{WB_DIR}}     current directory; updates when you enter/parent a directory
{{WB_FILE}}    selected file, empty for a directory
```

左侧状态行显示：

```text
DIR /d/code/qq_bash  FILE /d/code/qq_bash/src/lattice.sh
```

`WB_ROOT` 用作外层终端标题。窗口列表被移除，因为 Lattice 只打开一个窗口。状态更新会在后台合并，因此移动选择不会阻塞于 tmux 调用。

面板顺序单独存储在：

```text
~/.lattice/command-order.tsv
```

它不会被写回 `commands.conf`。用 Alt-Up/Alt-Down 重排所选行，或用 Ctrl-t 将其置顶。顺序会立即保存，并在重新加载和新会话后保留。顺序文件中缺失的新命令会按配置顺序追加。

## 最近命令

左下角面板显示 Lattice 派发的最近且不重复的命令。`Ctrl-r` 聚焦它，`j/k` 选择，Enter 重新运行。聚焦时，`0`-`9` 会重新运行对应的最近命令。`p` 或右键单击可预览完整命令；左键单击选中该行。面板上限为 10 条且完全可见，因此滚轮不会改变其选择。数字键在树模式下不起作用。

## 历史

只有由 Lattice 派发的命令才会被记录，存放在：

```text
~/.lattice/history.tsv
```

条目存储最终的字面命令，包括展开后的占位符和参数值。例如文件中包含：

```bash
grep -n -- '/d/code/qq_bash/file.txt'
```

而不是模板。重新运行某个条目会执行相同的字面命令。

带参数的命令会连同其值一起记录，因此可以直接重新运行。直接在另一个 shell 中运行的命令不会被捕获。

在历史面板中按 `/` 进行增量搜索。输入以过滤，`Esc` 退出搜索，再按 `Esc` 返回树。Enter 重新运行所选条目。Home/End 跳到第一个/最后一个条目，搜索时同样有效。`p` 或右键单击可预览完整命令；鼠标滚轮会滚动列表视口而不改变选择，左键单击选中，双击重新运行。一页内就能显示完的列表会忽略滚轮。历史条目也可以先用 `/` 搜索，再用 Enter 重新运行。

默认限制：

```text
history entries   512
recent commands   10
```

超出限制时，最旧的历史条目会被裁剪。`LATTICE_HISTORY_LIMIT` 可更改历史上限，供高级使用。

## 通过 SSH 运行

首选的部署方式是把 Lattice 复制到远程机器，如需要就在那里安装 `tmux`，然后远程运行 TUI：

```text
local terminal -> ssh -> remote tmux -> Lattice TUI + executor
```

在执行器内运行 `ssh` 也是可以的。命令会被粘贴到 SSH pty 并在远程 shell 上执行，但所有上下文值都已在本地展开：

```text
WB_ROOT / WB_DIR / WB_FILE    local paths
WB_A / WB_B / WB_C            local register values
WB_CLIP                       local clipboard
LATTICE_OPEN_CMD              local editor path
```

因此 `pwd`、`ls` 和 `git status` 可以工作，而 `diff A B`、打开文件或任何使用本地路径的模板通常会在远程失败。远程 shell 中还必须启用括起粘贴；否则 `ESC[200~`/`ESC[201~` 可能以字面文本出现。请使用现有的 SSH 命令骨架（`@ssh`）并运行远程 TUI 以获得完整功能。

## 复制输出 / 与执行器交互

右侧窗格是普通的交互式 Bash shell。用 `Ctrl-b →`（或 `Ctrl-b o`）聚焦它并在其中输入。Lattice 快捷键只在左侧窗格激活时生效。

复制模式：

```text
Ctrl-b [        enter copy mode
arrows/PgUp     move
Space           start selection
Enter           copy
Ctrl-b ]        paste inside tmux
q               leave copy mode
```

鼠标选择和滚轮滚动：

```bash
tmux set -g mouse on
```

启动器会启用 `set-clipboard on`，并在 `clip.exe`/`wl-copy`/`xclip` 可用时把鼠标拖拽释放绑定到系统剪贴板。请在右侧窗格中使用普通的左键拖拽（不是 Shift+拖拽）：它可以跨行，释放时会把选区写入剪贴板。选区也会留在 tmux 的缓冲区中。若想回到 shell，请按 `q`，然后：

```text
Ctrl-b e        open last buffer as file[:line], or a directory in the file manager
Ctrl-b ]        paste the last buffer
```

对于已经可见的一行，无需选择或缓冲区：

```text
Alt + left click    open the line under the pointer
Ctrl + left click   same, as a terminal fallback
```

行解析器会去掉前导空白和 ANSI 转义，然后从头开始扫描以空白分隔的 token。第一个存在的 token 生效：

```text
1. path:line   -> editor at that line
2. path        -> editor
3. directory   -> system file manager
4. nothing existing -> no action
```

只考虑存在的路径。`Ctrl-b e` 仍然是显式的基于缓冲区的操作；它不会尝试读取鼠标位置。

`Ctrl-b o` 是 tmux 正常的下一窗格切换；它与编辑器操作无关。

执行器中没有图形滚动条。使用 `Ctrl-b [` 然后 PgUp/PgDn（或鼠标滚轮）浏览 tmux 回滚；`q` 退出复制模式。从面板发送命令时会先自动退出复制模式，因此命令会到达 shell 提示符，而不是复制缓冲区。

### 分割执行器

在执行器 shell 中，按上下分割：

```bash
tmux split-window -v -c "$PWD"
```

左右分割：

```bash
tmux split-window -h -c "$PWD"
```

默认的 tmux prefix 等效按键是：

```text
Ctrl-b "     split top/bottom
Ctrl-b %     split left/right
Ctrl-b o     next pane
Ctrl-b z     zoom pane (asks for confirmation)
Ctrl-b x     close current pane
```

新分割的窗格**不会**被标记为 Lattice 执行器：

```text
TUI commands still go to the original executor
the new pane is for manual commands
```

在任何分割窗格中，选中路径并按 `Ctrl-b e` 仍会使用活动窗格的当前目录打开该文件或目录。

#### 安全关闭分割

TUI 窗格和原执行器都受到保护，免受误按 `Ctrl-b x` 的影响：

```text
Ctrl-b x on TUI or executor -> message, pane is not closed
Ctrl-b x on a split         -> normal confirmation
```

只关闭多余的分割：

```text
Ctrl-b q        briefly show pane numbers
Ctrl-b o        cycle to the split
Ctrl-b x        close active pane, confirm y
```

除非你想杀掉整个窗口（包括 TUI 和原执行器），否则绝不要使用 `Ctrl-b &`。它没有保护，因为这是有意的整窗操作；`Ctrl-b d` 只分离会话，是安全的。

如果原执行器被有意从其 shell 退出，TUI 命令会以 `no executor pane` 失败。通过重新启动一个 `lattice` 会话恢复；没有可靠的方法把任意分割提升回 Lattice 执行器，因为它缺少执行器 rc 和提示符设置。

在 Windows 上，显式的剪贴板桥接是：

```bash
tmux set-buffer -- "$(powershell.exe -NoProfile -Command Get-Clipboard)"
tmux paste-buffer -p
```

在 Windows Terminal 中，`Shift+拖拽` 通常可以在 tmux 不拦截鼠标的情况下选择文本。

### 在编辑器中打开 `file:line`

执行器提供 `eg`：

```text
eg path/to/file:42
eg path/to/file
```

`eg` 使用 `LATTICE_EDITOR`（默认 gvim）和 `--remote-silent +LINE`。诸如 `path/file.sh:42: pattern` 的 grep 行会被正确解析；相对路径相对于执行器的当前目录解析。

鼠标工作流：

```text
Alt+left click on path/file.sh:42 in the right pane
```

无需拖拽或复制模式。行解析器从头开始扫描并使用第一个存在的 token：

```text
path:line -> file -> directory -> no action
```

较旧的选词工作流仍然可用：

```text
normal drag-select path/file.sh:42 in the right pane
release
Ctrl-b e
```

如果复制模式仍然激活，请先按 `q`。`Ctrl-b e` 会把最后一个 tmux 缓冲区按 `file:line` 打开；如果所选路径是目录，则会在系统文件管理器中打开该目录，而不是编辑器。只选择 `path:line` token，而不是用空格分隔的文件名和行号。对于 grep，请使用：

```bash
grep -n --color=auto pattern path
rg -n --color=auto pattern path
```

`--color=auto` 在写入终端时会高亮匹配；只有在通过管道传递且消费方理解 ANSI 时才使用 `--color=always`。

如果所选路径不是已存在的文件，辅助程序会把它复制到 tmux 缓冲区并显示一条简短消息，而不是打开错误的文件。没有启用自动可点击的 grep 输出，因为那需要解析任意输出，打开错误路径的风险更高。

## 架构

```text
app/state.sh       state, paths, terminal sizing
fs/tree.sh         directory listing and navigation
cmd/registry.sh    array command registry + commands.conf loader
cmd/history.sh     TSV history, recent list, search and history cap
cmd/tmux.sh        pane discovery/sending
cmd/executor.sh    target resolution and command sending
ui/render.sh       ANSI renderer
ui/event.sh        key loop
```

命令注册表和历史就是普通 Bash 数组加 TSV 文件；它们不依赖 `x`/`xo` 运行时。`lattice.sh` 创建 tmux 会话并启动 TUI。

## 状态

1.0.0.0 是一个可运行的框架：文件树、快捷命令、tmux 发送、历史、重新加载、帮助、带参数的命令以及用户命令覆盖。文件预览已被移除，因为它让导航太慢。编辑、git UI 和结构化输出捕获有意不在范围内。
