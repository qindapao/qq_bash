# lattice_bash

A pure-Bash TUI workbench for tmux. Browse files and dispatch configured quick
commands into a dedicated executor pane without leaving the workbench.

Current version: **v1.0.0.0**

```bash
./src/lattice_bash/lattice.sh --version
```

Developer architecture, design tradeoffs and pitfalls: [DEVELOP.md](DEVELOP.md).

## Layout

```text
┌──────────────────────────┬────────────────────┐
│ Lattice TUI              │ executor shell     │
│ file tree                │ command output     │
└──────────────────────────┴────────────────────┘
```

The TUI is the left pane; commands are pasted into the right pane. The default
split is 30/70: the TUI gets about 30% and the executor about 70% (TUI minimum
24 columns). The executor is discovered by the tmux pane option
`@lattice_role=executor`, not by pane index. `auto`/`pane` targets currently
resolve to that executor.

## Resize panes

Use native tmux bindings:

```text
Ctrl-b Ctrl-Left/Right   resize by 1 column
Ctrl-b Alt-Left/Right    resize by 5 columns
Ctrl-b z                 zoom pane (asks y/n)
Ctrl-b Space             cycle layouts
```

Mouse click/selection/wheel are enabled. Border dragging is disabled because tmux has no minimum pane width and can destroy the TUI pane before WINCH can restore it. Use the keyboard resize bindings instead.

Border-drag control:

```bash
# Verify the current binding (no output means disabled)
tmux list-keys -n | grep MouseDrag1Border

# Disable (the launcher's default)
tmux unbind -n MouseDrag1Border

# Enable mouse border dragging (risk: a hard drag can kill the TUI pane)
tmux bind -n MouseDrag1Border resize-pane -M
```

The launcher runs the `unbind` on startup, so enabling it before `lattice` has no
effect. Enable it after the workbench is running, from another terminal or the
tmux command prompt. It is a tmux-server-global binding and persists until it
is unbound or the server restarts.

For an exact width, from inside the session:

```bash
tmux resize-pane -t "$(tmux display-message -p '#{session_name}'):work.0" -x 60%
```

The size is remembered by that tmux session. Mouse click/selection/wheel are
enabled; border dragging is intentionally disabled because tmux cannot enforce
a minimum pane width.

Long file names are truncated with `...`; the footer shows the selected entry's
full path. The tree deliberately does not wrap entries, because wrapping breaks
the one-entry-per-row selection model. The executor prompt uses
`PROMPT_DIRTRIM=2`, so deep directories render as `.../parent/leaf$` in blue
with a green prompt sigil.
instead of consuming the whole input line.

In the left tree, a single mouse click selects a row. Double-click a directory
to enter it, `..` to go to the parent, or a file to open it with
`LATTICE_OPEN_CMD`. The right pane still uses tmux copy mode for wheel history
and selection.

## Quick start

```bash
cd /path/to/qq_bash
./src/lattice_bash/lattice.sh --root "$PWD"
```

## Launcher function

For a portable USB setup, keep Lattice user data on the USB stick and pass it
explicitly. This is the recommended launcher:

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

First-time setup on the USB stick:

```bash
mkdir -p /x/.lattice/env.d
cp /d/code/qq_bash/src/lattice_bash/config/commands.conf \
   /x/.lattice/commands.conf
```

Then reload and start:

```bash
source ~/.bashrc
lattice
lattice /d/code/other-project
```

The portable layout is:

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

`LATTICE_STATE_DIR` and `LATTICE_CONFIG` are deliberately inline environment
assignments: they apply to the Lattice process and the tmux TUI it starts.
Do not point `LATTICE_CONFIG` back into the repository; that file is only a
frozen example.

To keep the function out of `.bashrc`, put it in a separate file:

```bash
# ~/.bashrc
[ -r ~/.config/lattice/launcher.bash ] && \
    . ~/.config/lattice/launcher.bash
```

