# DEVELOP — qq_bash internals

Development notes for `qq_bash`: what the project is for, how `xo` and `x` work,
the game's class tree, build/test flow, and the rules that keep the Bash version
frozen. Player-facing documentation lives in [README.md](README.md); project
conventions live in [CONSTITUTION.md](CONSTITUTION.md).

## Purpose and scope

`qq_bash` is primarily a validation project for the `xo` object system.
`strafe_bash` exists to prove that `xo` can model a real, stateful, interactive
application: named objects, inheritance, mixins, lifecycle, composition, and
method dispatch under a fixed game loop.

`xo` is **not a performance library**. Its intended home is the control plane
of Bash automation: build pipelines, industrial test harnesses, deployment
steps, test fixtures, and small DSLs. It trades a little memory and dispatch
overhead for nested data, inheritance, mixins, and readable composition. It is
not intended for high-throughput data processing, real-time engines, or
untrusted input.

## Bash version status

The Bash version of `strafe_bash` is **feature-frozen**. It is not receiving
new Bosses, weapons, mechanics, or systems. Remaining work is limited to:

- bug fixes
- balance tuning
- code cleanup and removal of code smells
- architectural cleanup, including moving responsibilities out of the main
  loop into the library/classes where they belong
- keeping `xo` reusable outside the game

The 30 FPS target is intentional. Bash/MSYS performance limits are accepted;
the game is a validation showcase, not a performance benchmark.

## Future

If the game is developed further, the likely path is a **Go rewrite**. The Bash
version would remain as a behavioral, numeric, and art reference. New gameplay
and higher performance targets belong in Go, not in this Bash codebase.

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
  then inherited methods. The Il-2 list below is the worked example.
- **Named objects** — `xo_obj_born_named OBJ_plane Plane` for stable handles.
- **Object pool** — `XO_OBJ_POOL[OBJ_7]` stores the class; `xo_obj_kill` frees it.
- **Dispatch** — `xo_call "$obj" move`; specialise with `Enemy_move`,
  `Boss_move`, etc.
- **Type checks** — `Base_is_a "$obj" BossBase`.

The game's class tree:

```text
Base
├── BulletType
│   ├── BulletTypeDefault
│   ├── BulletTypeLaser
│   ├── BulletTypeStar
│   ├── BulletTypeAt
│   └── BulletTypeDollar
└── Entity
    ├── Plane
    │   ├── PlaneBee
    │   ├── PlaneHornet
    │   ├── PlaneEagle
    │   └── PlaneIl2
    ├── Enemy
    │   ├── EnemyQ
    │   ├── EnemyV
    │   ├── EnemyB
    │   └── EnemyM
    ├── BossBase
    │   ├── Boss
    │   ├── BossSpinner
    │   └── SkullKing
    ├── Bullet
    ├── EnemyBullet
    │   └── BossBullet
    ├── Missile
    ├── Drop
    └── Word
```

Method-only mixins used by the plane classes:

```text
M_Blink
M_LongBlink
M_Ram
```

This is what lets the game add a new enemy or Boss without a giant `case`
statement: class templates hold the data, methods hold the behaviour.

### Il-2 mixin stack

Il-2 uses a three-entry Mixin list:

```text
{MIX} => M_LongBlink M_Blink M_Ram
```

- `M_LongBlink` overrides `blink_start` to 4 seconds.
- `M_Blink` supplies the normal blink tick/visibility methods; other planes
  use its 3-second default.
- `M_Ram` supplies the ramming ability: while Il-2 is blinking after a hit,
  colliding with an enemy deals 5 damage. The ram has a 10-tick cooldown and
  can kill enemies or a Boss through the normal score/death paths.

Player-facing summary of the same build: take one hit to enter the 4-second
angry state, then fly into enemies. The invulnerability window matches the
blink duration.

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

`build.sh` compiles the `#@if` blocks in `src/bashlib/*.in` (and
`test/bashlib/test_x.in`) into the `.sh` files that the game and tests source.
The generated `.sh` files are not tracked by git; run `./build.sh` after a fresh
clone or a clean, and `./build.sh -d` to remove them again.

## Rendering notes

Everything the game draws is appended to one buffer (`FRAME_BUF`) and flushed
once per frame; nothing in the render path writes to the terminal directly.
That keeps two properties that later fixes depend on:

- **Frames are atomic.** `frame_flush` wraps the whole buffer in `DECSET 2026`
  (synchronized output), so the terminal composes one frame instead of showing
  the intermediate "erase old position, then draw new one" state.
- **One write per frame.** The flush is a single `printf`; adding per-frame
  work here costs frames, so keep it to one call.

Draw order in the render pass is: erase previous positions, draw bullets,
missiles, enemy bullets, enemies, drops and words, then the player last, so
nothing can cover the plane. The player's own erase is skipped while it is
stationary and its art shape is unchanged, because that frame redraws the same
cells anyway.
