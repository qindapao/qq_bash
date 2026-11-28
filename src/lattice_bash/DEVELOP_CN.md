[English](DEVELOP.md) | 简体中文

# Lattice — Developer Notes

状态：**v1.0.0.0**  
读者：多年以后维护或调试 Lattice 的人。  
面向用户的文档：[README_CN.md](README_CN.md)。

本文说明整体架构、进程之间的契约、那些并不显然的实现选择，以及已经引发过 bug 的陷阱。在做结构性修改之前，请先通读全文。

---

## 1. Lattice 是什么

Lattice 是一个面向本地 tmux 会话的纯 Bash TUI 工作台：

```text
terminal
  └── tmux session
        ├── left pane  : Lattice TUI (file tree + command palette)
        └── right pane : executor shell (normal interactive Bash)
```

这个 TUI 负责四件事：

```text
browse files
select a command
collect optional parameters
expand {{placeholders}} and paste the literal command
```

它**不**执行命令、不捕获输出、不解析 stdout，也不管理执行器的作业控制。

### 非目标

以下都是有意省略的功能，而不是尚未完成的功能：

```text
no file preview
no editor embedded in the TUI
no output parsing or structured command results
no command market / package manager
no automatic file watching
no in-panel add-command form
no multi-user or server architecture
no remote/SSH backend (yet)
no Windows-native UI; tmux is the window manager
```

本项目更看重稳定性、启动速度和可预测的状态，而不是功能数量。

---

## 2. 设计原则

### 2.1 进程分离，单向控制

TUI 与执行器是位于不同 tmux 窗格中的独立进程。

```text
control plane : TUI -> literal command + tmux paste -> executor
data plane    : executor -> tmux pane rendering
```

TUI 从不读取执行器的输出，执行器也从不渲染 TUI 的状态。关闭或阻塞 TUI 不得阻塞正在运行的前台命令，除非整个由 Lattice 拥有的 tmux 会话被有意杀掉。

### 2.2 TUI 侧不做 shell 插值，也不使用 `eval`

命令模板使用显式占位符：

```text
{{WB_ROOT}} {{WB_DIR}} {{WB_FILE}} {{PARAM}}
```

TUI 会把每个占位符替换为经过 shell 引用的 `${value@Q}` 字面量。整个过程不做任何 shell 求值，也不传递变量环境。

这样引用关系保持如实，也避免了重复求值引发的 bug。

### 2.3 显式契约

只有以下值会跨越边界：

```text
literal command text          computed in the TUI
editor binary                 startup environment
```

其余一切内容都留在各自进程内部。

### 2.4 配置是受信任的 Bash

`commands.conf`、`commands.user.conf`、`env.conf` 以及机器环境文件都由 Bash source 加载。它们与 `~/.bashrc` 具有相同的信任级别。

不要把它们当作数据来解析，不要对它们做沙箱隔离，也不要试图让它们对不受信任的用户安全。本项目并不采用那种威胁模型。

### 2.5 不重写源文件

`commands.conf` 是源文件，TUI 永远不会重写它。用户新增的命令放在 `commands.user.conf` 中；隐藏项放在 `commands.disabled` 中。

TUI 可能出错，也可能被杀掉；但它绝不能破坏用户手写的配置。

### 2.6 稳定的 tmux 目标

执行器通过窗格选项来定位：

```text
@lattice_role=executor
```

而不是通过窗格索引，也不是通过当前获得焦点的窗格。拆分执行器不会把 TUI 的命令抢到新窗格，原执行器仍然是默认目标。

### 2.7 快速常用路径

普通命令名和命令体都是 ASCII。渲染器带有 ASCII 快速路径，以及按命令缓存的行缓存。只有在需要时才计算 CJK 宽度。

在没有实测的情况下，不要给常规滚动路径增加逐帧开销。

---

## 3. 代码地图

```text
src/lattice_bash/
├── lattice.sh                 entry point, CLI, tmux session creation
├── app/state.sh               paths, env layers, machine id, globals, ANSI
├── fs/tree.sh                 file tree operations
├── cmd/registry.sh            command arrays, loading, search, order, forms
├── cmd/history.sh             history TSV, recent list, search and history cap
├── cmd/tmux.sh                roles, layout, mouse bindings, tmux send
├── cmd/executor.sh            target resolution and command sending
├── ui/render.sh               full-frame renderer and popups
├── ui/event.sh                raw keys, mouse, forms, event loop
├── executor/rc.sh             executor prompt and eg
├── executor/open-selection.sh open selected file:line or directory
├── executor/open-directory.sh platform file manager launcher
├── executor/copy-selection.sh clipboard bridge
├── config/commands.conf       frozen shipped example (not user catalog)
├── config/commands.user.example.conf  copyable user examples
└── README.md                  user-facing manual
```

此目录之外的支持库：

```text
src/bashlib/str.sh             str_display_width, CJK/emoji width
```

`str.sh` 被 source 时会打印一段语法探测输出。启动器会把它的 stdout 重定向到 `/dev/null`；否则这段探测输出会破坏备用屏幕。

---

## 4. 启动流程

### 4.1 正常启动

```text
lattice.sh --root DIR --session NAME
  |
  +-- source str.sh, state, tree, registry, history, tmux, executor, render, event
  |
  +-- no TMUX environment?
        -> lattice_create_session
             new-session -d -s NAME -n work -c ROOT
             split-window -h -p 70
             mark pane 0 @lattice_role=tui
             mark pane 1 @lattice_role=executor
             respawn pane 0 -> lattice.sh --tui --owned ...
             attach
```