and place the `lattice()` function above in
`~/.config/lattice/launcher.bash`.

Each invocation creates a different tmux session. The timestamp is enough for
interactive use: opening another workbench by hand takes far longer than one
second. Exit each one with `Ctrl-g`; that closes the session it owns.

No `cd` is required; `lattice.sh` resolves its own library directory through
`BASH_SOURCE`. Do not use `--root_$(date +%s)`: that is an unknown option. The
correct option is `--root /path/to/project`.

A fixed alias still works for a single reusable workbench on a local config:

```bash
alias lattice='/d/code/qq_bash/src/lattice_bash/lattice.sh --root /d/code'
```

Re-running that alias attaches the same `lattice` session. Use the function
above when you want a new session every time.

Run this from the outer UCRT64 shell, not from inside an existing Lattice
executor pane. If you detached with `Ctrl-b d`, `tmux list-sessions` shows the
old session; `Ctrl-g` is the intended clean exit.

Requirements: Bash 5.x and `tmux` (Linux: your package manager; MSYS2/UCRT64: `pacman -S tmux`).
No drive-letter or Windows-only path is assumed; runtime paths use `HOME`, `TMPDIR`,
and `BASH_SOURCE`.

Inside tmux:

```bash
./src/lattice_bash/lattice.sh --tui --root "$PWD"
```

If there is no executor pane, the TUI reports an error instead of splitting from inside the TUI.

## Keys

