English | [简体中文](DEVELOP_CN.md)

# Lattice — Developer Notes

Status: **v1.0.0.0**  
Audience: the person maintaining or debugging Lattice years from now.  
User-facing documentation: [README.md](README.md).

This document explains the architecture, the contracts between processes, the
non-obvious implementation choices, and the traps that have already caused
bugs. Read the whole file before making structural changes.

---

## 1. What Lattice is

Lattice is a pure-Bash TUI workbench for a local tmux session:

```text
terminal
  └── tmux session
        ├── left pane  : Lattice TUI (file tree + command palette)
        └── right pane : executor shell (normal interactive Bash)
```

The TUI does four jobs:

```text
browse files
select a command
collect optional parameters
expand {{placeholders}} and paste the literal command
```

It does **not** execute commands, capture output, parse stdout, or manage the
executor's job control.

### Non-goals

These are deliberate omissions, not unfinished features:

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

The project values stability, startup speed, and predictable state over feature
count.

---

## 2. Design principles

### 2.1 Separate processes, one-way control

The TUI and executor are independent processes in separate tmux panes.

```text
control plane : TUI -> literal command + tmux paste -> executor
data plane    : executor -> tmux pane rendering
```

The TUI never reads executor output. The executor never renders TUI state.
Closing or blocking the TUI must not block a running foreground command, except
when the whole owned tmux session is deliberately killed.

### 2.2 No TUI-side shell interpolation, no `eval`

A command template uses explicit placeholders:

```text
{{WB_ROOT}} {{WB_DIR}} {{WB_FILE}} {{PARAM}}
```

The TUI replaces each placeholder with a `${value@Q}` shell-quoted literal.
No shell evaluation is performed and no variable environment is passed.

This keeps quoting honest and avoids double-evaluation bugs.

### 2.3 Explicit contracts

Only these values cross the boundary:

```text
literal command text          computed in the TUI
editor binary                 startup environment
```

Everything else stays inside its process.

### 2.4 Configuration is trusted Bash

`commands.conf`, `commands.user.conf`, `env.conf`, and machine env files are
sourced by Bash. They have the same trust level as `~/.bashrc`.

Do not parse them as data, sandbox them, or try to make them safe for
untrusted users. That is not the threat model.

### 2.5 Source files are not rewritten

`commands.conf` is a source file and is never rewritten by the TUI.
User additions live in `commands.user.conf`; hides live in
`commands.disabled`.

The TUI can be wrong or killed; it must not corrupt a user's hand-written
configuration.

### 2.6 Stable tmux target

The executor is found by the pane option:

```text
@lattice_role=executor
```

not by pane index and not by the currently focused pane. Splitting the
executor does not steal TUI commands. The original executor remains the
default target.

### 2.7 Fast common path

Normal command names and command bodies are ASCII. The renderer has an ASCII
fast path and a per-command row cache. CJK width is computed only when needed.

Do not add per-frame work to the normal scrolling path without measuring it.

---

## 3. Code map

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

Support library outside this directory:

```text
src/bashlib/str.sh             str_display_width, CJK/emoji width
```

`str.sh` prints a grammar probe when sourced. The launcher redirects its stdout
to `/dev/null`; otherwise the probe would corrupt the alternate screen.

---

## 4. Boot sequence

### 4.1 Normal launch

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

The TUI is started only after the split. Starting the TUI before the split
makes it cache the full-window width and render misaligned in a narrower pane.

### 4.2 Inside tmux

If `TMUX` is already set, the launcher runs the TUI in the current pane instead
of creating a session.

### 4.3 TUI startup

`lattice_app_main`:

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

`--owned` is passed only by the session launcher. A manually started `--tui`
inside a user session must not kill that session on exit.

### 4.4 Half-created sessions

If a session with the requested name exists but lacks either `tui` or
`executor`, it is killed and recreated. Never try to repair a half-built
session in place; the old blocked-split failure mode is worse.

---

## 5. tmux model

### 5.1 Pane roles

```text
@lattice_role=tui
@lattice_role=executor
```

Roles are set with:

```bash
tmux set-option -p -t PANE @lattice_role ROLE
```

New panes created by `split-window` do **not** inherit pane options. A
user-created split has no role and is not an executor target.

### 5.2 Target selection

`lattice_tmux_select_executor` scans panes in order and picks the first pane
with role `executor` or `primary`.

Consequences:

```text
split executor              -> original remains target
focus a split               -> target does not change
close original executor     -> no executor target; sends fail safely
mark a split as executor    -> it may become target, but it lacks rc setup
```

Do not auto-promote splits. A split shell started by tmux is not running the
executor rc.

### 5.3 Layout

Default split:

```bash
split-window -h -p 70
```

At TUI startup the width is re-applied from the actual window width:

```text
left  = window_width * 30 / 100
left >= 24 columns
right >= 24 columns
```

The detached session initially has a different width than the attached
terminal. Without the re-apply, the visual ratio drifts toward 40/60.

### 5.4 Sending commands

```bash
tmux load-buffer -
tmux paste-buffer -p -d -t TARGET
tmux send-keys -t TARGET Enter
```

`paste-buffer -p` uses bracketed paste, preserving quoting and special
characters. Do not use `send-keys -l` for arbitrary commands; tmux key-name
interpretation and shell multiline behavior become fragile.

### 5.5 Session safety

`Ctrl-b x` is guarded for `tui` and `executor`:

```text
Ctrl-b x on protected pane -> message, no close
Ctrl-b x on split          -> confirmation
```

`exit` in the executor shell still closes that pane. That cannot be
intercepted without replacing the user's shell behavior.

`Ctrl-b z` is zoom, not close, and asks for confirmation.

`Ctrl-b &` kills the whole window and is intentionally not guarded.

---

## 6. TUI runtime

### 6.1 Screen and raw mode

`lattice_screen_init`:

```text
alternate screen
hide cursor
enable mouse reporting (SGR)
enable bracketed paste
clear screen
save stty
raw-ish mode: -icanon -echo -icrnl
```

`lattice_screen_done` reverses all of it and restores `stty`.

The terminal is restored in EXIT/INT/TERM/HUP traps. A crash that bypasses
those traps can leave the terminal raw; that is the main reason cleanup is
centralized.

### 6.2 Event loop

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

There is no polling and no background reader.

Important consequences:

```text
executor output does not trigger TUI render
TUI idle CPU is effectively zero
TUI only redraws after a key/mouse event or WINCH
heavy executor output cannot back-pressure the TUI
```

### 6.3 Full-frame rendering

Each render builds `LATTICE_FRAME` and writes it once.

Why one write:

```text
many small writes make tmux/WinTerm visibly repaint between lines
```

Each line starts with `\033[0m`; selected rows add reverse and reset before
`\033[K`. Without per-line reset, terminal reverse state can bleed into the
next rows.

### 6.4 Enter and Ctrl-J

The terminal reports Enter and Ctrl-J as the same LF/empty byte. The reader
normalizes both to CR so Enter reliably executes. Ctrl-J is not a reliable
secondary action; use Ctrl-n/Ctrl-p/Ctrl-k in search and lists.

### 6.5 Mouse

SGR mouse sequences are parsed manually:

```text
button, x, y
wheel: b=64/65
motion: b & 32
press/release: low bits
double click: 900 ms row/mode timer
```

Mouse coordinate mapping uses the **current render offset**:

```text
row = LATTICE_CMD_OFFSET + y - 2
row = LATTICE_TREE_OFFSET + y - 2
row = history offset + y - 2
```

The recent panel occupies the bottom ten rows of the tree view. Left-click
selects, double-click reruns, and right-click previews the full command. The
panel is fully visible, so wheel events leave its selection alone. `Ctrl-r`
focuses it, `j/k` selects, Enter reruns, and `0`-`9` rerun the corresponding
row. In tree, command and history lists the wheel scrolls the viewport only;
the selected entry does not change, and a one-page list ignores the wheel. In
history mode left-click selects, double-click reruns, and `p` or right-click
previews the full command. A preview popup routes a click back to the mode that
opened it. Keyboard navigation clears the manual scroll flag and brings the
selection back into view.

### 6.6 Render modes

```text
tree      file tree + recent commands
commands  command list + one-line command preview
history   command history
help      key reference
```

Overlays:

```text
form      parameter/delete form
snapshot  floating snapshot content
```

`q` in tree is intentionally disabled; only Ctrl-g quits. This prevents a
single mistaken `q` from ending the whole workbench.

---

## 7. Command registry

### 7.1 Data model

The registry is parallel arrays:

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

There is no `x`/`xo` tree at runtime. The registry was migrated to flat arrays
for startup speed and simplicity.