TUI 只在拆分完成之后才启动。如果在拆分之前启动 TUI，它会缓存整个窗口的宽度，从而在更窄的窗格中渲染错位。

### 4.2 在 tmux 内部

如果 `TMUX` 已经设置，启动器会直接在当前窗格中运行 TUI，而不是新建会话。

### 4.3 TUI 启动

`lattice_app_main`：

```text
apply 30/70 width if inside tmux
enable mouse and clipboard bindings
install EXIT/INT/TERM/HUP/WINCH traps
load registry
load history
load file tree
enter alternate screen and raw mode
run event loop
restore terminal
kill session only when LATTICE_OWN_SESSION=1
```

`--owned` 只会由会话启动器传入。用户在自有会话中手动启动的 `--tui`，退出时不得杀掉该会话。

### 4.4 创建了一半的会话

如果请求名称的会话已经存在，但缺少 `tui` 或 `executor` 中的任意一个，它会被杀掉并重新创建。绝不要尝试就地修复构建到一半的会话；旧的 `split` 阻塞故障模式更糟。

---

## 5. tmux 模型

### 5.1 窗格角色

```text
@lattice_role=tui
@lattice_role=executor
```

角色通过以下命令设置：

```bash
tmux set-option -p -t PANE @lattice_role ROLE
```

由 `split-window` 新建的窗格**不会**继承窗格选项。用户自行拆分出的窗格没有角色，不会成为执行器目标。

### 5.2 目标选择

`lattice_tmux_select_executor` 会按顺序扫描窗格，选择第一个角色为 `executor` 或 `primary` 的窗格。

由此带来的后果：

```text
split executor              -> original remains target
focus a split               -> target does not change
close original executor     -> no executor target; sends fail safely
mark a split as executor    -> it may become target, but it lacks rc setup
```

不要自动提升拆分出的窗格。由 tmux 启动的拆分 shell 并不会加载执行器的 rc。

### 5.3 布局

默认拆分：

```bash
split-window -h -p 70
```

TUI 启动时会根据实际窗口宽度重新应用宽度：

```text
left  = window_width * 30 / 100
left >= 24 columns
right >= 24 columns
```

分离状态下创建的会话，其初始宽度与附加后的终端宽度不同。如果不重新应用宽度，视觉比例会漂移到 40/60。

### 5.4 发送命令

```bash
tmux load-buffer -
tmux paste-buffer -p -d -t TARGET
tmux send-keys -t TARGET Enter
```

`paste-buffer -p` 使用括号粘贴，能保留引用关系和特殊字符。不要用 `send-keys -l` 发送任意命令；tmux 的键名解释和 shell 的多行行为会变得脆弱。

### 5.5 会话安全

`Ctrl-b x` 对 `tui` 和 `executor` 做了保护：

```text
Ctrl-b x on protected pane -> message, no close
Ctrl-b x on split          -> confirmation
```

在执行器 shell 中执行 `exit` 仍会关闭该窗格。除非替换用户的 shell 行为，否则无法拦截这一点。

`Ctrl-b z` 是缩放而不是关闭，并且会请求确认。

`Ctrl-b &` 会杀掉整个窗口，有意不加保护。

---

## 6. TUI 运行时

### 6.1 屏幕与 raw 模式

`lattice_screen_init`：

```text
alternate screen
hide cursor
enable mouse reporting (SGR)
enable bracketed paste
clear screen
save stty
raw-ish mode: -icanon -echo -icrnl
```

`lattice_screen_done` 会撤销上述全部操作并恢复 `stty`。

终端会在 EXIT/INT/TERM/HUP 陷阱中恢复。绕过这些陷阱的崩溃会让终端停留在 raw 模式；这正是清理逻辑要集中管理的主要原因。

### 6.2 事件循环

```bash
while (( ! LATTICE_QUIT )); do
    if lattice_read_key; then
        lattice_handle_key "$key"
        lattice_render
    elif (( LATTICE_NEED_RENDER )); then
        LATTICE_NEED_RENDER=0
        lattice_render
    fi
done
```

这里没有轮询，也没有后台读取器。

重要后果：

```text
executor output does not trigger TUI render
TUI idle CPU is effectively zero
TUI only redraws after a key/mouse event or WINCH
heavy executor output cannot back-pressure the TUI
```

### 6.3 全帧渲染

每次渲染都会构建 `LATTICE_FRAME` 并一次性写出。

为什么只写一次：

```text
many small writes make tmux/WinTerm visibly repaint between lines
```

每一行都以 `\033[0m` 开头；选中行会追加反显，并在 `\033[K` 之前重置。如果没有逐行重置，终端的反显状态会渗到后续行。

### 6.4 Enter 与 Ctrl-J

终端会把 Enter 和 Ctrl-J 都报告为同一个 LF/空字节。读取器会把两者都归一化为 CR，因此 Enter 能可靠地执行。Ctrl-J 不是可靠的次要操作；请在搜索和列表中使用 Ctrl-n/Ctrl-p/Ctrl-k。

### 6.5 鼠标

SGR 鼠标序列由手工解析：

```text
button, x, y
wheel: b=64/65
motion: b & 32
press/release: low bits
double click: 900 ms row/mode timer
```

鼠标坐标映射使用**当前渲染偏移**：

```text
row = LATTICE_CMD_OFFSET + y - 2
row = LATTICE_TREE_OFFSET + y - 2
row = history offset + y - 2
```