```text
j/k, ↑/↓     move
Home / End   first / last entry
Enter        enter directory / run selected command
h            parent directory
Backspace    parent directory
r            refresh
.            toggle hidden files
o            open selected directory in the system file manager
y            copy selected path to the clipboard
@a / @b / @c copy selected full path into WB_A/WB_B/WB_C
```
:            quick command palette
/            filter file/dir names in tree; search commands in palette
H            history
Ctrl-r       focus recent commands (then 1-8 or Enter)
/            search history (in history mode)
R            reload commands (tree or palette)
?            help
Ctrl-g       quit and close the Lattice session
```

## User environment and machine identity

User-specific paths belong outside the repository:

```text
~/.lattice/env.conf                  shared by all machines
~/.lattice/env.d/<machine-id>.conf   one machine
```

These files are trusted Bash and are read once when Lattice starts.

### First-time setup

```bash
cd /path/to/qq_bash
./src/lattice_bash/lattice.sh --machine-id
```

Example output:

```text
machine: 72a9e8a6-0709-41fa-bdad-f5bbaa3cc9d8
common:  /home/me/.lattice/env.conf
machine: /home/me/.lattice/env.d/72a9e8a6-0709-41fa-bdad-f5bbaa3cc9d8.conf
```

Create the machine file:

```bash
mkdir -p ~/.lattice/env.d
$EDITOR ~/.lattice/env.d/72a9e8a6-0709-41fa-bdad-f5bbaa3cc9d8.conf
```

Typical machine file:

```bash
# ~/.lattice/env.d/<machine-id>.conf
LATTICE_EDITOR=/d/programes/vim/vim91/gvim.exe
LATTICE_OPEN_CMD='/d/programes/vim/vim91/gvim.exe --remote-silent'
LATTICE_RECENT_LIMIT=8
```

Typical common file:

```bash
# ~/.lattice/env.conf
LATTICE_RECENT_LIMIT=8
```

Restart Lattice after changing these files:

```text
Ctrl-g
lattice
```

### Machine id

The id comes from:

```text
Linux:   /etc/machine-id
MSYS2:   HKLM\SOFTWARE\Microsoft\Cryptography\MachineGuid
fallback: $HOSTNAME
```

The id is derived on every run and is **not** written into
`LATTICE_STATE_DIR`. That directory may live on a USB stick used by several
machines; a cached id there would be reused on every machine and select the
wrong machine file.

All machine files can live together in one portable directory:

```text
/mnt/usb/lattice/env.conf
/mnt/usb/lattice/env.d/<machine-a>.conf
/mnt/usb/lattice/env.d/<machine-b>.conf
```

Set the portable root explicitly:

```bash
LATTICE_STATE_DIR=/mnt/usb/lattice lattice
```

Each machine still reads only its own `<machine-id>.conf`.

Override the id only for testing:

```bash
LATTICE_MACHINE_ID=test-machine lattice
```

### Precedence

```text
explicit environment variable
> machine-specific file
> common env.conf
> built-in defaults
```

For example:

```bash
LATTICE_EDITOR=/tmp/test-editor lattice
```

wins over both files.

### What users normally configure

Most users only need these:

```text
LATTICE_EDITOR          editor binary; default gvim
LATTICE_RECENT_LIMIT    recent-command count; default 8
LATTICE_ROOT            optional initial tree root
```

`LATTICE_OPEN_CMD` is an advanced override. By default it is derived:

```bash
LATTICE_OPEN_CMD="$LATTICE_EDITOR --remote-silent"
```

Set it explicitly only when the editor needs different arguments.

Everything else is internal or for development:

```text
LATTICE_CONFIG          use --config instead
LATTICE_STATE_DIR       advanced profile/state relocation
LATTICE_ENV_CONF        advanced env-file relocation
LATTICE_ENV_DIR         advanced env-file relocation
LATTICE_HISTORY_FILE    derived from state dir
LATTICE_HISTORY_LIMIT   history entry cap; default 1000
LATTICE_ORDER_FILE      derived from state dir
LATTICE_USER_COMMANDS_FILE  user-added commands
LATTICE_DISABLED_FILE   hidden command names
LATTICE_EXECUTOR_RC     internal shell hook
LATTICE_TMUX_BIN        tmux auto-detection
LATTICE_TMUX_SESSION    use --session instead
LATTICE_MACHINE_ID      testing override
```

All `LATTICE_*` variables listed above are supported overrides; "internal"
means "not recommended as a user knob", not "ignored". If you set one, Lattice
uses it. CLI options such as `--root`, `--config` and `--session` still win over
environment values.

The bootstrap variables `LATTICE_ENV_CONF`, `LATTICE_ENV_DIR` and
`LATTICE_MACHINE_ID` must be set in the process environment before startup if
you want them to select which files are loaded. Setting them inside the file
they are supposed to locate is too late.

Normal machine file:

```bash
# ~/.lattice/env.d/<machine-id>.conf
LATTICE_EDITOR=/d/programes/vim/vim91/gvim.exe
LATTICE_RECENT_LIMIT=8
```

Do not expose every internal variable as a user knob. If a path or session
matters, prefer the CLI (`--root`, `--config`, `--session`).

### Dynamic values: placeholders only

Commands use explicit placeholders:

```text
{{WB_ROOT}}     project root
{{WB_DIR}}      current tree directory
{{WB_FILE}}     selected file; empty for a directory
{{WB_CLIP}}     current system clipboard
{{WB_A}}        register A
{{WB_B}}        register B
{{WB_C}}        register C
```

Before sending, Lattice replaces each placeholder with a shell-quoted literal:

```bash
lattice_command 'cd here' 'dir'  'pane' 'cd {{WB_DIR}}'
lattice_command 'view'    'file' 'pane' 'gvim {{WB_FILE}}'
lattice_command 'diff A C' 'dir' 'pane' 'diff -u {{WB_A}} {{WB_C}}'
```

Registers are shared with the executor:

```text
tree:       @a / @b / @c   copy selected full path into WB_A/B/C
executor:   Ctrl-b a/b/c   copy system clipboard into WB_A/B/C
executor:   Ctrl-b v       refresh WB_CLIP preview from the clipboard
```

`Ctrl-b c` overrides tmux new-window inside the Lattice session.  
The status-left preview shows `CLIP`, `A`, `B`, `C` with the first five
characters and `...` when longer; empty values are omitted. The preview
refreshes when a register or clipboard cache changes; arbitrary external
clipboard changes wait for `Ctrl-b v` or the next clipboard command.

The `CLIP` preview cache stores only the first five characters; the full
clipboard is read on demand for `{{WB_CLIP}}` and is not persisted by the cache
writer. Registers intentionally store their full values because the user
explicitly placed them there.

A clipboard read timeout is a failure, not partial content: the staged file is
discarded, the cache/register is left unchanged, and a command using
`{{WB_CLIP}}` is not sent. An actually empty clipboard is still a successful
read and becomes an empty argument.

Do not use `$WB_DIR`, `$WB_FILE`, `$WB_ROOT`, `$WB_A/B/C`, `$WB_CLIP`, or
`$LP_*` in command templates. They are rejected at dispatch time. The executor
receives the final literal command with no environment prefix or hidden
context.

Do not put these values in `env.conf`; they are runtime context, not user
settings.

## Configuration

`config/commands.conf` is a **frozen example**, not the user's command
catalog. Copy it to your own config (for example
`/x/.lattice/commands.conf`) and maintain that copy. The Lattice repository
does not keep adding example commands.

A ready-to-copy user-command example is
`config/commands.user.example.conf`; it is not loaded automatically.

The example file is trusted Bash configuration:

```bash
lattice_command 'git status' 'dir'  'pane' 'GIT_TERMINAL_PROMPT=0 git -C {{WB_DIR}} status --short --branch' '只查看当前目录。'
lattice_command 'git check all' 'dir' 'pane' 'GIT_TERMINAL_PROMPT=0 timeout 60 git_check_status.sh -o {{WB_DIR}}' '扫描所有仓库，较慢。'
lattice_command 'git diff'   'file' 'pane' 'git diff -- {{WB_FILE}}' '查看选中文件的 diff。'
```

There are no command shortcut keys. Open the `:` palette, use `j/k` or arrows
to select, press `/` to enter search and type to filter, and press Enter to
send; the palette stays open after dispatch. While search is active, printable
keys such as `p`, `D` and `R` go into the query; their command shortcuts only
apply when search is inactive. Esc leaves search (clearing the
query), then Esc leaves the palette. Opening search mirrors the query into the
tmux status bar and replaces the header with a `search>` line, so the query
stays visible without hiding the executor pane. Exiting search restores the
previous status bar. PageUp/PageDown and the mouse wheel move through a long
list; the header shows the visible range. A `*` marks a command
with a snapshot and `+` marks a user-added command. Rows show the command name,
scope, and target. A one-line preview below the list shows the selected command
body only. The command body is not rendered in the list itself, but remains
searchable. Press `p` or right-click a row to see the full command body; if the
command has a snapshot, both sections are shown. The popup has no title or
footer.
Moving to another row, clicking elsewhere, or Esc/q dismisses it automatically.
Press `D` to disable the selected command. Add commands manually in
`commands.user.conf`, then press `R` in the palette to reload, or restart
Lattice.

The optional fifth `lattice_command` argument is a snapshot shown by `p` or
right-click. The optional sixth argument is a whitespace-separated parameter
list. Snapshots are included in search and may contain Chinese.
`scope` is informational in 1.0. `target` is the transport policy
(`pane`, `auto`, `pane:<id>`, …).

### Parameterized commands

```bash
lattice_command 'grep current tree' 'dir' 'pane' \
  'grep -n --color=auto -- {{PATTERN}} {{WB_DIR}}' \
  '按模式搜索当前文件树' \
  'PATTERN'