### 7.2 Config format

```bash
lattice_command NAME SCOPE TARGET COMMAND [SNAPSHOT] [PARAMS...]
```

Everything after the snapshot is a parameter:

```bash
lattice_command 'grep in target' 'dir' 'pane' \
  'grep -nHE -- {{PATTERN}} {{TARGET_DIR}}' \
  '搜索指定目录' \
  'PATTERN' 'TARGET_DIR=.'
```

A command whose name begins with `@` is insert-only:

```bash
lattice_command '@ssh' 'dir' 'pane' 'ssh ' '打开 SSH 骨架'
```

The registry stores a `submit` mode. `run` means paste + Enter; `insert` means
paste only, then focus the executor. Insert-only commands are not written to
history. This is the supported escape hatch for interactive programs (SSH,
REPLs, prompts): the TUI delivers a skeleton and the user finishes it.

Each parameter is one separate argument. The default is everything after the
first `=`, kept verbatim. Spaces need config-level quoting; `B=$'a\tb'` can be
written directly and already arrives as a real tab. The form is single-line, so
real newlines are not suitable defaults.

Empty snapshot:

```bash
... '' 'PATTERN'
```

### 7.3 Load order

```text
commands.conf
commands.user.conf
minus commands.disabled
```

`commands.conf` is the frozen shipped example. The user's actual catalog is
normally on a USB stick and selected through `LATTICE_CONFIG`.

User names override base names intentionally. A duplicate within the same
layer is ignored and reported:

```text
lattice: duplicate command: name
loaded N commands; M duplicate(s) ignored
```

Lattice still starts. A malformed config should not make the workbench
unopenable.

### 7.4 Disabled list

`commands.disabled` is one command name per line. It hides a command without
rewriting the source file. To reuse a hidden name, remove it from this file.

### 7.5 Order

```text
command-order.tsv
```

contains names only. It is not written back to commands.conf.

```text
Ctrl-t      pin selected to top
Alt-↑/↓     move selected
```

Order is saved immediately. Names that no longer exist are pruned.

### 7.6 Search

`lattice_registry_build_hay` builds one lowercase haystack per command:

```text
name scope target command snapshot params
```

Search is multi-term. Each term becomes an ordered-subsequence glob:

```text
gst -> *g*s*t*
```

Bash's C-level `[[ $hay == $pattern ]]` does the matching. This is much faster
than calling an external grep per keystroke.

Case is ignored by lowercasing both haystack and query.

Opening search mirrors the query into the tmux status bar and turns the TUI
header into a dedicated `search>` line showing the query tail. The executor
pane stays visible. The status-right and status-right-length values are saved
before search and restored on exit; if the TUI exits unexpectedly, cleanup
restores them.

### 7.7 Duplicate policy

```text
user command same name as base -> user overrides base
duplicate in same file          -> first wins, later ignored + error
disabled name                   -> not loaded; remove disable first
```

### 7.8 UI

Command list rows show only:

```text
* / + marks, name, scope, target
```

The selected command body is shown in a one-line preview below the list.
Snapshots are not rendered in the list.

The row cache key is:

```text
raw command index : terminal columns
```

It is cleared on registry reset, reload, reorder, and width change. Without the
cache, 1000 Chinese snapshots made scrolling visibly slow.

### 7.9 Add/delete policy

There is no in-panel add form. Add commands with a text editor:

```text
commands.user.conf
```

`D` disables a selected command by appending its name to `commands.disabled`.
`R` reloads. This keeps input editing out of the TUI and avoids rewriting
hand-written Bash files.

---

## 8. Parameters and placeholders

### 8.1 Parameter lifecycle

```text
select parameterized command
-> form opens with defaults prefilled
-> Enter moves to next field
-> last Enter sends
```

Form keys:

```text
Tab       next field
Shift-Tab previous field
Ctrl-u    clear current field
Ctrl-d    restore default
Esc       cancel
```

Tab and Shift-Tab move between fields; they do not insert a literal tab. Use a
complete `$'...'` parameter such as `$'a\tb'` for literal tabs; it is validated
and previewed like any explicit ANSI-C value.

Required/optional convention:

```text
NAME          no default; currently accepted empty, but intended as required
NAME=default  default value
```

There is no separate type system and no complex interactive parameter support.
Complex interactive commands belong in the executor.

### 8.2 Placeholders

Command templates use:

```text
{{WB_ROOT}}
{{WB_DIR}}
{{WB_FILE}}
{{PARAM}}
```

`PARAM` is the parameter name declared in the sixth argument. There is no
`LP_` namespace and no exported parameter environment.

Names must match `[A-Za-z_][A-Za-z0-9_]*`, are case-sensitive, and must be
declared. `WB_ROOT/WB_DIR/WB_FILE/WB_CLIP/WB_A/WB_B/WB_C` are reserved and
cannot be parameter names. Unknown names abort dispatch. A placeholder may
appear multiple times; every occurrence gets the same value. Snapshot text is
display-only and is not expanded.

`[{NAME}]` is the raw form: the value is inserted verbatim without `@Q`, so it
can provide globs or shell brace syntax. It always forces preview insertion,
never auto-runs, and enters history as preview text. Values are not validated.
The parser accepts only a complete `[{NAME}]` token; other bracketed text, such
as JSON `[{"a":1}]`, remains literal.

### 8.3 Expansion and quoting

Before sending, `lattice_command_expand`:

```text
reads WB_ROOT / WB_DIR / WB_FILE from the tree
reads NAME=value pairs from the form
replaces each {{NAME}} with ${value@Q}
rejects unknown or unclosed placeholders
```

Values with spaces, quotes, `$`, backticks, or newlines become safe shell
literals. The command sent to the executor is the same literal stored in
history.

Placeholders must be outside quotes:

```bash
grep -- {{PATTERN}} {{WB_DIR}}      # correct
grep -- "{{PATTERN}}" {{WB_DIR}}    # invalid; @Q escaping changes
```

### 8.4 History

Every dispatched command is stored as its final literal text, including
parameter values. `history.tsv` therefore contains repeatable commands.

Insert-only `@` commands are not written. Commands forced into preview mode by
a **valid** `$'...'` parameter are written as the inserted text, before any
manual edit; replay uses that pre-edit text and the user owns the review.
Malformed `$'...'` attempts are not recorded.

History search is modal and incremental: `/` activates the filter, printable
keys update it without a blocking `read`, `Esc` leaves search and a second
`Esc` returns to the tree. This avoids the old blocking prompt that could look
stuck.

### 8.5 Explicit ANSI-C parameters

A parameter that is exactly one complete `$'...'` word is inserted verbatim.
Any other `$'`-prefixed value falls back to `@Q` quoting. Both cases force
`submit=insert`, so the user reviews and presses Enter.

The validator scans for an unescaped single quote and a trailing backslash:
it never evaluates the value. Raw Chinese/Unicode is accepted; only malformed
ASCII quoting falls back.

Commands containing legacy `$WB_*` or `$LP_*` syntax are rejected at dispatch
time. They must be migrated to placeholders.

### 8.6 Registers and clipboard

`WB_A/WB_B/WB_C` are raw files in `LATTICE_STATE_DIR`:

```text
wb-register-A
wb-register-B
wb-register-C
wb-clip
```

`wb-clip` stores only the ten-character preview, never the full clipboard.
Full clipboard content is read on demand into memory for `{{WB_CLIP}}`
expansion; it is not persisted by the cache writer. Registers intentionally
store their full values because the user explicitly placed them there.

- tree `@` then `a/b/c` writes the selected full path;
- `Ctrl-b a/b/c` reads the system clipboard into the register;
- `Ctrl-b v` refreshes only the `WB_CLIP` preview;
- commands referencing `{{WB_CLIP}}` read and cache the clipboard once.

The status-left worker reads the register files and renders
`DIR A B C CLIP FILE`. `CLIP` and the registers show the last ten characters
with a leading `...` when longer. Empty values are omitted. This keeps the TUI
render path free of clipboard calls and per-key file work. External clipboard
changes are intentionally not polled.

Clipboard reads use a 2-second inner timeout and a 3-second outer
`--kill-after=1` guard. Timeout/discard is a failure: partial temp data is
removed, caches/registers are not overwritten, and `{{WB_CLIP}}` commands are
not sent. A successful empty read is still a valid empty value.

`Ctrl-b c` overrides tmux new-window inside the Lattice session. The session
is single-window, so creating another window would produce an unmarked pane.

The executor gets no hidden context and no cleanup trap; it is a plain Bash
prompt plus the final command line.

Default limits:

```text
history entries  512
recent commands  10
```