最近命令面板占据文件树视图底部十行。左键单击选中，双击重新运行，右键单击预览完整命令。该面板完全可见，因此滚轮事件不会影响它的选中项。`Ctrl-r` 让它获得焦点，`j/k` 选择，Enter 重新运行，`0`-`9` 重新运行对应行。在文件树、命令列表和历史列表中，滚轮只滚动视口；选中条目不会改变，单页列表会忽略滚轮。历史模式下左键单击选中，双击重新运行，`p` 或右键单击预览完整命令。预览弹窗会把点击交还给打开它的模式。键盘导航会清除手动滚动标记，并把选中项带回视野。

### 6.6 渲染模式

```text
tree      file tree + recent commands
commands  command list + one-line command preview
history   command history
help      key reference
```

覆盖层：

```text
form      parameter/delete form
snapshot  floating snapshot content
```

文件树中的 `q` 被有意禁用；只有 Ctrl-g 可以退出。这样可以避免一次误按 `q` 就结束整个工作台。

---

## 7. 命令注册表

### 7.1 数据模型

注册表使用一组并行数组：

```text
LATTICE_CMD_IDS
LATTICE_CMD_NAMES
LATTICE_CMD_SCOPES
LATTICE_CMD_TARGETS
LATTICE_CMD_COMMANDS
LATTICE_CMD_SNAPSHOTS
LATTICE_CMD_PARAMS
LATTICE_CMD_ORIGINS
LATTICE_CMD_VIEW        raw indices after search
```

运行时不存在 `x`/`xo` 树。为了启动速度和简洁性，注册表已经迁移为扁平数组。

### 7.2 配置格式

```bash
lattice_command NAME SCOPE TARGET COMMAND [SNAPSHOT] [PARAMS...]
```

快照之后的所有内容都是参数：

```bash
lattice_command 'grep in target' 'dir' 'pane' \
  'grep -nHE -- {{PATTERN}} {{TARGET_DIR}}' \
  '搜索指定目录' \
  'PATTERN' 'TARGET_DIR=.'
```

名称以 `@` 开头的命令是只插入命令：

```bash
lattice_command '@ssh' 'dir' 'pane' 'ssh ' '打开 SSH 骨架'
```

注册表会记录一种 `submit` 模式。`run` 表示粘贴后按 Enter；`insert` 表示只粘贴，然后把焦点交给执行器。只插入命令不会写入历史。这是为交互式程序（SSH、REPL、提示符）提供的受支持变通方式：TUI 只投递一个骨架，由用户补全。

每个参数是一个独立实参。第一个 `=` 之后的全部内容都是默认值，原样保留。空格在配置层需要加引号；`B=$'a\tb'` 可以直接写，到达 Lattice 时已经是真实制表符。表单是单行输入，真实换行不适合作为默认值。

空快照：

```bash
... '' 'PATTERN'
```

### 7.3 加载顺序

```text
commands.conf
commands.user.conf
minus commands.disabled
```

`commands.conf` 是冻结的随附示例。用户实际使用的命令目录通常放在 U 盘上，并通过 `LATTICE_CONFIG` 选择。

用户命令名会有意覆盖基础命令名。同一层内的重名会被忽略并报告：

```text
lattice: duplicate command: name
loaded N commands; M duplicate(s) ignored
```

Lattice 仍会启动。配置格式错误不应该让工作台无法打开。

### 7.4 禁用列表

`commands.disabled` 每行一个命令名。它可以在不重写源文件的情况下隐藏命令。要重新使用某个被隐藏的名称，请从该文件中删除对应行。

### 7.5 排序

```text
command-order.tsv
```

该文件只包含名称，不会被写回 commands.conf。

```text
Ctrl-t      pin selected to top
Alt-↑/↓     move selected
```

排序会立即保存。已不存在的名称会被清理。

### 7.6 搜索

`lattice_registry_build_hay` 会为每条命令构建一个小写 haystack：

```text
name scope target command snapshot params
```

搜索支持多个词项。每个词项都会转换为按顺序匹配子序列的通配符：

```text
gst -> *g*s*t*
```

匹配由 Bash 在 C 层执行 `[[ $hay == $pattern ]]` 完成。这比每次按键都调用外部 grep 快得多。

同时把 haystack 和查询都转为小写，从而实现忽略大小写。

打开搜索时，查询会同步显示到 tmux 状态栏，TUI 头部会变成专门的 `search>` 行，显示查询尾部。执行器窗格保持可见。搜索前会保存 `status-right` 和 `status-right-length` 的取值，退出时恢复；如果 TUI 意外退出，清理逻辑也会恢复它们。

### 7.7 重名策略

```text
user command same name as base -> user overrides base
duplicate in same file          -> first wins, later ignored + error
disabled name                   -> not loaded; remove disable first
```

### 7.8 界面

命令列表行只显示：

```text
* / + marks, name, scope, target
```

选中命令的命令体会显示在列表下方的一行预览中。快照不会渲染在列表里。

行缓存的键是：

```text
raw command index : terminal columns
```

在注册表重置、重新加载、重新排序和宽度变化时，该缓存都会被清空。如果没有该缓存，1000 条中文快照会让滚动明显变慢。

### 7.9 添加/删除策略

没有面板内的添加表单。请用文本编辑器添加命令：

```text
commands.user.conf
```

`D` 通过把选中命令的名称追加到 `commands.disabled` 来禁用它。`R` 重新加载。这样可以把输入编辑排除在 TUI 之外，也避免重写手写的 Bash 文件。

---

## 8. 参数与占位符