```

Selecting the command and pressing Enter opens a form instead of sending
immediately. Values are plain input strings, not shell fragments. Lattice
quotes each value with the `${value@Q}` operator and substitutes it before
sending.

```text
PATTERN   -> placeholder {{PATTERN}}
NAME=def  -> default value def
```

There is no `LP_` namespace and no `eval`. A parameter named `PATTERN` is only
addressable as:

```bash
{{PATTERN}}
```

The final literal command is stored in history, so it can be rerun directly.

All arguments after the snapshot are parameters. They may be written
separately:

```bash
lattice_command 'grep in target' 'dir' 'pane' \
  'grep -nHE --color=auto -- {{PATTERN}} {{TARGET_DIR}}' \
  '搜索指定目录' \
  'PATTERN' 'TARGET_DIR=.'
```

or as one whitespace-separated argument:

```bash
lattice_command 'grep in target' 'dir' 'pane' \
  'grep -nHE --color=auto -- {{PATTERN}} {{TARGET_DIR}}' \
  '搜索指定目录' \
  'PATTERN TARGET_DIR=.'
```

Placeholders must be outside single/double quotes:

```bash
grep -- {{PATTERN}} {{WB_DIR}}      # correct
grep -- "{{PATTERN}}" {{WB_DIR}}    # wrong
```

Placeholder names follow `[A-Za-z_][A-Za-z0-9_]*`, are case-sensitive, and must
be declared in the parameter list. These names are reserved for dynamic context
and cannot be parameters:

```text
WB_ROOT WB_DIR WB_FILE WB_CLIP WB_A WB_B WB_C
```

An undeclared name is an error and the command is not sent. The same
placeholder may appear multiple times and always receives the same value:

```bash
lattice_command 'same twice' 'dir' 'pane' \
  'diff -u {{A}} {{A}}' \
  '' \
  'A'
