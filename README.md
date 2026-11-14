# qq_bash

**A pure-Bash toolkit — and a terminal bullet-hell built with it.**

`qq_bash` bundles a small standard-library of string/array helpers, a JSON-like
tree (`x`), an object system (`xo`), and **strafe_bash**: a playable ASCII
shooter that runs entirely in Bash. No Node, Python, or game engine.

```bash
./build.sh
./src/strafe_bash/strafe_bash.sh
```

Requires Bash 5+, a UTF-8 locale, and a 256-color terminal.

## What's inside

| Module | What it does |
|---|---|
| **`xo`** | Class templates, single inheritance, mixins, object pool, named objects, method dispatch |
| **`x`** | In-memory JSON-like tree: objects, arrays, null/bool, paths, DFS, JSON round-trip |
| **`strafe_bash`** | Terminal shooter: planes, enemies, two Bosses, weapons, drops, save/load |
| **`str` / `array` / `float` / `var`** | UTF-8-aware strings, arrays, numbers, indirection helpers |

## strafe_bash

A small but complete terminal shooter. Auto-fire is always on; the fun is in
positioning, weapon timing, and surviving the Bosses.

- **5 weapon tiers** — `|` laser, `#` star, `@` at, `$` dollar; each tier's
  actual class is randomized per run from its own library.
- **4 selectable planes** — balanced Bee, armored Hornet, fast Eagle-1, and the
  heavy Il-2; each has its own HP, score multiplier, bullet speed, and shield art.
- **Three Bosses** — the classic `Boss` (HP 150), the spinning `BossSpinner`
  (HP 250), and `SkullKing` (HP 500). SkullKing fires three homing 5×3 skull
  bullets, alternates between headless/armed forms, and sprays `O`/`X` bullets.
  Its spawn chance is about two-thirds that of each other Boss. At most two
  Bosses on screen.
- **Drops and words** — `H` heal, `b` bomb, `m` missile, `L` lane, `S` shield;
  touching a falling word collects it for score. `m` now launches a missile
  that automatically homes in on the nearest enemy. At five bombs, picking up
  another `b` immediately detonates the pickup without spending stock.
- **Hit sparks** — short-lived `*` marks show bullet impacts, shield absorbs,
  and player damage without spawning extra objects.
- **M_Blink mixin** — the player blinks for a short invulnerability window after
  taking damage; this exercises xo method injection and inheritance.
- **Il-2 multi-mixin** — `{MIX} => M_LongBlink M_Blink M_Ram`: Il-2 blinks for
  8 seconds (other planes 3 seconds), and while blinking its ramming collision
  deals 5 damage to an enemy, with a short cooldown.
- **Clear banner** — clearing all enemies when there were at least 5 at the
  start of the tick shows `ALL ENEMIES CLEARED  +1000`; killing a Boss shows
  `<BOSS NAME> WAS KILLED BY YOU!  +2000`. Either condition triggers the short
  FIGlet-style `EXCELLENT!` overlay. These bonuses are fixed and are not
  reduced by the Hornet score multiplier.
- **Minimal save** — score, HP, pickups, active weapon slot, the run's weapon
  classes, and the chosen plane. Loading starts a fresh wave.
- **30 Hz logic / 60 Hz render** — fixed tick loop, raw terminal input, ANSI
  256-color output, no external runtime.

### Choose your plane

| # | Plane | HP | Trait |
|---|---|---|---|
| 1 | Bee | 20 | Balanced; no penalty |
| 2 | Hornet | 30 | Armored; kills and words give 60% score |
| 3 | Eagle-1 | 15 | Non-laser bullets +1 speed; laser unaffected |
| 4 | Il-2 Sturmovik | 40 | Heavy armor; all bullets -1 speed |

Shield size follows the plane: a wider plane has a wider shield and clears
enemy bullets over a larger area. Damage without a shield is always the center
of the first row.

### Il-2 ramming build

Il-2 uses a three-entry Mixin list:

```text
{MIX} => M_LongBlink M_Blink M_Ram
```

- `M_LongBlink` overrides `blink_start` to 8 seconds.
- `M_Blink` supplies the normal blink tick/visibility methods; other planes
  use its 3-second default.
- `M_Ram` supplies the ramming ability: while Il-2 is blinking after a hit,
  colliding with an enemy deals 5 damage. The ram has a 10-tick cooldown and
  can kill enemies or a Boss through the normal score/death paths.

Practical use: take one hit to enter the 8-second angry state, then fly into
enemies. The invulnerability window matches the blink duration.

### Controls

| Key | Action |
|---|---|
| `1`–`4` | Choose a plane on the title screen |
| `W A S D` / `H J K L` | Move |
| `Y U` / `B N` | Move diagonally (up-left/up-right, down-left/down-right) |
| — | Fire automatically |
| `SPACE` / right click | Use a bomb (after picking up `b`) |
| `P` | Pause / resume |
| `Q` | Quit |
| `S` | Save while paused (hidden `.strafe_save`) |
| `L` | Load while paused, or from the title screen |

### Mouse support

Mouse control uses the terminal's xterm SGR mouse reporting, so it is
cell-based rather than pixel-based. Moving the mouse over the terminal moves
the plane; firing stays automatic.

- Mouse capture is always enabled while playing; there is no toggle. Terminal
  text selection is therefore unavailable until the game exits.
- Right-click uses a bomb. Mouse motion and left-click move the plane.
- The pointer is placed two cells below the plane's center, so it does not sit
  on top of the plane.