### 8.1 参数生命周期

```text
select parameterized command
-> form opens with defaults prefilled
-> Enter moves to next field
-> last Enter sends
```

表单按键：

```text
Tab       next field
Shift-Tab previous field
Ctrl-u    clear current field
Ctrl-d    restore default
Esc       cancel
```

Tab 和 Shift-Tab 在字段之间移动；它们不会插入字面制表符。要输入字面制表符，请使用完整的 `$'...'` 参数，例如 `$'a\tb'`；它会像其他显式 ANSI-C 值一样被校验和预览。

必填/可选约定：

```text
NAME          no default; currently accepted empty, but intended as required
NAME=default  default value
```

没有单独的类型系统，也不支持复杂的交互式参数。复杂的交互式命令应放在执行器中。

### 8.2 占位符

命令模板使用：

```text
{{WB_ROOT}}
{{WB_DIR}}
{{WB_FILE}}
{{PARAM}}
```

`PARAM` 是第六个参数中声明的参数名。没有 `LP_` 命名空间，也不导出参数环境。

名称必须匹配 `[A-Za-z_][A-Za-z0-9_]*`，区分大小写，并且必须已声明。`WB_ROOT/WB_DIR/WB_FILE/WB_CLIP/WB_A/WB_B/WB_C` 是保留名称，不能用作参数名。未知名称会中止派发。同一个占位符可以出现多次；每次出现都会得到相同的值。快照文本仅用于显示，不会被展开。

`[{NAME}]` 是裸写形式：值会原样插入，不加 `@Q`，因此可以提供 glob 或 shell 花括号语法。它总是强制预览插入，绝不自动执行，并以预览文本进入历史。值不做校验。解析器只接受完整的 `[{NAME}]` 标记；其他方括号文本（例如 JSON `[{"a":1}]`）保持字面量。

### 8.3 展开与引用

发送之前，`lattice_command_expand` 会：

```text
reads WB_ROOT / WB_DIR / WB_FILE from the tree
reads NAME=value pairs from the form
replaces each {{NAME}} with ${value@Q}
rejects unknown or unclosed placeholders
```

包含空格、引号、`$`、反引号或换行的值会变成安全的 shell 字面量。发送给执行器的命令与历史中保存的是同一个字面量。

占位符必须位于引号之外：

```bash
grep -- {{PATTERN}} {{WB_DIR}}      # correct
grep -- "{{PATTERN}}" {{WB_DIR}}    # invalid; @Q escaping changes
```

### 8.4 历史

每条派发的命令都会以其最终字面文本存储，包括参数值。因此 `history.tsv` 中保存的是可重复执行的命令。

只插入的 `@` 命令不会被写入。因**有效**的 `$'...'` 参数而进入预览模式的命令，会按插入的文本、在任何手工编辑之前写入；重放使用编辑前的文本，由用户自行负责审查。格式错误的 `$'...'` 尝试不会被记录。

历史搜索是模态且增量的：`/` 激活过滤，可打印字符会更新过滤条件而不使用阻塞的 `read`，`Esc` 退出搜索，再按一次 `Esc` 返回文件树。这避免了旧版中可能看起来像卡住的阻塞提示。

### 8.5 显式 ANSI-C 参数

如果某个参数恰好是一个完整的 `$'...'` 单词，它会被原样插入。其他任何以 `$'` 开头的值都会回退到 `@Q` 引用。两种情况都会强制 `submit=insert`，由用户审查后按 Enter。

校验器会扫描未转义的单引号和末尾反斜杠：它从不对该值求值。原始中文/Unicode 会被接受；只有格式错误的 ASCII 引用才会回退。

包含遗留 `$WB_*` 或 `$LP_*` 语法的命令会在派发时被拒绝。它们必须迁移为占位符。

### 8.6 寄存器与剪贴板

`WB_A/WB_B/WB_C` 是 `LATTICE_STATE_DIR` 中的原始文件：

```text
wb-register-A
wb-register-B
wb-register-C
wb-clip
```

`wb-clip` 只保存十个字符的预览，从不保存完整剪贴板内容。完整剪贴板内容会在需要时为 `{{WB_CLIP}}` 展开按需读入内存；缓存写入器不会持久化它。寄存器则有意保存完整值，因为用户明确把它们放在了那里。

- 在文件树中按 `@`，再按 `a/b/c`，会写入选中项的完整路径；
- `Ctrl-b a/b/c` 会把系统剪贴板读入对应寄存器；
- `Ctrl-b v` 只刷新 `WB_CLIP` 预览；
- 引用 `{{WB_CLIP}}` 的命令会读取并缓存一次剪贴板。

status-left worker 会读取寄存器文件并渲染 `DIR A B C CLIP FILE`。`CLIP` 和寄存器会显示最后十个字符，更长时在前面加 `...`。空值会被省略。这样 TUI 的渲染路径就不会包含剪贴板调用和逐键文件操作。外部剪贴板变化有意不做轮询。

剪贴板读取使用 2 秒内层超时和 3 秒外层 `--kill-after=1` 保护。超时/丢弃都算失败：部分临时数据会被删除，缓存/寄存器不会被覆盖，`{{WB_CLIP}}` 命令不会被发送。成功读取到空值仍然是有效的空值。

`Ctrl-b c` 在 Lattice 会话内覆盖 tmux 的新建窗口操作。该会话是单窗口的，因此再创建一个窗口会产生没有角色标记的窗格。

执行器不会获得隐藏上下文，也没有清理陷阱；它只是一个普通的 Bash 提示符，加上最终的命令行。

