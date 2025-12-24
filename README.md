
# qq_bash

一个个人的 bash 库

## 运行测试

进入项目的根目录下直接执行 `test.sh` 脚本即可。

## API

### trie

bash 中模拟的前缀字典树，提供了下列函数。

- trie_init 初始化一颗树
- trie_graft 把一棵树挂接到另外一颗树上
- trie_inserts 批量插入树根节点
- trie_insert 插入一个树根节点
- trie_dump 树状打印一棵树
- trie_dump_flat 扁平打印一棵树
- trie_delete 删除一个节点和它的所有子节点
- trie_get_subtree 获取一个节点下的子树
- trie_iter 树单层迭代
- trie_walk 遍历一棵树，并且可以传入回调函数
- trie_callback_print trie_walk 的默认回调
- trie_id_rebuild 重建一棵树的ID，树清洗
- trie_equals 比较两颗树是否相等

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