`LATTICE_HISTORY_LIMIT` changes the history cap. Oldest entries are pruned in
batches: when the cap is exceeded, `LATTICE_HISTORY_TRIM_BATCH` entries are
dropped and the TSV is atomically rewritten once, instead of rewriting the
whole file after every command.

---

## 9. Executor shell

### 9.1 Startup

The right pane is started with:

```bash
LATTICE_EDITOR=...
exec bash --noprofile --rcfile executor/rc.sh -i
```

The rc sets only:

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

It parses a path and optional line, validates existence, and launches the
editor. The helper used by the TUI does the same for tmux copy-mode selections.

### 9.3 Opening selected text

Global tmux prefix binding:

```text
Ctrl-b e
```

runs `open-selection.sh` with the active pane's current directory and the last
tmux buffer. It handles:

```text
file:line  -> editor + line
directory  -> system file manager
bad path   -> message + buffer kept
```

Relative paths resolve against the active pane's cwd, not against a global
fixed root.

The tmux status-left line mirrors the live context instead of the session/window
label:

```text
DIR <WB_DIR>  FILE <WB_FILE>
```

`WB_FILE` is omitted for a directory selection. `lattice_status_left_start`
saves the original `status-left`, `status-left-length`, `status-format[0]`,
`set-titles` and `set-titles-string`, removes the single-window list, and sets
the outer title to `WB_ROOT`.

Status updates are written to a small temp file and applied by one background
worker. The TUI never runs a tmux `set-option` on selection movement; updating
`status-left` synchronously would add roughly 50 ms per key on MSYS2. The worker
coalesces rapid movement and applies only the latest text. Cleanup stops the
worker and restores all saved options.

### 9.3.1 Opening a mouse line without selection

`Alt+left-click` and `Ctrl+left-click` are bound in the tmux `root` table:

```text
M-MouseDown1Pane
C-MouseDown1Pane
```

They run `open-line.sh` with the full `#{mouse_line}` and the pane cwd. This is
possible only because the binding is a mouse event; tmux does not expose a
persistent hover position, and there is no supported `mouse_x`/`mouse_y`
column for a later keyboard binding.

The helper trims leading whitespace and ANSI escapes, scans whitespace
tokens from the start, and opens the first token that exists:

```text
file:line  -> editor + line
file       -> editor
directory  -> file manager
none       -> no action
```

The priority is per token. The scan is deliberately simple and deterministic;
a line with multiple existing paths uses the first one. The buffer-based
`Ctrl-b e` action is unchanged and remains the fallback for arbitrary
selections.

Alt is the primary modifier because Ctrl+click is often consumed by terminal
hyperlink handling; Ctrl is bound as a compatibility fallback. Plain click is
not used because it must keep selecting panes and dragging text.

### 9.4 Detaching the editor

`copy-pipe`/tmux command pipelines close stdio quickly. The helper launches the
editor with:

```bash
nohup setsid EDITOR ... </dev/null >/dev/null 2>&1 &
```

Without `</dev/null`, gvim can read EOF from the copy pipeline and exit.
Without process detachment, the GUI can be killed with the pipeline.

### 9.5 Clipboard

Mouse drag-release copies through:

```text
copy-selection.sh
```

Why not `copy-pipe-and-cancel "clip.exe"` directly: under MSYS2 tmux that path
was unreliable. The helper writes a temp file, sets the tmux buffer, and pipes
the file to `clip.exe`/`wl-copy`/`xclip`.

---

## 10. File tree

State:

```text
LATTICE_ENTRIES          filtered visible names
LATTICE_ENTRY_IS_DIR
LATTICE_TREE_SEARCH
LATTICE_TREE_FILTER
LATTICE_SHOW_HIDDEN
LATTICE_TREE_OFFSET
LATTICE_TREE_BODY
```

Keys:

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

The filter retains `..` and matches names only. It does not recursively search
file contents.

Scroll offset is preserved while the selection remains visible, same as the
command list.

---

## 11. Snapshot popup

Snapshots are display-only text from the fifth `lattice_command` argument.

```text
p            open
right-click  open
PgUp/PgDn    scroll
wheel        scroll
Esc/q/click  close
```

The popup contains only a border, the command body, and — if present — a blank
line followed by the snapshot. Do not add a title or footer; those were removed
because they were visual noise.

Long lines are wrapped with display-width accounting for CJK/emoji.

---

## 12. Environment and machine configuration