默认限制：

```text
history entries  512
recent commands  10
```

`LATTICE_HISTORY_LIMIT` 可修改历史上限。最旧的条目会分批清理：超过上限时，会一次性丢弃 `LATTICE_HISTORY_TRIM_BATCH` 个条目并原子重写一次 TSV，而不是在每条命令之后都重写整个文件。

---

## 9. 执行器 shell

### 9.1 启动

右侧窗格通过以下方式启动：

```bash
LATTICE_EDITOR=...
exec bash --noprofile --rcfile executor/rc.sh -i
```

该 rc 只设置：

```text
PROMPT_DIRTRIM=2
PS1='\[\e[1;34m\]\w\[\e[0m\]\[\e[1;32m\]\$\[\e[0m\] '
```

### 9.2 `eg`

```text
eg path/to/file:42
eg path/to/file
eg path/to/directory
```

它会解析路径和可选行号，校验存在性，然后启动编辑器。TUI 使用的辅助脚本会对 tmux copy-mode 选区做同样的事。

### 9.3 打开选中的文本

全局 tmux 前缀绑定：

```text
Ctrl-b e
```

会以活动窗格的当前目录和最后一个 tmux 缓冲区为参数运行 `open-selection.sh`。它处理：

```text
file:line  -> editor + line
directory  -> system file manager
bad path   -> message + buffer kept
```

相对路径会相对活动窗格的 cwd 解析，而不是相对某个全局固定根目录。

tmux 状态栏左侧行会镜像实时上下文，而不是会话/窗口标签：

```text
DIR <WB_DIR>  FILE <WB_FILE>
```

选择目录时会省略 `WB_FILE`。`lattice_status_left_start` 会保存原始的 `status-left`、`status-left-length`、`status-format[0]`、`set-titles` 和 `set-titles-string`，移除单窗口列表，并把外部标题设置为 `WB_ROOT`。

状态更新会写入一个小临时文件，并由一个后台 worker 应用。TUI 在选区移动时从不运行 tmux `set-option`；在 MSYS2 上同步更新 `status-left` 每次按键大约会增加 50 ms。worker 会合并快速移动，只应用最新文本。清理时会停止 worker 并恢复所有已保存的选项。

### 9.3.1 在没有选区的情况下打开鼠标所在行

`Alt+左键单击` 和 `Ctrl+左键单击` 绑定在 tmux 的 `root` 表中：

```text
M-MouseDown1Pane
C-MouseDown1Pane
```

它们会带着完整的 `#{mouse_line}` 和窗格 cwd 运行 `open-line.sh`。这之所以可行，只是因为绑定的是鼠标事件；tmux 不暴露持久的悬停位置，也没有受支持的 `mouse_x`/`mouse_y` 列可供之后的键盘绑定使用。

该辅助脚本会去掉前导空白和 ANSI 转义，从开头开始扫描空白分隔的 token，并打开第一个存在的 token：

```text
file:line  -> editor + line
file       -> editor
directory  -> file manager
none       -> no action
```

优先级按 token 逐个判断。扫描被有意设计得简单且确定；一行中有多个存在的路径时使用第一个。基于缓冲区的 `Ctrl-b e` 操作保持不变，仍是任意选区的回退方式。

Alt 是主修饰键，因为 Ctrl+单击常被终端的超链接处理占用；Ctrl 作为兼容回退也做了绑定。普通单击不被使用，因为它必须保留用于选择窗格和拖选文本。

### 9.4 分离编辑器

`copy-pipe`/tmux 命令管道会很快关闭 stdio。辅助脚本通过以下方式启动编辑器：

```bash
nohup setsid EDITOR ... </dev/null >/dev/null 2>&1 &
```

如果没有 `</dev/null`，gvim 可能从 copy 管道读到 EOF 并退出。如果不做进程分离，GUI 可能随管道一起被杀掉。

### 9.5 剪贴板

鼠标拖拽释放时会通过以下脚本复制：

```text
copy-selection.sh
```

为什么不直接用 `copy-pipe-and-cancel "clip.exe"`：在 MSYS2 tmux 下这条路径不可靠。辅助脚本会写一个临时文件，设置 tmux 缓冲区，并把文件通过管道传给 `clip.exe`/`wl-copy`/`xclip`。

---

## 10. 文件树

状态：

```text
LATTICE_ENTRIES          filtered visible names
LATTICE_ENTRY_IS_DIR
LATTICE_TREE_SEARCH
LATTICE_TREE_FILTER
LATTICE_SHOW_HIDDEN
LATTICE_TREE_OFFSET
LATTICE_TREE_BODY
```

按键：

```text
j/k/arrows  move
Enter       enter directory / open file
h/Backspace parent
r           refresh
.           hidden files
o           open selected directory in system file manager
y           copy selected path to the clipboard
/           incremental name filter
```

过滤器会保留 `..`，并且只匹配名称。它不会递归搜索文件内容。

只要选区仍然可见，滚动偏移就会保持不变，这一点与命令列表相同。

---

## 11. 快照弹窗

快照是来自 `lattice_command` 第五个参数的仅用于显示的文本。

```text
p            open
right-click  open
PgUp/PgDn    scroll
wheel        scroll
Esc/q/click  close
```

弹窗只包含边框、命令体，以及——如果存在的话——一个空行后接快照内容。不要添加标题或页脚；它们已经因为视觉噪音被移除。

长行会按显示宽度换行，并考虑 CJK/emoji。

---