```

Snapshot text is display-only and is never placeholder-expanded.

A command name starting with `@` is **insert-only**. Lattice pastes the command
skeleton without pressing Enter and does not add it to history:

```bash
lattice_command '@ssh' 'dir' 'pane' 'ssh ' '插入 SSH 骨架；不会自动执行。'
```

The status line reports that the skeleton was inserted. Lattice switches focus
to the executor automatically; use `Ctrl-b ←` to return to the TUI. Press Enter
yourself when the command is ready. This is the intended mode for interactive
commands such as SSH, REPLs, and prompts.

An empty fifth argument means there is no snapshot. Parameters can still
follow it:

```bash
lattice_command 'grep in target' 'dir' 'pane' \
  'grep -nHE --color=auto -- {{PATTERN}} {{TARGET_DIR}}' \
  '' \
  'PATTERN' 'TARGET_DIR=.'
```

A command with an empty snapshot still shows its command body in the popup;
`p` / right-click reports `COMMAND` only.

The form uses almost the full TUI pane width so long values remain readable.
It shows one field per parameter; defaults are prefilled. The active field uses
the terminal cursor rather than an inserted underscore, so the cursor does not
occupy or shift a character cell; the terminal's own cursor shape is preserved. Enter moves to the next field
and sends after the last one.

```text
Tab       next field
Shift-Tab previous field
Ctrl-u    clear current field
Ctrl-d    restore its default value
Esc       cancel
```

Enter moves to the next field and sends after the last one. Tab and Shift-Tab
only move between fields; they do not insert a literal tab. To pass a literal
tab as a parameter value, use the ANSI-C form, for example `$'a\tb'`; it becomes
a preview-only value that you confirm with Enter.

### Explicit ANSI-C value

If a parameter is one complete `$'...'` word, Lattice treats it as an already
quoted literal and inserts it verbatim. The command is then **inserted without
Enter**, focus moves to the executor, and you review it before pressing Enter.

```text
$'a b'
$'line1\nline2'
$'it\'s 中文'
```

The value must be exactly one complete ANSI-C word. Malformed attempts such as
`$'a'; id` or `$'a'$'b'` are re-quoted as ordinary literal text and still use
preview insertion. This is not shell evaluation: `$'...'` never runs command
substitution.

Preview commands from a valid `$'...'` parameter are recorded in Lattice history
as the inserted text, before any manual edits. Re-running them uses that
pre-edit text; the user is responsible for reviewing it. Malformed `$'...'`
attempts and `@` skeletons are not recorded because they are incomplete or
invalid command text.

A command whose template uses `{{WB_CLIP}}` is stored in history as its
expanded literal, so history may contain the clipboard text. Clear
`history.tsv` if that content is sensitive; registers are always stored in
full because they are explicit user state.

Parameterized commands are written to history as their fully expanded literal
command. Special characters in values need no user escaping: type the value
literally and Lattice quotes it for the shell.

### Quotes inside command bodies

The command is one Bash string. The outer quoting belongs to the config file;
quotes inside it belong to the executor shell.

Preferred outer form is single quotes:

```bash
lattice_command 'printf one' 'dir' 'pane' \
  'printf "%s\n" "hello"'
