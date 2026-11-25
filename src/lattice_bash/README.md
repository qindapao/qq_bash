# lattice_bash

A pure-Bash TUI workbench for tmux. Browse files and dispatch configured quick
commands into a dedicated executor pane without leaving the workbench.

## Layout

```text
┌──────────────────────────┬────────────────────┐
│ Lattice TUI              │ executor shell     │
│ file tree                │ command output     │
└──────────────────────────┴────────────────────┘
```

The TUI is the left pane; commands are pasted into the right pane. The executor
is discovered by the tmux pane option `@lattice_role=executor`, not by pane
index. `auto`/`pane` targets currently resolve to that executor.

## Quick start

```bash
cd /path/to/qq_bash
./src/lattice_bash/lattice.sh --root "$PWD"
```

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
Enter        enter directory / run selected command
h            parent directory
Backspace    parent directory
r            refresh
.            toggle hidden files
:            quick command palette
/            filter file/dir names in tree; search commands in palette
H            history
Ctrl-r       focus recent commands (then 1/2/3 or Enter)
/            search history (in history mode)
R            reload commands.conf
?            help
q / Ctrl-g   quit and close the Lattice session
```

## Configuration

`config/commands.conf` is trusted Bash configuration:

```bash
lattice_command 'git status' 'dir'  'pane' 'GIT_TERMINAL_PROMPT=0 git -C "$WB_DIR" status --short --branch'
lattice_command 'git check all' 'dir' 'pane' 'GIT_TERMINAL_PROMPT=0 timeout 60 git_check_status.sh -o "$WB_DIR"'
lattice_command 'git diff'   'file' 'pane' 'git diff -- "$WB_FILE"'
```

There are no command shortcut keys. Open the `:` palette, use `j/k` or arrows
to select, press `/` to enter search and type to filter, and press Enter to
send; the palette stays open after dispatch. Esc leaves search (clearing the
query), then Esc leaves the palette.
`scope` is informational in 0.1. `target` is the transport policy
(`pane`, `auto`, `pane:<id>`, …). A command receives:

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
`Ctrl-r` focuses it, `j/k` selects and Enter reruns. While focused, `1`, `2`,
`3` rerun the corresponding recent command. Numeric keys do nothing in tree
mode.

## History

Only commands dispatched by Lattice are recorded, in:

```text
~/.lattice/history.tsv
```

Commands run directly in another shell are not captured. History entries can
be searched with `/` and re-run with Enter.

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
```

For mouse selection and wheel scrolling:

```bash
tmux set -g mouse on
```

For tmux copy mode to place text on the system clipboard (terminal must
support OSC 52):

```bash
tmux set -g set-clipboard on
```

In Windows Terminal, `Shift+drag` usually selects text without tmux
intercepting the mouse.

## Architecture

```text
app/state.sh       state, paths, terminal sizing
fs/tree.sh         directory listing and navigation
cmd/registry.sh    x tree command registry + commands.conf loader
cmd/history.sh     xo data-tree history + TSV persistence
cmd/tmux.sh        pane discovery/sending
cmd/executor.sh    target resolution and context injection
ui/render.sh       ANSI renderer
ui/event.sh        key loop
```

The command registry is an `x` tree; command history uses the `xo` dataclass
layer. `lattice.sh` creates the tmux session and starts the TUI.

## Status

0.1 is a runnable framework: file tree, quick commands, tmux sending, history,
reload, and help. File preview was removed because it made navigation too slow. Editing, git UI, and structured output capture are
intentionally out of scope.