## 12. 环境与机器配置

### 12.1 机器 id

每次运行都会推导 id：

```text
Linux:   /etc/machine-id
Windows: MachineGuid via powershell.exe
fallback: HOSTNAME
```

它**不会缓存到 `LATTICE_STATE_DIR`**。该目录可能是跨机器共享的 U 盘；缓存 id 会在每台机器上被复用。

`LATTICE_MACHINE_ID` 仅在测试时覆盖它。

### 12.2 环境文件

```text
$LATTICE_STATE_DIR/env.conf
$LATTICE_STATE_DIR/env.d/<machine-id>.conf
```

先通用，后机器专用。显式环境变量优先于两者。

优先级：

```text
explicit environment
> machine file
> common env.conf
> built-in defaults
```

引导变量（`LATTICE_ENV_CONF`、`LATTICE_ENV_DIR`、`LATTICE_MACHINE_ID`）如果用来选择加载哪些文件，必须在启动前设置在进程环境中。在它们所定位的文件内部设置就太晚了。

### 12.3 便携布局

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

`LATTICE_STATE_DIR` 和 `LATTICE_CONFIG` 必须由启动器显式传入。不要将 `LATTICE_CONFIG` 指回仓库。

### 12.4 编辑器默认值

```text
LATTICE_EDITOR   default gvim
LATTICE_OPEN_CMD default "$LATTICE_EDITOR --remote-silent"
```

机器专用的绝对路径应放在机器环境文件中，而不是仓库里。

---

## 13. 性能说明

在开发机（MSYS2/UCRT64、tmux）上测得：

```text
1000 commands, 120x58
  load:       ~296 ms
  render:     ~8.5 ms/frame after row caching
  search:     ~70-106 ms

2000 commands (stress fixture)
  load:       ~729 ms
  render:     ~8.5 ms/frame
  search:     ~146 ms
```

历史性能很重要：

```text
history is capped at 512 entries by default
recent panel is capped at 10 unique commands, numbered 0-9
history rows are cached by command text and terminal width
```

历史行缓存上限为 512 条；文件树行缓存上限为 16384 条。滚轮事件只改变视口偏移；它不会重建视图，也不会移动选区。

重要的优化历史：

* 历史行在 `_lattice_fit` 之后缓存；没有缓存时，一个完整的历史帧会重新测量每条可见命令。
* 历史分批裁剪，而不是在写满后每条命令都重写。

* 最初的命令行缓存消除了重复的 CJK 宽度计算。
* 命令行缓存上限为 4096 条，并在宽度变化时清空。
* `_lattice_fit` 和 `_lattice_pad` 带有 ASCII 快速路径。
* 已从每次 `lattice_command_add` 调用中移除重名扫描；它曾让加载 1000 条命令耗时 9.4 秒。不要在加载路径上重新引入 O(N²) 扫描。

不要以跳过正确性为代价做优化：

* ASCII 快速路径在遇到 CJK 时必须回退到显示宽度代码。
* 每行缓存键包含终端列数，并在重排/重载时清空。

---

## 14. 信任与安全模型

受信任：

```text
commands.conf
commands.user.conf
env.conf
env.d/*.conf
executor/rc.sh
```

这些是 Bash，在 source 时可以执行任意代码。

不受信任：

```text
parameter values typed into the form
paths from the file tree
tmux copy-mode selections
```

参数值通过环境变量传递，并由命令作者负责引用。Lattice 从不对参数值做 `eval`，也从不把它插值进命令字符串。

编辑器和文件管理器辅助脚本会在启动前校验存在性。这是可用性检查，不是沙箱。

---

## 15. 已经遇到的陷阱

### 15.1 在拆分之前启动 TUI

这会让 TUI 缓存整个窗口宽度，并在自己的窗格中渲染错误。始终先完成拆分，再通过 respawn 启动 TUI。

### 15.2 从 TUI 内部拆分

被阻塞的 `split-window` 客户端可能冻结整个工作台。执行器缺失是一种错误，绝不能成为从 TUI 中拆分的理由。

### 15.3 关闭 TUI 或执行器

`Ctrl-b x` 对 TUI/执行器做了保护。用户仍然可以在执行器中输入 `exit`，或使用 `Ctrl-b &`。恢复需要新建会话；任意拆分出的窗格无法被提升为执行器，因为它们缺少执行器 rc。

### 15.4 tmux 窗格选项不会被继承

拆分出的窗格没有 `@lattice_role`。它只是一个手动 shell，不是执行器。

### 15.5 不能根据选区重新计算滚动偏移

每帧重新计算 `offset = selected - body + 1` 会导致点击可见的中间行时列表发生跳动。只要选区仍然可见，就应保留偏移。

### 15.6 终端反显渗色

每个渲染行都需要显式的 SGR 重置。否则选中行的反显视频会泄漏到后续行。

### 15.7 `str.sh` 的 stdout 污染

source `str.sh` 会打印语法探测输出。请在启动器中把 stdout 重定向到 `/dev/null`。不要移除该重定向。

### 15.8 CJK 宽度与逐帧开销

`str_display_width` 是正确的，但按行逐字符调用时开销很大。它的慢路径会跳过 ASCII 连续段，只对非 ASCII 字符进入码点宽度逻辑；不会保留无界的字符缓存。请使用 ASCII 快速路径和命令行缓存。快照文本由手动触发，可以走慢路径。

### 15.9 `copy-pipe` 到 `clip.exe`

在 MSYS2 tmux 下不可靠。请改用 `show-buffer`/辅助临时文件桥接。