### 12.1 Machine id

The id is derived every run:

```text
Linux:   /etc/machine-id
Windows: MachineGuid via powershell.exe
fallback: HOSTNAME
```

It is **not cached in `LATTICE_STATE_DIR`**. That directory may be a USB stick
shared across machines; a cached id would be reused on every machine.

`LATTICE_MACHINE_ID` overrides it only for testing.

### 12.2 Env files

```text
$LATTICE_STATE_DIR/env.conf
$LATTICE_STATE_DIR/env.d/<machine-id>.conf
```

Common then machine-specific. Explicit environment variables win over both.

Precedence:

```text
explicit environment
> machine file
> common env.conf
> built-in defaults
```

Bootstrap variables (`LATTICE_ENV_CONF`, `LATTICE_ENV_DIR`,
`LATTICE_MACHINE_ID`) must be set in the process environment before startup if
they are to select which files load. Setting them inside the file they locate
is too late.

### 12.3 Portable layout

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

`LATTICE_STATE_DIR` and `LATTICE_CONFIG` must be passed explicitly by the
launcher. Do not point `LATTICE_CONFIG` back into the repository.

### 12.4 Editor defaults

```text
LATTICE_EDITOR   default gvim
LATTICE_OPEN_CMD default "$LATTICE_EDITOR --remote-silent"
```

Machine-specific absolute paths belong in the machine env file, not in the
repository.

---

## 13. Performance notes

Measured on the development machine (MSYS2/UCRT64, tmux):

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

History performance matters:

```text
history is capped at 512 entries by default
recent panel is capped at 10 unique commands, numbered 0-9
history rows are cached by command text and terminal width
```

The history row cache is capped at 512 entries; the tree row cache is capped
at 16384. A wheel event only changes the viewport offset; it does not rebuild
the view or move the selection.

Important optimization history:

* History rows are cached after `_lattice_fit`; without the cache a full
  history frame re-measured every visible command.
* History is trimmed in batches, not rewritten after every command once full.

* The first command-row cache removed repeated CJK width calculation.
* The command-row cache is capped at 4096 entries and cleared on width changes.
* `_lattice_fit` and `_lattice_pad` have ASCII fast paths.
* A duplicate-name scan was removed from every `lattice_command_add` call; it
  made 1000-command loading take 9.4 seconds. Do not reintroduce an O(N²) scan
  on the load path.

Do not optimize by skipping correctness:

* ASCII fast paths must fall back to display-width code for CJK.
* Per-row cache keys include terminal columns and are cleared on reorder/reload.

---

## 14. Trust and security model

Trusted:

```text
commands.conf
commands.user.conf
env.conf
env.d/*.conf
executor/rc.sh
```

These are Bash and can execute arbitrary code at source time.

Untrusted:

```text
parameter values typed into the form
paths from the file tree
tmux copy-mode selections
```

Parameter values are passed through environment variables and quoted by the
command author. Lattice never `eval`s a parameter value and never interpolates
it into a command string.

The editor and file-manager helpers validate existence before launching.
This is a usability check, not a sandbox.

---

## 15. Pitfalls already encountered

### 15.1 Starting the TUI before splitting

Makes the TUI cache the full window width and render wrongly in its pane.
Always split first, then respawn the TUI.

### 15.2 Splitting from inside the TUI

A blocked `split-window` client can freeze the whole workbench. A missing
executor is an error, never a reason to split from the TUI.

### 15.3 Closing the TUI or executor

`Ctrl-b x` is guarded for TUI/executor. A user can still type `exit` in the
executor or use `Ctrl-b &`. Recovering requires a fresh session; arbitrary
splits cannot be promoted because they lack the executor rc.

### 15.4 tmux pane options are not inherited

A split pane has no `@lattice_role`. It is a manual shell, not an executor.

### 15.5 Scroll offset must not be recomputed from selection

Recomputing `offset = selected - body + 1` on every frame makes a click on a
visible middle row jump the list. Preserve offset while selected is visible.

### 15.6 Terminal reverse bleeding

Every rendered line needs an explicit SGR reset. Otherwise reverse video from a
selected row can leak into following rows.

### 15.7 `str.sh` stdout pollution

Sourcing `str.sh` prints a grammar probe. Redirect stdout to `/dev/null` in the
launcher. Do not remove that redirect.

### 15.8 CJK width and per-frame cost