```

To include a literal single quote, close and reopen the outer string:

```bash
lattice_command 'it works' 'dir' 'pane' \
  'printf "%s\n" "it'\''s fine"'
```

When the body has no `$` or backticks, outer double quotes are often more
readable, especially with a single-quoted printf format:

```bash
lattice_command 'snapshot metachars' 'dir' 'pane' \
  "printf '%s\\n' 'snapshot demo'" \
  'snapshot text'
```

`\\n` becomes `\n` when the config file is sourced; `printf` interprets it.
Placeholders still go outside shell quotes:

```bash
lattice_command 'echo path' 'file' 'pane' \
  'printf "%s\n" {{WB_FILE}}'
```

### Literal newlines and tabs

`commands.conf` and `commands.user.conf` are Bash files, so use Bash ANSI-C
quoting for literal control characters:

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

`$'...'` is processed by Bash when the config file is sourced. By the time
`lattice_command` receives the command, `\n` and `\t` are already real bytes.
The TUI stores that string and sends it through the tmux paste buffer, so
newlines and tabs survive the transport.

For external commands this is safe because the executor shell parses the
stored command normally. A newline inside quotes becomes part of one argument:

```bash
printf "%s" "
"
```

A newline outside quotes separates commands, which is intentional:

```bash
lattice_command 'two commands' 'dir' 'pane' \
  $'echo one\necho two' \
  '执行两条命令'
```

`$'...'` does not bypass quoting. Dynamic values belong in placeholders:

```bash
lattice_command 'echo value' 'dir' 'pane' \
  'printf "%s\n" {{PATTERN}}' \
  '打印参数' \
  'PATTERN'
