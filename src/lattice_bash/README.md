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

### Dynamic values: do not configure

Lattice writes these immediately before each executor command:

```text
WB_ROOT     project root
WB_DIR      current tree directory
WB_FILE     selected file; empty for a directory
```

They are available inside command definitions:

```bash
lattice_command 'pwd'     'dir'  'pane' 'pwd'
lattice_command 'cd here' 'dir'  'pane' 'cd "$WB_DIR"'
lattice_command 'view'    'file' 'pane' 'gvim "$WB_FILE"'
```

Do not put `WB_*` in `env.conf`; they are runtime context, not user settings.

## Configuration

`config/commands.conf` is a **frozen example**, not the user's command
catalog. Copy it to your own config (for example
`/x/.lattice/commands.conf`) and maintain that copy. The Lattice repository
does not keep adding example commands.

A ready-to-copy user-command example is
`config/commands.user.example.conf`; it is not loaded automatically.

The example file is trusted Bash configuration:

```bash
lattice_command 'git status' 'dir'  'pane' 'GIT_TERMINAL_PROMPT=0 git -C "$WB_DIR" status --short --branch' '只查看当前目录。'
lattice_command 'git check all' 'dir' 'pane' 'GIT_TERMINAL_PROMPT=0 timeout 60 git_check_status.sh -o "$WB_DIR"' '扫描所有仓库，较慢。'
lattice_command 'git diff'   'file' 'pane' 'git diff -- "$WB_FILE"' '查看选中文件的 diff。'
```

There are no command shortcut keys. Open the `:` palette, use `j/k` or arrows
to select, press `/` to enter search and type to filter, and press Enter to
send; the palette stays open after dispatch. Esc leaves search (clearing the
query), then Esc leaves the palette. Opening search mirrors the query into the
tmux status bar and replaces the header with a `search>` line, so the query
stays visible without hiding the executor pane. Exiting search restores the
previous status bar. PageUp/PageDown and the mouse wheel move through a long
list; the header shows the visible range. A `*` marks a command
with a snapshot and `+` marks a user-added command. Rows show the command name,
scope, and target. A one-line preview below the list shows the selected command
body only. The command body is not rendered in the list itself, but remains
searchable. Press `p` or right-click a row for the full snapshot content.
The snapshot popup shows only the snapshot text, with no title or footer.
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
  'grep -n --color=auto -- "$LP_PATTERN" "$WB_DIR"' \
  '按模式搜索当前文件树' \
  'PATTERN'
```

Selecting the command and pressing Enter opens a form instead of sending
immediately. Values are supplied as environment variables in the executor;
they are never interpolated into the command string and there is no `eval`.

```text
PATTERN   -> exported as $LP_PATTERN
NAME=def  -> default value def
```

Parameters are namespaced. A parameter named `PATTERN` is never exported as
bare `$PATTERN`; it is available as:

```bash
"$LP_PATTERN"
```

This avoids clobbering `PATH`, `HOME`, or user environment variables. A
parameter block is one-shot: `LP_*` values are available while the command
runs, then cleared at the next prompt. Stale values are also unset before a new
command loads its parameters.

All arguments after the snapshot are parameters. They may be written
separately:

```bash
lattice_command 'grep in target' 'dir' 'pane' \
  'grep -nHE --color=auto -- "$LP_PATTERN" "$LP_TARGET_DIR"' \
  '搜索指定目录' \
  'PATTERN' 'TARGET_DIR=.'
```

or as one whitespace-separated argument:

```bash
lattice_command 'grep in target' 'dir' 'pane' \
  'grep -nHE --color=auto -- "$LP_PATTERN" "$LP_TARGET_DIR"' \
  '搜索指定目录' \
  'PATTERN TARGET_DIR=.'
```

A command name starting with `@` is **insert-only**. Lattice pastes the command
skeleton without pressing Enter and does not add it to history:

```bash
lattice_command '@ssh' 'dir' 'pane' 'ssh ' '插入 SSH 骨架；不会自动执行。'
```

The status line reports that the skeleton was inserted. Switch to the executor
with `Ctrl-b →`, finish the command, and press Enter yourself. This is the
intended mode for interactive commands such as SSH, REPLs, and prompts.

An empty fifth argument means there is no snapshot. Parameters can still
follow it:

```bash
lattice_command 'grep in target' 'dir' 'pane' \
  'grep -nHE --color=auto -- "$LP_PATTERN" "$LP_TARGET_DIR"' \
  '' \
  'PATTERN' 'TARGET_DIR=.'
```

A command with an empty snapshot is not marked with `*`, and `p` /
right-click reports that it has no snapshot.

The form shows one field per parameter; defaults are prefilled. Enter moves to
the next field and sends after the last one.

```text
Ctrl-u    clear current field
Ctrl-d    restore its default value
Esc       cancel
```

Commands that still use bare `$PATTERN` must be updated to
`$LP_PATTERN`.

Parameterized commands are intentionally not written to history yet: replaying
one would need its parameter values. Re-run it from the palette and enter the
parameters again.

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

`$'...'` does not bypass quoting and is not an injection defense. Dynamic
values still belong in environment variables with quotes:

```bash
lattice_command 'echo value' 'dir' 'pane' \
  'printf "%s\n" "$LP_PATTERN"' \
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
WB_ROOT    project root
WB_DIR     current directory; updates when you enter/parent a directory
WB_FILE    selected file, empty for a directory
```

## Command order

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

Entries store the command template, not expanded values. For example the file
contains:

```bash
grep -n -- "$WB_DIR/file.txt"
```

not the expanded path. Rerunning it recreates the current executor context, so
`$WB_DIR` and `$WB_FILE` resolve against the current selection.

Parameterized commands are intentionally not written: replaying one would need
the parameter values. Use the palette and enter them again.

Commands run directly in another shell are not captured. History entries can
be searched with `/` and re-run with Enter.

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
(or the mouse wheel) to browse tmux scrollback; `q` leaves copy mode.

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
executor because it lacks the executor rc/context hook.

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
cmd/executor.sh    target resolution and context injection
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