`str_display_width` is correct but expensive when called per character per row.
Its slow path skips ASCII runs and only enters codepoint width logic for
non-ASCII characters; no unbounded character cache is kept.
Use the ASCII fast path and the command-row cache. Snapshot text is
manually-triggered and may take the slow path.

### 15.9 `copy-pipe` to `clip.exe`

Unreliable under MSYS2 tmux. Use `show-buffer`/helper temp-file bridge instead.

### 15.10 gvim inheriting a pipe

A GUI editor launched from `copy-pipe` can read selection stdin and exit.
Redirect stdin from `/dev/null` and detach with `setsid`/`nohup`.

### 15.11 Placeholder quoting

Do not export parameter environments. Replace `{{NAME}}` with `${value@Q}` at
dispatch time; placeholders must be outside shell quotes.

### 15.12 Multi-line commands

There is no one-shot context to lose. A rendered multi-line command is a
single literal paste; every line sees the same values.

### 15.13 History

History stores the rendered literal command, including parameter values.
Insert-only `@` commands are not stored because Lattice never executes them.

### 15.14 Duplicate names

The user file may override a base command. Duplicates inside one layer are
ignored with stderr/status output, but startup continues. This is deliberate:
a typo should not make the workbench unopenable.

### 15.15 q became a footgun

`q` used to quit in tree mode. It is now disabled; only `Ctrl-g` quits. The
footer uses `^G`, not `G`.

### 15.16 Machine-id cache on USB

Never write a machine-id cache into `LATTICE_STATE_DIR`. It would select the
same machine file on every host.

### 15.17 `LATTICE_CONFIG` pointing into the repo

The repository config is a frozen example. Point the launcher at the USB/user
config instead.

---

## 16. Debugging checklist

### Syntax

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

### Config

```bash
LATTICE_STATE_DIR=/x/.lattice \
LATTICE_CONFIG=/x/.lattice/commands.conf \
./src/lattice_bash/lattice.sh --list-commands
```

### tmux state

```bash
tmux list-sessions
tmux list-panes -a -F '#{session_name} #{pane_index} #{pane_id} #{@lattice_role} #{pane_width}'
tmux show -g mouse
tmux list-keys -T prefix | grep -E ' e | x | z '
```

### Executor command

The executor is a plain Bash prompt. Inspect the command that was sent with:

```bash
history 1
```

There is no context file, DEBUG trap or parameter environment to inspect.

### TUI

There are intentionally no TUI test files in the repository while the UI is
still changing. Use temporary tmux sessions for manual testing:

```bash
tmux new-session -d -s t
tmux send-keys -t t '...lattice.sh --tui --no-tmux ...' Enter
tmux capture-pane -p -t t
```

---

## 17. Rejected designs and why

### File preview in the tree

Rejected: every cursor move caused file I/O and slowed navigation. The
workbench is for navigation and command dispatch, not reading files.

### `x`/`xo` runtime for commands

Rejected: loading a class tree for a flat command list was unnecessary startup
cost. Parallel arrays are faster and easier to inspect.

### In-panel add-command form

Removed: multi-field editing in a 30%-wide TUI was slow and error-prone. Use a
text editor and `R`.

### Legacy template variables

Rejected: `$WB_*` and `$LP_*` produce empty or stale shell values. Use
`{{...}}` placeholders; the renderer quotes them with `@Q`.

### Hard failure on duplicate names

Rejected: one typo would make the workbench unopenable. Skip/report and keep
running; fix and `R`.

### Rewriting `commands.conf` from the TUI

Rejected: would destroy comments/formatting and risk data loss. User additions
and hides are separate files.

### Draggable pane border

Rejected after real failures: tmux has no minimum pane width; dragging can
collapse the TUI and WINCH arrives after the pane is destroyed. Native tmux
resize bindings are safer.

### Snapshot title/footer

Removed: `snapshot: name` and `Esc/q close` were noise. The popup now shows
only content.

### Hard-coded user paths in the repository

Rejected: config must be portable. Machine paths live in `env.d/<machine>.conf`.

---

## 18. Future: SSH

Not implemented. This section is a design map, not a promise. The current
v1.0 loop intentionally stays local.

SSH support has three plausible shapes. They are not equally difficult.

### 18.1 Option A: remote-first (recommended first step)

Run Lattice entirely on the remote host; the local terminal only displays the
remote tmux session.