### 15.10 gvim 继承管道

从 `copy-pipe` 启动的 GUI 编辑器可能读取选区 stdin 并退出。请把 stdin 从 `/dev/null` 重定向，并用 `setsid`/`nohup` 分离。

### 15.11 占位符引用

不要导出参数环境。在派发时用 `${value@Q}` 替换 `{{NAME}}`；占位符必须位于 shell 引号之外。

### 15.12 多行命令

没有会丢失的一次性上下文。渲染出的多行命令是一次字面粘贴；每一行看到的都是相同的值。

### 15.13 历史

历史保存渲染后的字面命令，包括参数值。只插入的 `@` 命令不会被保存，因为 Lattice 从不执行它们。

### 15.14 重名

用户文件可以覆盖基础命令。同一层内的重名会被忽略，并通过 stderr/状态输出提示，但启动会继续。这是有意为之：一个拼写错误不应该让工作台无法打开。

### 15.15 `q` 变成了隐患

`q` 过去在文件树模式下退出。现在已禁用；只有 `Ctrl-g` 退出。页脚使用 `^G`，不是 `G`。

### 15.16 U 盘上的 machine-id 缓存

绝不要把 machine-id 缓存写入 `LATTICE_STATE_DIR`。那会让每台主机都选中同一个机器文件。

### 15.17 `LATTICE_CONFIG` 指向仓库

仓库中的配置是冻结的示例。请让启动器指向 U 盘/用户配置。

---

## 16. 调试清单

### 语法

```bash
for f in src/lattice_bash/*.sh src/lattice_bash/*/*.sh ; do
    bash -n "$f" || echo "bad: $f"
done
```

### CLI

```bash
./src/lattice_bash/lattice.sh --version
./src/lattice_bash/lattice.sh --machine-id
./src/lattice_bash/lattice.sh --list-commands
```

### 配置

```bash
LATTICE_STATE_DIR=/x/.lattice \
LATTICE_CONFIG=/x/.lattice/commands.conf \
./src/lattice_bash/lattice.sh --list-commands
```

### tmux 状态

```bash
tmux list-sessions
tmux list-panes -a -F '#{session_name} #{pane_index} #{pane_id} #{@lattice_role} #{pane_width}'
tmux show -g mouse
tmux list-keys -T prefix | grep -E ' e | x | z '
```

### 执行器命令

执行器是一个普通的 Bash 提示符。用以下命令检查发送出去的命令：

```bash
history 1
```

没有上下文文件、DEBUG 陷阱或参数环境可供检查。

### TUI

在 UI 仍在变化期间，仓库中有意不放置 TUI 测试文件。请使用临时 tmux 会话进行手动测试：

```bash
tmux new-session -d -s t
tmux send-keys -t t '...lattice.sh --tui --no-tmux ...' Enter
tmux capture-pane -p -t t
```

---

## 17. 被拒绝的设计及原因

### 文件树中的文件预览

拒绝原因：每次光标移动都会引发文件 I/O 并拖慢导航。工作台用于导航和命令派发，不是用来阅读文件的。

### 命令的 `x`/`xo` 运行时

拒绝原因：为一个扁平命令列表加载类树会带来不必要的启动开销。并行数组更快，也更容易检查。

### 面板内的添加命令表单

移除原因：在宽度 30% 的 TUI 中做多字段编辑既慢又容易出错。请使用文本编辑器和 `R`。

### 遗留模板变量

拒绝原因：`$WB_*` 和 `$LP_*` 会产生空值或过期的 shell 值。请使用 `{{...}}` 占位符；渲染器会用 `@Q` 为它们加引用。

### 重名时硬失败

拒绝原因：一个拼写错误就会让工作台无法打开。跳过/报告并保持运行；修复后按 `R`。

### 从 TUI 重写 `commands.conf`

拒绝原因：会破坏注释/格式并有数据丢失风险。用户新增和隐藏使用独立文件。

### 可拖拽的窗格边框

在真实故障之后被拒绝：tmux 没有最小窗格宽度；拖拽可能压垮 TUI，而 WINCH 在窗格被销毁之后才到达。原生 tmux 调整大小绑定更安全。

### 快照标题/页脚

移除原因：`snapshot: name` 和 `Esc/q close` 是噪音。弹窗现在只显示内容。

### 仓库中硬编码的用户路径

拒绝原因：配置必须可移植。机器路径放在 `env.d/<machine>.conf` 中。

---

## 18. 未来：SSH

尚未实现。本节是设计地图，不是承诺。当前 v1.0 的循环有意保持本地。

SSH 支持有三种可能形态。它们的难度并不相同。

### 18.1 方案 A：远程优先（推荐的第一步）

完全在远程主机上运行 Lattice；本地终端只显示远程 tmux 会话。

```text
local terminal
  └── ssh -t host
        └── remote tmux
              ├── Lattice TUI
              └── remote executor
```

本地命令最终可以是这样：

```bash
lattice --ssh devbox:/home/me/project
```

或者只是一个包装脚本：

```bash
ssh -t devbox 'cd /home/me/project && /path/to/lattice.sh'
```

为什么这是最简单的：

```text
file tree, paths, executor and command transport all stay remote
no local/remote path mapping
no per-command SSH protocol
no remote file API
commands are fully rendered before transport
```

仍需要做的工作：

```text
remote dependency check: bash >= 4.4, tmux, vim, grep/sed/find
remote deploy/update (git or rsync)
terminal editor integration
OSC52 clipboard
remote machine env.d profile
```

