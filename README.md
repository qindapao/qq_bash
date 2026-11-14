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

- **5 weapon tiers** — `|` laser, `*` star, `@` at, `$` dollar; each tier's
  actual class is randomized per run from its own library.
- **Two Bosses** — the classic `Boss` (HP 150) and the spinning `BossSpinner`
  (HP 250) with four damage phases and rotating bullet patterns. At most two
  Bosses on screen.
- **Drops and words** — `H` heal, `b` bomb, `m` missile, `L` lane, `S` shield;
  type falling words for bonus score.
- **Minimal save** — score, HP, pickups, active weapon slot, and the run's
  weapon classes. Loading starts a fresh wave, not a frozen bullet pattern.
- **30 Hz logic / 60 Hz render** — fixed tick loop, raw terminal input, ANSI
  256-color output, no external runtime.

### Controls

| Key | Action |
|---|---|
| `W A S D` / `H J K L` | Move |
| — | Fire automatically |
| `SPACE` | Use a bomb (after picking up `b`) |
| `P` | Pause / resume |
| `Q` | Quit |
| `S` | Save while paused (hidden `.strafe_save`) |
| `L` | Load while paused, or from the title screen |

### Screenshot

<details>
<summary>Pure-text gameplay (80×24)</summary>

```text
┌─────────────────────────────────────────────────────────────────────────────────┐
│HP:3/20  SCORE:58440  W:@  BOMB:2/5  E:9/25  OBJ:116                             │
│BULLET |:1 *:2 @:3 $:4  DROP H:+3 b:BOMB m:MISSILE L:LANE S:SHIELD               │
│BONUS  |:  0  *:  0  @: 35  $:  0  M:  9  L:  0(1)  S:  0                        │
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
  then inherited methods.
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
    ├── Plane
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
