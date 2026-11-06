
# qq_bash

A personal Bash library.

It bundles a set of everyday string and array helpers, plus a
hand-rolled tree structure that implements full JSON semantics
(pure Bash, no external runtime).

## What's inside

- **String helpers** (`str.in`) — char-level length/slice (UTF-8 aware),
  splitting, cutting, counting, byte-width measurement, and JSON-style
  escaping that preserves real newlines while neutralizing C0/C1 controls.
- **Array helpers** (`array.in`) — sorting, searching, indexing, and
  associative-array key/value serialization.
- **`x` tree** (`x.in`) — an in-memory tree that models JSON exactly:
  objects, arrays, nulls, booleans, nested structures, ordered children,
  and path-based access. Includes insert/delete/get, array push/pop/shift/unshift,
  DFS walking, flattening, id rebuilding, equality checking, subtree grafting,
  and lossless JSON round-tripping via `x_to_json` / `x_from_json`.

## Run tests

Enter the root directory of the project and directly execute the `test.sh` script.

## Define the variables within a function that need to be passed to a sub-function for processing.

Since subfunctions require the use of `local -n` references to variables, a naming convention—designed to avoid name collisions—involves prefixing these variables with the current function name (formatted in PascalCase). For example:

```bash
test_func1 ()
{
	local TestFunc1_var1=
	test_func2 TestFunc1_var1
	echo "long1: $TestFunc1_var1"
	local -n short=TestFunc1_var1
	echo "short1: $short"
}

test_func2 ()
{
	local -n get_var=$1
	get_var="a tring 2"
	local TestFunc2_var1=
	test_func3 TestFunc2_var1
	echo "long2: $TestFunc2_var1"
}

test_func3 ()
{
	local -n get_var=$1
	get_var="a tring 3"
}

test_func1
```

Other types of variables within a function are not subject to this constraint and may use very short, lowercase names.

## API Overview

Full documentation is in the function header comments of `x.in`. Below is a quick index.

### Tree Lifecycle
- `x_init [OBJ|ARR]` — Create an empty tree
- `x_delete tree key` — Delete a node (and subtree). Empty key resets the tree.
- `x_id_rebuild tree` — Compact node IDs

### Insert
- `x_insert tree key value` — Core insert, auto-creates path
- `x_insert_dict` / `x_insert_token_dict` — Fast paths (no return)
- `x_qinserts` / `x_inserts` — Batch insert
- `x_push_leaf_fast` — Fast array append

### Read
- `x_get_leaf` / `x_get_tree` — Get leaf value or subtree
- `x_iter` — Iterate one level
- `x_walk` — DFS walk with callback

### Array Ops
- `x_push_leaf` / `x_push_tree` / `x_unshift_leaf` / `x_unshift_tree`
- `x_pop_leaf` / `x_pop_tree` / `x_shift_leaf` / `x_shift_tree`

### Flat
- `x_to_flat_array` / `x_to_flat_assoc` — Flatten a node
- `x_flat_to_tree` — Write flat structure as subtree
- `x_push_flat` / `x_unshift_flat` — Push/unshift a flat structure to an array
- `x_pop_to_flat_array` / `x_pop_to_flat_assoc` — Pop and flatten
- `x_shift_to_flat_array` / `x_shift_to_flat_assoc` — Shift and flatten`

### JSON
- `x_to_json` / `x_from_json` — Serialize / Deserialize

### Utilities
- `x_dump` — Debug print
- `x_equals` — Compare two trees
- `x_graft` — Attach a subtree

Full parameters, return codes (`X_RET_ENUM_*`), and side effects are documented in each function's header comment.