编辑器是主要缺口。现有的 `eg` / `open-selection.sh` 路径会启动 GUI 编辑器。在无头远程主机上，实际可行的选择是：

```text
terminal vim in a remote tmux pane/window
remote gvim over X11 (not available on Windows terminals)
local gvim via SSHFS or scp:// URLs
```

终端 vim 模式会新增一个策略，例如：

```text
LATTICE_OPEN_MODE=gui|terminal
```

并在远程 tmux 窗口中打开 `vim +LINE FILE`，而不是启动 gvim。这是一种新的编辑器契约，不是一行改动。

远程优先 MVP 的估计：启动/依赖/tmux 大约 0.5–1 天，再加上编辑器和剪贴板工作。

### 18.2 方案 B：本地 TUI + 远程执行器

本地 TUI 负责渲染；右侧 tmux 窗格是一个 SSH shell；命令被发送到远程 shell。

```text
local tmux
├── local Lattice TUI
└── local pane running: ssh -tt host
```

这很有吸引力，因为本地渲染保持响应，本地编辑器可以继续使用 gvim。但它比远程优先难得多。

困难之处：

```text
remote file tree
local/remote path mapping
editor choice
SSH disconnect detection
clipboard
```

不要为每条命令打开一个 SSH 连接。请使用持久控制连接：

```text
ControlMaster auto
ControlPersist yes
ServerAliveInterval ...
```

后端的大致形态会是：

```text
list_dir(path)
stat(path)
send_command(literal_text)
open_file(remote_path, line)
```

本地后端就是今天的实现。SSH 后端必须实现同一接口。不要给每个 tmux/文件树函数都添加 `if remote` 分支。

命令在传输前已完全渲染。远程后端应接收相同的字面命令文本；不需要远程上下文文件或提示符陷阱。

传输仍可以是本地 tmux `send-keys` 向 SSH 窗格发送。这部分是可靠的；困难的是远程文件系统和路径契约。

### 18.3 方案 C：本地 TUI + 本地 gvim + 远程项目

最难的变体：

```text
remote file tree
local gvim editing remote files
remote executor
local/remote path mapping
```

真正的实现需要以下之一：

```text
SSHFS mount on the local machine
scp://host//absolute/path
rsync-based synchronization
```

每种方案都会带来各自的问题：Windows 上 SSHFS 的可靠性、保存延迟、重命名/删除语义、路径转换，以及过期挂载。不要从这里开始。

### 18.4 推荐的演进路径

```text
now:       local only; keep the current loop stable
step 1:    remote-first launcher + dependency check + remote tmux
step 2:    terminal-vim open mode + OSC52 clipboard
step 3:    only if needed: backend abstraction for local TUI + remote executor
step 4:    local gvim/SSHFS only after a proven file-system strategy
```

第一步不应该改动注册表、占位符渲染、字面传输或 tmux 角色。它应该在远程主机上复用这些机制。

### 18.5 任何 SSH 实现都必须满足的不变量

```text
No per-command SSH handshake.
No TUI-side interpolation of remote paths.
No eval of remote parameters.
No assumption that local paths equal remote paths.
No silent fallback to a local shell after SSH disconnect.
No direct split from the TUI.
```

断开的 SSH 窗格必须被显式检测到，命令必须以清晰的状态失败，而不是被粘贴到错误的 shell 中。

### 18.6 为什么推迟

SSH 会触及当前设计中最昂贵的部分：受信任的本地文件系统与远程 shell 之间的边界。一个只做了一半的混合方案可能看起来正确，却把命令发送到错误路径或打开错误的文件。

当前的本地循环小而稳定。SSH 应该作为一个独立的传输/后端层加入，而不是散落在各处的条件分支。

---

## 19. 变更清单

在提交结构性变更之前：

```text
[ ] bash -n all modified files
[ ] --version still prints v1.0.0.0
[ ] --list-commands works with the USB config
[ ] TUI starts, q no longer quits, Ctrl-g exits
[ ] executor receives the literal expanded command
[ ] command history contains the same literal
[ ] no `$WB_*` / `$LP_*` templates remain
[ ] command list click after scroll selects the visible row
[ ] snapshot popup has no title/footer
[ ] no new TUI test files unless explicitly requested
[ ] user-facing behavior documented in README.md
[ ] architecture/tradeoff documented here
```

如果变更影响以下任一契约，请先更新本文件，或与代码一起更新：

```text
placeholder syntax
literal expansion and @Q quoting
tmux roles
command config format
environment precedence
history limits
```

---

## 20. 术语表

```text
TUI             left pane; Lattice's renderer and input loop
executor        right pane; plain interactive Bash with Lattice rc
placeholder     {{WB_DIR}} / {{WB_FILE}} / {{WB_ROOT}} / {{PARAM}}
literal command final @Q-quoted shell command sent and stored
snapshot        optional display-only help text for a command
disabled list   names hidden without editing the source config
frozen example  config/commands.conf shipped in the repo
user catalog    commands.conf/commands.user.conf on the USB stick
owned session   tmux session created by the launcher; Ctrl-g closes it
half session    session missing tui or executor; killed and recreated
```

---

## 21. 最短的心智模型

如果你只记住一件事：

```text
TUI and executor are separate processes.
TUI never executes commands.
TUI expands {{placeholders}} with @Q, then pastes a literal command.
The executor is a plain Bash prompt with no context trap.
History stores the same literal command.
Config is trusted Bash.
Source config is never rewritten.
The tmux executor is found by role, not focus.
```