- Mouse events only arrive while the terminal window has OS focus and the
  pointer is inside it. Moving outside or clicking another window stops the
  events — the game cannot capture the pointer outside its terminal.
- The game periodically re-asserts mouse reporting to recover from terminals
  that silently drop it after focus changes.
- The input loop caps mouse events per iteration so a fast mouse cannot starve
  the game loop.
- `ESC[?25l` hides the text cursor while the game runs. A terminal application
  cannot portably hide the OS mouse pointer with ANSI; that is a terminal
  emulator preference (Windows Terminal / mintty mouse settings).
- If the terminal does not support SGR mouse reporting, the mouse is simply
  inactive and all keyboard controls still work.
- Mouse capture is disabled automatically on quit and GAME OVER.

### Screenshot

<details>
<summary>Pure-text gameplay (80×24)</summary>

```text
┌─────────────────────────────────────────────────────────────────────────────────┐
│HP:3/20  SCORE:58440  W:@  BOMB:2/5  E:9/25  OBJ:116                             │
│BULLET |:1 #:2 @:3 $:4  DROP H:+3 b:BOMB m:MISSILE L:LANE S:SHIELD               │
│BONUS  |:  0  #:  0  @: 35  $:  0  m:  9  L:  0(1)  S:  0                        │
│                                  ___                      _____                 │
│                                 | M |                    /     \                │
│                                 |___|                   /  O O  \               │
│                                 [10/10]                 \_|_|_|_/               │
│                                                          \_____/                │
│                                                       [124/150]                 │
│                                                                                 │
│                                                        ! 0 !                    │
│                                                                                 │
│                                                       ! 0 !                     │
│                                                                                 │
│                                   +                                             │
│                                   +            o|o         ! 0 !                │
│                                                -'-                              │
│                                                                                 │
│                                                                                 │
│                                   +            ! 0 !                            │
│                       All you need is love.    ! 0 !                            │
│   .                                                                             │
│                                  +                                              │
│                                                   ___                    ___    │
│                                                  | B |                  | B |   │
│                                        ! 0 !     |___|                  |___|   │
│                                                  [4/30]                         │
│                                                    +                            │
│          Q                                                                      │
│         [_]                                                                     │
│   .                                              ! 0 ! ! !                      │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

</details>

## The `xo` object system

`xo` gives Bash a small, pragmatic object model. Classes are declared as
templates, and every object is an associative array in `XO_OBJ_POOL`.

```bash
readonly EnemyStaticTemplate='
    EnemyObj ->
        {CLS} => Enemy
        {SUP} => Entity
        {MIX} =>
        {x} => 0
        {y} => 0
        {hp} => 1
'

Enemy_born () {
    local -n self=$1
    self["{x}$X"]=10
    self["{y}$X"]=5
}

Enemy_move () {
    local -n self=$1
    self["{y}$X"]=$(( ${self["{y}$X"]} + 1 ))
}

xo_init
xo_obj_born Enemy      # -> REPLY=OBJ_1
xo_call "$REPLY" move
```

Key ideas:

- **Templates** use `{CLS}`, `{SUP}`, `{MIX}` and arbitrary `{field}` entries.
- **Single inheritance** — a class gets its parent's fields and methods.
- **Mixins** — `{MIX}` lists method-only mixins; class methods win, then mixins,
  then inherited methods. The Il-2 list above is the worked example.
- **Named objects** — `xo_obj_born_named OBJ_plane Plane` for stable handles.
- **Object pool** — `XO_OBJ_POOL[OBJ_7]` stores the class; `xo_obj_kill` frees it.
- **Dispatch** — `xo_call "$obj" move`; specialise with `Enemy_move`,
  `Boss_move`, etc.
- **Type checks** — `Base_is_a "$obj" BossBase`.

The game's class tree:

```text
Base
├── BulletType ── BulletTypeDefault / Laser / Star / At / Dollar
└── Entity
    ├── Plane ── PlaneBee / PlaneHornet / PlaneEagle / PlaneIl2
    ├── Enemy ── EnemyQ / EnemyV / EnemyB / EnemyM
    ├── BossBase ── Boss / BossSpinner
    ├── Bullet
    ├── EnemyBullet ── BossBullet
    ├── Missile
    ├── Drop
    └── Word
```

This is what lets the game add a new enemy or Boss without a giant `case`
statement: class templates hold the data, methods hold the behaviour.

## The `x` tree

`x` is an in-memory tree with JSON semantics, implemented in pure Bash. It
supports objects, arrays, nulls, booleans, ordered children, and path access.

- `x_init [OBJ|ARR]` — create an empty tree
- `x_insert` / `x_delete` / `x_get_leaf` / `x_get_tree`
- `x_push_leaf` / `x_pop_leaf` / `x_shift_leaf` / `x_unshift_leaf`
- `x_walk` / `x_iter` / `x_to_flat_array` / `x_flat_to_tree`
- `x_to_json` / `x_from_json` / `x_dump` / `x_equals` / `x_graft`

Full parameters and return codes are documented in the function headers of
`src/bashlib/x.in`.

## Build and test

```bash
./build.sh        # generate .sh files from .in sources
./test.sh         # run the test suite
```

## Links

- Project: <https://github.com/qindapao/qq_bash>
- Author: **qindapao**
- GitHub: <https://github.com/qindapao>
- Blog: <https://qindapao.com>
- Email: <northisland2017@gmail.com>