```

History normalizes tabs and newlines to spaces; use this for commands whose
exact multiline history is not important.

### Add and delete commands

There is no in-panel add form. Add commands with a text editor:

```bash
$EDITOR /x/.lattice/commands.user.conf
```

Example:

```bash
lattice_command 'ps xf' 'dir' 'pane' 'ps -xf' '读取进程树'
```

Save, then press `R` in the palette, or restart Lattice. Restart is fast.

Delete from the palette:

```text
D        disable selected command (writes commands.disabled)
y        confirm deletion
```

Files:

```text
commands.user.conf    manually maintained user commands
commands.disabled     names hidden from the registry
```

`commands.conf` is the source file and is never rewritten by the TUI. Base
commands are disabled rather than deleted. User commands remain in the user
file but are hidden by the disabled list. `R` reloads everything.

### Duplicate command names

Names should be unique.

```text
commands.user.conf overrides commands.conf
duplicate inside the same file is ignored
```

A duplicate is reported on stderr and in the TUI status:

```text
lattice: duplicate command: name
config: 1 duplicate name(s) ignored
```

Lattice still starts. A malformed config should not leave the user unable to
open the workbench; fix the file and press `R`.

If a name is listed in `commands.disabled`, remove it from that file before
reusing the name.

A command receives:

```text
{{WB_ROOT}}    project root
{{WB_DIR}}     current directory; updates when you enter/parent a directory
{{WB_FILE}}    selected file, empty for a directory
```

The left status line shows:

```text
DIR /d/code/qq_bash  FILE /d/code/qq_bash/src/lattice.sh
```

`WB_ROOT` is used as the outer terminal title. The window list is removed
because Lattice opens a single window. Status updates are coalesced in the
background, so moving the selection does not block on a tmux call.

Palette order is stored separately in:

```text
~/.lattice/command-order.tsv
```

It is not written back into `commands.conf`. Reorder the selected row with
Alt-Up/Alt-Down, or pin it to the top with Ctrl-t. The order is saved
immediately and survives reloads and new sessions. New commands missing from
the order file are appended in config order.

## Recent commands

The left-bottom panel shows the last unique commands dispatched by Lattice.
`Ctrl-r` focuses it, `j/k` selects and Enter reruns. While focused, `1`-`8`
rerun the corresponding recent command. Numeric keys do nothing in tree
mode.

## History

Only commands dispatched by Lattice are recorded, in:

```text
~/.lattice/history.tsv
```

Entries store the final literal command, including expanded placeholders and
parameter values. For example the file contains:

```bash
grep -n -- '/d/code/qq_bash/file.txt'
```

not the template. Rerunning an entry executes the same literal command.

Parameterized commands are recorded with their values, so they can be rerun
directly. Commands run directly in another shell are not captured.

Press `/` in the history panel for incremental search. Type to filter, `Esc`
leaves search, and `Esc` again returns to the tree. Enter reruns the selected
entry. History entries can also be searched with `/` and re-run with Enter.

Default limits:

```text
history entries   1000
recent commands   8
```

The oldest history entries are pruned when the limit is exceeded.
`LATTICE_HISTORY_LIMIT` changes the history cap for advanced use.

## Copying output / interacting with the executor

The right pane is a normal interactive Bash shell. Focus it with `Ctrl-b →`
(or `Ctrl-b o`) and type there. Lattice shortcuts only apply while the left
pane is active.

For copy mode:

```text
Ctrl-b [        enter copy mode
arrows/PgUp     move
Space           start selection
Enter           copy
Ctrl-b ]        paste inside tmux
q               leave copy mode
```

For mouse selection and wheel scrolling:

```bash
tmux set -g mouse on
```

The launcher enables `set-clipboard on` and, when `clip.exe`/`wl-copy`/
`xclip` is available, binds mouse drag-release to the system clipboard. Use a
normal left-drag in the right pane (not Shift+drag): it can cross lines, and
the release writes the selection to the clipboard. The selection also stays in
tmux's buffer. Press `q` if you want to return to the shell, then:

```text
Ctrl-b e        open last buffer as file[:line], or a directory in the file manager
Ctrl-b ]        paste the last buffer
```

For a line that is already visible, no selection or buffer is needed:

```text
Alt + left click    open the line under the pointer
Ctrl + left click   same, as a terminal fallback
```

The line parser trims leading whitespace and ANSI escapes, then scans
whitespace-separated tokens from the start. The first existing token wins:

```text
1. path:line   -> editor at that line
2. path        -> editor
3. directory   -> system file manager
4. nothing existing -> no action
```

Only existing paths are considered. `Ctrl-b e` remains the explicit
buffer-based action; it does not try to read the mouse position.

`Ctrl-b o` is tmux's normal next-pane switch; it is unrelated to the editor
action.

There is no graphical scrollbar in the executor. Use `Ctrl-b [` then PgUp/PgDn
(or the mouse wheel) to browse tmux scrollback; `q` leaves copy mode. Sending
a command from the palette automatically leaves copy mode first, so the
command reaches the shell prompt instead of the copy buffer.

### Splitting the executor

From the executor shell, split top/bottom:

```bash
tmux split-window -v -c "$PWD"
```

Left/right:

```bash
tmux split-window -h -c "$PWD"
```

The default tmux prefix equivalents are:

```text
Ctrl-b "     split top/bottom
Ctrl-b %     split left/right
Ctrl-b o     next pane
Ctrl-b z     zoom pane (asks for confirmation)
Ctrl-b x     close current pane
```

New split panes are **not** tagged as the Lattice executor:

```text
TUI commands still go to the original executor
the new pane is for manual commands
```

In any split pane, selecting a path and pressing `Ctrl-b e` still opens that
file or directory using the active pane's current directory.

#### Closing splits safely

The TUI pane and original executor are both protected from an accidental
`Ctrl-b x`:

```text
Ctrl-b x on TUI or executor -> message, pane is not closed
Ctrl-b x on a split         -> normal confirmation
```

To close only the extra split:

```text
Ctrl-b q        briefly show pane numbers
Ctrl-b o        cycle to the split
Ctrl-b x        close active pane, confirm y
```

Never use `Ctrl-b &` unless you intend to kill the entire window, including
the TUI and original executor. It is not guarded because it is a deliberate
whole-window operation; `Ctrl-b d` only detaches and is safe.

If the original executor is deliberately exited from its shell, TUI commands
fail with `no executor pane`. Recover by starting a fresh `lattice` session;
there is no reliable way to promote an arbitrary split back into the Lattice
executor because it lacks the executor rc and prompt setup.

On Windows, an explicit clipboard bridge is:

```bash
tmux set-buffer -- "$(powershell.exe -NoProfile -Command Get-Clipboard)"
tmux paste-buffer -p
```

In Windows Terminal, `Shift+drag` usually selects text without tmux
intercepting the mouse.

### Open `file:line` in the editor

The executor provides `eg`:

```text
eg path/to/file:42
eg path/to/file
```

`eg` uses `LATTICE_EDITOR` (default gvim) and `--remote-silent +LINE`.
A grep line such as `path/file.sh:42: pattern` is parsed correctly; relative
paths resolve against the executor's current directory.

For the mouse workflow:

```text
Alt+left click on path/file.sh:42 in the right pane
```

No drag or copy mode is required. The line parser scans from the beginning and
uses the first existing token:

```text
path:line -> file -> directory -> no action
```

The older selection workflow still works:

```text
normal drag-select path/file.sh:42 in the right pane
release
Ctrl-b e
```

Use `q` first if copy mode is still active. `Ctrl-b e` opens the last tmux
buffer as `file:line`; if the selected path is a directory it opens that
directory in the system file manager instead of the editor. Select only the
`path:line` token, not a filename and line number separated by spaces. For
grep, use:

```bash
grep -n --color=auto pattern path
rg -n --color=auto pattern path
```

`--color=auto` highlights matches when writing to a terminal; use
`--color=always` only when piping and the consumer understands ANSI.

If the selected path is not an existing file, the helper copies it to the tmux
buffer and shows a short message instead of opening the wrong file. Automatic
clickable grep output is not enabled because it requires parsing arbitrary
output and has a higher risk of opening the wrong path.

## Architecture

```text
app/state.sh       state, paths, terminal sizing
fs/tree.sh         directory listing and navigation
cmd/registry.sh    array command registry + commands.conf loader
cmd/history.sh     TSV history + recent-command cache
cmd/tmux.sh        pane discovery/sending
cmd/executor.sh    target resolution and command sending
ui/render.sh       ANSI renderer
ui/event.sh        key loop
```

The command registry and history are plain Bash arrays plus TSV files; they do
not depend on the `x`/`xo` runtime. `lattice.sh` creates the tmux session and
starts the TUI.

## Status

1.0.0.0 is a runnable framework: file tree, quick commands, tmux sending,
history, reload, help, parameterized commands, and user command overlays.
File preview was removed because it made navigation too slow. Editing,
git UI, and structured output capture are intentionally out of scope.