```text
local terminal
  └── ssh -t host
        └── remote tmux
              ├── Lattice TUI
              └── remote executor
```

The local command could eventually be:

```bash
lattice --ssh devbox:/home/me/project
```

or simply a wrapper:

```bash
ssh -t devbox 'cd /home/me/project && /path/to/lattice.sh'
```

Why this is the easiest:

```text
file tree, paths, executor and command transport all stay remote
no local/remote path mapping
no per-command SSH protocol
no remote file API
commands are fully rendered before transport
```

What still needs work:

```text
remote dependency check: bash >= 4.4, tmux, vim, grep/sed/find
remote deploy/update (git or rsync)
terminal editor integration
OSC52 clipboard
remote machine env.d profile
```

The editor is the main gap. The current `eg` / `open-selection.sh` paths launch
a GUI editor. On a headless remote host the practical choices are:

```text
terminal vim in a remote tmux pane/window
remote gvim over X11 (not available on Windows terminals)
local gvim via SSHFS or scp:// URLs
```

A terminal-vim mode would add a policy such as:

```text
LATTICE_OPEN_MODE=gui|terminal
```

and open `vim +LINE FILE` in a remote tmux window rather than launching gvim.
This is a new editor contract, not a one-line change.

Estimate for a remote-first MVP: roughly 0.5–1 day for launch/deps/tmux, plus
editor and clipboard work.

### 18.2 Option B: local TUI + remote executor

Local TUI renders; the right tmux pane is an SSH shell; commands are sent to
the remote shell.

```text
local tmux
├── local Lattice TUI
└── local pane running: ssh -tt host
```

This is attractive because local rendering remains responsive and the local
editor can stay gvim. It is much harder than remote-first.

The hard parts:

```text
remote file tree
local/remote path mapping
editor choice
SSH disconnect detection
clipboard
```

Do not open one SSH connection per command. Use a persistent control
connection:

```text
ControlMaster auto
ControlPersist yes
ServerAliveInterval ...
```

The rough backend shape would be:

```text
list_dir(path)
stat(path)
send_command(literal_text)
open_file(remote_path, line)
```

The local backend is today's implementation. An SSH backend must implement the
same interface. Do not add `if remote` branches to every tmux/tree function.

Commands are fully rendered before transport. A remote backend should receive
the same literal command text; no remote context file or prompt trap is needed.

The transport can still be local tmux `send-keys` into the SSH pane. That part
is reliable; the remote filesystem and path contracts are the hard part.

### 18.3 Option C: local TUI + local gvim + remote project

The hardest variant:

```text
remote file tree
local gvim editing remote files
remote executor
local/remote path mapping
```

A real implementation needs one of:

```text
SSHFS mount on the local machine
scp://host//absolute/path
rsync-based synchronization
```

Each introduces its own problems: Windows SSHFS reliability, save latency,
rename/delete semantics, path translation, and stale mounts. Do not start here.

### 18.4 Recommended evolution

```text
now:       local only; keep the current loop stable
step 1:    remote-first launcher + dependency check + remote tmux
step 2:    terminal-vim open mode + OSC52 clipboard
step 3:    only if needed: backend abstraction for local TUI + remote executor
step 4:    local gvim/SSHFS only after a proven file-system strategy
```

The first step should not touch the registry, placeholder rendering, literal
transport, or tmux roles. It should reuse them on the remote host.

### 18.5 Invariants for any SSH implementation

```text
No per-command SSH handshake.
No TUI-side interpolation of remote paths.
No eval of remote parameters.
No assumption that local paths equal remote paths.
No silent fallback to a local shell after SSH disconnect.
No direct split from the TUI.
```

A disconnected SSH pane must be detected explicitly and commands must fail with
a clear status, not be pasted into the wrong shell.

### 18.6 Why this is deferred

SSH touches the most expensive part of the current design: the boundary between
a trusted local filesystem and a remote shell. A half-done hybrid can look
correct while sending commands to the wrong path or opening the wrong file.

The current local loop is small and stable. SSH should be added as a separate
transport/back-end layer, not as scattered conditionals.

---

## 19. Change checklist

Before committing a structural change:

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

If a change affects one of these contracts, update this file first or alongside
the code:

```text
placeholder syntax
literal expansion and @Q quoting
tmux roles
command config format
environment precedence
history limits
```

---

## 20. Glossary

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

## 21. The shortest mental model

If you remember nothing else:

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
