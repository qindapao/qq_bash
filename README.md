
# qq_bash

A personal bash library

## Run tests

Enter the root directory of the project and directly execute the `test.sh` script.

## API

### trie

To simulate a prefix dictionary tree in `BASH`, it can be used as a nested array
or associative array. The function of the array has not been fully implemented
yet, and the following functions are provided.

- trie_init Initialize a tree
- trie_graft Hook one tree to another tree
- trie_inserts Insert tree leaf nodes in batches
- trie_insert Insert a tree leaf node
- trie_dump tree print
- trie_dump_flat Flat print of a tree
- trie_delete Delete a node and all its child nodes
- trie_get_subtree Get the subtree under a node
- trie_iter Tree single level iteration
- trie_walk Traverse a tree and can pass in a callback function
- trie_callback_print Default callback for trie_walk
- trie_id_rebuild Reconstructing a tree's ID, tree cleaning
- trie_equals Compare two trees for equality

#### trie_init
#### trie_insert
#### trie_inserts
#### trie_dump
#### trie_dump_flat
#### trie_delete
#### trie_get_subtree
#### trie_graft
#### trie_iter
#### trie_walk
#### trie_callback_print
#### trie_id_rebuild
#### trie_equals

