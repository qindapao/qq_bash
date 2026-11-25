declare -gA _BASHLIB_IMPORTED
((_BASHLIB_IMPORTED[x]++)) && return 0

# X 是全局保留分隔符。首次 source 时如果调用方已经定义 X，直接拒绝加载。
# 这是致命错误：source 方必须检查返回值并终止，不允许重试半加载的模块。
# X 故意不是 readonly，便于测试在子 shell 中临时覆盖。
if [[ -n "${X+x}" ]] ; then
    printf 'x.sh: X is already defined; refuse to override it\n' >&2
    return 1
fi

. "${BASH_SOURCE[0]%/*}/grammar.sh"
. "${BASH_SOURCE[0]%/*}/array.sh"
. "${BASH_SOURCE[0]%/*}/var.sh"
. "${BASH_SOURCE[0]%/*}/str.sh"

# ================================================================================
# Importantly, if you want to save x data, there are two recommended ways:
#
#   1. Serialize it into JSON standard format (x_to_json in xj.sh), and convert
#      the JSON back into x (x_from_json in xj.sh) before use. x.sh itself is
#      JSON-free; source xj.sh when you need the JSON layer.
#
#   Extension APIs (graft, leaf/tree push/pop/shift, flat/layer conversion,
#   x_equals, ...) live in xe.sh. x.sh must not depend on xe.sh or xj.sh.
#
#   2. Use the native dump format: dump the tree (which yields a stable,
#      human-readable text representation), and rebuild the tree from that
#      dump with x_rebuild_from_dump before use.
#
# Both of the above rely only on stable, documented formats, so they keep
# working even if the internal implementation of the tree changes.
#
# Do NOT save a tree by `declare -p tree` to a file and restore it via the
# `source` method. That depends on the internal implementation details of
# the tree; if those details change, restoring will fail.
#
# All variable names in the library start with tr_.
# Be careful to avoid external variables.
# tr_
#
# ================================================================================
# MSYS2 / Git Bash limitation: CR (0x0D) in x keys is unsupported.
#
# MSYS2's Bash strips raw CR when an assignment string is re-parsed, e.g.
#     local -A "map=($REPLY)"
#     eval "map=($REPLY)"
# A CR inside a key is silently lost. The same test on native Linux
# Bash keeps CR intact. This is an MSYS2 Bash/platform quirk, not an x-tree
# design rule.
#
# Values are stored and returned as raw strings, and @Q token lists encode
# CR as an escaped form; value paths covered by test_msys2_cr.sh preserve
# CR on MSYS2. Do not put raw CR into x keys on Windows/MSYS2. If you must
# transport a CR-containing key, encode it in your own layer and decode
# after the shell parser has finished. Linux/Bash has no such limitation.
# ================================================================================
#================================================================================

#-------------------------------------------------------------------------------

# If you want more powerful anti-collision capabilities, you can set it as follows
# But usually $'\034' is enough.
# Be careful not to change this value casually, as it may affect the re-import of the variable.
# The semantics will change after importing
# X 当前是单字符：切分器优先走 IFS word splitting。
# 多字符分隔符保留逐段慢路径；未来优化方向是：先把分隔符替换成数据中不存在的
# 单字符哨兵，再复用 IFS word splitting，避免逐段 %%/# 的 O(N²) 写法。
# WARNING: X 是全局分隔符契约；不要在树/常量创建后修改它。
# 非 readonly 只是为了测试可在子 shell 中临时覆盖。
X=$'\034'
readonly X_ROOT_ID=1

readonly X_RET_ENUM_OK=0

readonly X_RET_ENUM_KEY_IS_TREE=1
readonly X_RET_ENUM_KEY_IS_LEAF=2
readonly X_RET_ENUM_KEY_IS_NOTFOUND=3
readonly X_RET_ENUM_KEY_IS_INVALID=4
readonly X_RET_ENUM_KEY_OUT_OF_INDEX=5
readonly X_RET_ENUM_KEY_IS_NOT_LEAF=6
readonly X_RET_ENUM_KEY_IS_NULL=7
readonly X_RET_ENUM_KEY_UP_LEV_TYPE_MISMATCH=8
readonly X_RET_ENUM_KEY_CHILD_CNT_IS_ZERO=9

readonly X_RET_ENUM_TREE_IS_INVALID=50
readonly X_RET_ENUM_TREE_IS_EMPTY=51
readonly X_RET_ENUM_TREE_NOT_HAVE_ROOT=52
readonly X_RET_ENUM_TREE_IS_NOT_SAME=53

# type field (dedicated to container identification)
readonly X_TYPE_OBJ=1
readonly X_TYPE_ARR=2

# Node type (walk-specific)
readonly X_NODE_KIND_OBJ=1
readonly X_NODE_KIND_ARR=2
readonly X_NODE_KIND_OBJ_EMPTY=3
readonly X_NODE_KIND_ARR_EMPTY=4
readonly X_NODE_KIND_LEAF=5
readonly X_NODE_KIND_LEAF_NULL=6
readonly X_NODE_KIND_UNKNOWN=7

# Value types (only for writing and printing)
readonly X_VALUE_NULL="null$X"
readonly X_VALUE_TRUE="true$X"
readonly X_VALUE_FALSE="false$X"
readonly X_VALUE_NULL_OBJ="{}$X"
readonly X_VALUE_NULL_ARR="[]$X"

#-------------------------------------------------------------------------------
_split_tokens_fast ()
{
    if ((${#X}==1)) ; then
        local -n w_tokens=$1
        local - IFS=$X
        set -f ; w_tokens=($2)
        return 0
    fi
    _split_tokens "$@"
}

#-------------------------------------------------------------------------------

# 拆分 "$X" 分隔的 token 串为数组，校验每个 token 是否合法（'{k}'/'[i]'/'()'/'<>'）。
# 单 token 直接写入；多 token 用 word splitting 切分；多字符分隔符走慢路径。
# @in  $1=输出数组变量名  $2=token 串  $3=插入语义标志(1=允许 '()' 主键)
# @out $1=token 数组
# @ret 0=OK  4=X_RET_ENUM_KEY_IS_INVALID
_split_tokens ()
{
    local -n w_tokens=$1 ; w_tokens=()
    local is_insertion_semantics=${3:-0} token

    [[ -n "$2" ]] || return $X_RET_ENUM_OK

    # 非空 token 串必须带尾部分隔符；`*"$X"` 是“以 X 结尾”，不是“包含 X”。
    if [[ "$2" != *"$X" ]] ; then
        return $X_RET_ENUM_KEY_IS_INVALID
    fi

    if ((${#X}==1)) ; then
        # 单 token 不走数组 word splitting，避免 set -f/local IFS 的固定开销。
        local body=${2%"$X"}
        if [[ "$body" != *"$X"* ]] ; then
            w_tokens=("$body")
        else
            _split_tokens_fast "$1" "$2" || return $?
        fi
    else
        # 多字符分隔符：保留逐段提取的扩展路径。
        # 用 -n 做 O(1) 判空；正常有尾部分隔符时一定会逐步缩短。
        # 优化方向：把 X 替换成数据中不存在的单字符哨兵，再走 word splitting。
        local tokens_str=$2
        while [[ -n "$tokens_str" ]] ; do
            token=${tokens_str%%"$X"*}
            w_tokens+=("$token")
            tokens_str="${tokens_str#*"$X"}"
        done
    fi

    for token in "${w_tokens[@]}" ; do
        ((${#token}<=2)) && return $X_RET_ENUM_KEY_IS_INVALID
        case "${token:0:1}${token: -1}" in
        '()')
            # Must have insertion semantics and must be a positive integer
            ((is_insertion_semantics)) || {
                die ERR "now are not in insertion semantics. key:${2@Q} is invalid!"
                return $X_RET_ENUM_KEY_IS_INVALID
            }
            str_is_decimal_positive_int "${token:1:-1}" || {
                die ERR "key:${2@Q} is invalid!"
                return $X_RET_ENUM_KEY_IS_INVALID
            }
            ;;
        '[]')
            str_is_decimal_int "${token:1:-1}" || {
                die ERR "key:${2@Q} is invalid!"
                return $X_RET_ENUM_KEY_IS_INVALID
            }
            ;;
        '{}'|'<>')  : ;;
        *)  die ERR "key:${2@Q} is invalid!"
            return $X_RET_ENUM_KEY_IS_INVALID
            ;;
        esac
    done

    return $X_RET_ENUM_OK
}

#-------------------------------------------------------------------------------

# index -> physical
#
# 索引 token 转物理 token（如 '[0]' -> '<n>'）。
# @in  $1=树名  $2=token  $3=父节点 ID
# @out REPLY=物理 token
# @ret 0=OK  5=X_RET_ENUM_KEY_OUT_OF_INDEX
tr_resolve_index_token ()
{
    REPLY=
    local -n tr_t=$1
    local tr_token=$2 tr_node=$3
    if [[ "${tr_token:0:1}${tr_token: -1}" == '[]' ]] ; then
        local -a "tr_child_ids=(${tr_t[$tr_node.s]})"
        _negative_token_to_positive "$tr_token" "${#tr_child_ids[@]}" "$tr_node" || {
            return $?
        }
        tr_token=${tr_child_ids[${REPLY:1:-1}]} REPLY=
    fi
    REPLY="$tr_token"
}

#-------------------------------------------------------------------------------

# physical -> index
#
# 物理 token 转索引 token（如 '<n>' -> '[i]'）。
# @in  $1=树名  $2=token  $3=父节点 ID
# @out REPLY=索引 token
# @ret 0=OK  4=X_RET_ENUM_KEY_IS_INVALID
tr_resolve_physical_token ()
{
    REPLY=
    local -n tr_t=$1
    local tr_token=$2
    # local tr_node=$3

    if [[ "${tr_token:0:1}${tr_token: -1}" == '<>' ]] ; then
        local -a "tr_child_ids=(${tr_t[$3.s]})"

        array_index "${tr_token}" ${tr_child_ids[@]} ; local -i tr_index=$REPLY

        ((tr_index==-1)) && {
            die ERR "node:$3(token:${tr_token@Q}) can not find index."
            return $X_RET_ENUM_KEY_IS_INVALID
        }
        tr_token="[$tr_index]"
    fi
    REPLY="$tr_token"
}

#-------------------------------------------------------------------------------

# Convert negative index of array to positive index
# a=(1 2 3 4) index=-1 -> index=3
#                         index=(($len+index))
# 负索引归一化：'[-1]' -> '[(len-1)]'。
# @in  $1=token  $2=数组长度  $3=父节点 ID
# @out REPLY=归一化后的 token
# @ret 0=OK  5=X_RET_ENUM_KEY_OUT_OF_INDEX
_negative_token_to_positive ()
{
    REPLY=
    # local tr_token=$1 tr_array_len=$2 tr_node=$3
    local -i tr_token_abs=${1:1:-1}
    if ((${1:1:-1}<0)) ; then
        ((tr_token_abs=-tr_token_abs))
        ((tr_token_abs>$2)) && {
            die ERR "node:$3(token:${1@Q}) index:${1:1:-1} is out of index."
            return $X_RET_ENUM_KEY_OUT_OF_INDEX
        }
        ((tr_token_abs=$2-tr_token_abs))
        REPLY="${1:0:1}$tr_token_abs${1: -1}"
    else
        REPLY="$1"
    fi
    return $X_RET_ENUM_OK
}

#-------------------------------------------------------------------------------

# children -> s
# child    -> c
# key      -> k
# type     -> t
# 初始化一棵空树，直接写入调用方关联数组。
# @in  $1=树保存到的关联数组名（调用方先声明 local -A / declare -gA）
#      $2=根类型（X_TYPE_OBJ=1 或 X_TYPE_ARR=2，默认 OBJ）
# @out $1=新树（关联数组 KV 格式，含根节点和 max_index=2）
# @ret 0
x_init ()
{
    local -n w_x=$1
    w_x=(
        [$X_ROOT_ID.t]=${2:-$X_TYPE_OBJ}
        [max_index]=2
    )
}

#-------------------------------------------------------------------------------

# Verify whether the subtree is a basic x
#
# 校验子树是否合法（关联数组、非空、有根节点）。
# @in  $1=树名
# @ret 0=OK  50=X_RET_ENUM_TREE_IS_INVALID  51=TREE_IS_EMPTY  52=TREE_NOT_HAVE_ROOT
_x_tree_is_valid ()
{
    local -n tr_tree=$1

    [[ "${tr_tree@a}" != *A* ]] && {
        die ERR "invalid tree: $1 is not an associative array!"
        return ${X_RET_ENUM_TREE_IS_INVALID}
    }

    ((${#tr_tree[@]})) || {
        die ERR "invalid tree: $1 is empty!"
        return ${X_RET_ENUM_TREE_IS_EMPTY}
    }

    [[ ${tr_tree[$X_ROOT_ID.t]+_} ]] || {
        die ERR "invalid tree: $1 not have root node!"
        return ${X_RET_ENUM_TREE_NOT_HAVE_ROOT}
    }

    return ${X_RET_ENUM_OK}
}

#-------------------------------------------------------------------------------

# 将 '()' 主键语义转为 '[]' 索引语义（用于 x_qinserts 的前缀归一化）。
# @in  $1=token 串
# @out REPLY=转换后的 token 串
# @ret 0
_tokens_insert_to_overwrite ()
{
    REPLY=
    local tokens_str=$1
    [[ -z "$tokens_str" ]] && return $X_RET_ENUM_OK
    local -a tokens=()
    local token
    while [[ -n "$tokens_str" ]] ; do
        token=${tokens_str%%"$X"*}
        [[ "${token:0:1}" == '(' ]] && token="[${token:1:-1}]"
        tokens+=("$token")
        tokens_str="${tokens_str#*"$X"}"
    done
    printf -v REPLY "%s$X" "${tokens[@]}"
    return $X_RET_ENUM_OK
}

#-------------------------------------------------------------------------------

# 校验物理键格式：非空、不以 $X 开头、不含连续的 $X、必须含 $X。
# @in  $1=物理键字符串
# @ret 0=OK  7=X_RET_ENUM_KEY_IS_NULL
x_key_is_invalid ()
{
    if [[ "$1" == "$X"* ]] ||
        [[ "$1" == *"$X$X"* ]] ||
        [[ "$1" == "$X" ]] ||
        [[ "$1" != *"$X" ]] ; then
        die ERR "key:${1@Q} is null or invalid!"
        return $X_RET_ENUM_KEY_IS_NULL
    else
        return $X_RET_ENUM_OK
    fi
}

#-------------------------------------------------------------------------------
# x_qinserts — 批量带公共前缀插入多个叶
#
# 用途：所有叶子共享同一段前缀（如 {Base}$X{Device}$X），
#       一次性把它们的 KV 挂上去。
#
# 【加速原理（黑盒，但对调用方可见）】
#   第一个 KV 走完整路径 x_insert（从根找），拿到 node_id 和 physical_full_key；
#   后续 N-1 个 KV 直接拿这两个参数喂给 x_insert，跳过从根找的开销。
#   调用方无需操心，函数内部自动完成。
#
# 【返回模式（$2）】
#   leaves:<数组>  — 每个叶子的 "node_id physical_key" 元组全部写入数组
#   common:<数组>  — 只把公共前缀节点的 "node_id physical_key" 写入数组
#                    适合后续用这个前缀继续批量写
#   数组由调用方先声明 local -a；函数直接写，不再用 REPLY。
#
# 【Windows/MSYS2 坑：声明复合赋值会吞 \r】
#   不是 "$@" 的语义问题，也不是 Windows 命令行转换；是 local/declare
#   “声明 + 复合数组赋值”路径会吞掉 \r：
#       local -a a=("$@")       # CR 丢失
#   本函数保持“先声明、后赋值”：
#       local -a a
#       a=("$@")                # CR 保留
#   不要改回一行式复合赋值。
#
# 用法：
#   local -a w_x_caller__rows=()   # 前缀用调用方自己的函数名
#   x_qinserts t1 leaves:w_x_caller__rows "{prefix1}$X{prefix2}$X" \
#       "[0]$X" "array_value1" \
#       "[1]$X" "array_value2" \
#       "[2]$X" "array_value3"
#
# 【约束】
#   只有 $3 公共前缀允许出现 '()' 插入语义（第一次插入需要它）。
#   $4.. 的配对 key 不得含 '()'：本函数不拦截，x_insert 会把它当数组插入
#   语义处理，结果不可预期。
#
# @in  $1=树名  $2=<leaves|common>:输出数组名
#      $3=公共前缀 token 串（可含 '()' 插入语义）
#      $4..=成对的 {key value}；key 不得含 '()' 插入语义
#      单值模式：$4 直接写到 $3；如果 $4 是空容器 sentinel，按 x_insert 的
#      叶子覆盖语义处理（普通标量会被覆盖成空容器）。
# @out $2 冒号后的数组=按模式写入的 "node_id physical_key ..." 列表
# @ret 0=OK  其他=透传 x_insert 的返回码
#-------------------------------------------------------------------------------
x_qinserts ()
{
    # local - ; set +x
    # $2 = leaves:<输出数组名> / common:<输出数组名>
    local tr_t_name=$1 tr_return_spec=$2 tr_common_prefix=$3
    shift 3

    local tr_return_mode=${tr_return_spec%%:*}
    local tr_var=${tr_return_spec#*:}
    [[ -n "$tr_var" ]] || {
        die ERR "x_qinserts: return spec must be <leaves|common>:<array>"
        return $X_RET_ENUM_KEY_IS_INVALID
    }
    local -n tr_w_out=$tr_var
    tr_w_out=()

    # MSYS2/Bash 坑：声明命令里的复合数组赋值会吞掉 \r：
    #     local -a a=("$@")       # CR 丢失
    # 分开声明和赋值就正常：
    #     local -a a
    #     a=("$@")                # CR 保留
    # 这不是 "$@" 的语义问题，也不是 Windows 命令行转换；是 local/declare
    # 复合赋值路径的 CR 处理问题。下面保持“先声明、后赋值”。
    local -a tr_insert_kv ; tr_insert_kv=("$@")

    # If the number of parameters is 1, it means only writing a single value, not a key
    ((${#tr_insert_kv[@]}==1)) && {
        x_insert "$tr_t_name" "$tr_common_prefix" "${tr_insert_kv[0]}" \
                 "" "" "$tr_var"
        return $?
    }

    ((${#tr_insert_kv[@]}<2)) && return $X_RET_ENUM_OK

    case "$tr_return_mode" in
    leaves|common) : ;;
    *)  die ERR "x_qinserts: unknown return mode:${tr_return_mode@Q}"
        return $X_RET_ENUM_KEY_IS_INVALID
        ;;
    esac

    # The first insertion uses the original KEY
    if [[ "$tr_return_mode" == 'leaves' ]] ; then
        x_insert "$tr_t_name" "$tr_common_prefix${tr_insert_kv[0]}" "${tr_insert_kv[1]}" \
                 "" "" "$tr_var" || return $?
    else
        x_insert "$tr_t_name" "$tr_common_prefix${tr_insert_kv[0]}" "${tr_insert_kv[1]}" \
                 || return $?
    fi

    # The subsequent insertion prefix uses the physical key and brings the node id for acceleration.
    local tr_k_index=2 tr_v_index=3

    _tokens_insert_to_overwrite "$tr_common_prefix" ; tr_common_prefix=$REPLY REPLY=
    local -A w_x_qinserts__prefix_token_info=()
    _x_token_to_node_id w_x_qinserts__prefix_token_info \
                        "$tr_t_name" "$tr_common_prefix" || return $?

    tr_common_prefix=${w_x_qinserts__prefix_token_info[physical_full_key]}
    local tr_common_id=${w_x_qinserts__prefix_token_info[node_id]}
    local tr_out_name=''
    if [[ "$tr_return_mode" == 'common' ]] ; then
        tr_w_out=("$tr_common_id" "$tr_common_prefix")
    else
        tr_out_name=$tr_var
    fi

    for((tr_k_index=2,tr_v_index=3;tr_v_index<${#tr_insert_kv[@]};tr_k_index+=2,tr_v_index+=2)) ; do
        x_insert "$tr_t_name" \
                    "${tr_common_prefix}${tr_insert_kv[tr_k_index]}" \
                    "${tr_insert_kv[tr_v_index]}" \
                    "$tr_common_id" \
                    "$tr_common_prefix" \
                    "$tr_out_name" || return $?
    done

    return $X_RET_ENUM_OK
}

#-------------------------------------------------------------------------------

# Returns an array of node IDs
# 批量插入叶：树名在前，输出数组名可选（空=不收集返回列表）。
# @in  $1=树名  $2=输出数组名（可空）  $3..=成对的 {key value}
# @out $2=叶节点 "node_id physical_key" 列表（$2 非空时）
# @ret 0=OK  其他=透传 x_insert 的返回码
x_inserts ()
{
    # local - ; set +x
    local tr_t_name=$1 tr_var=$2
    shift 2

    if [[ -n "$tr_var" ]] ; then
        local -n tr_w_out=$tr_var
        tr_w_out=()
    fi

    while (($#>1)) ; do
        x_insert "$tr_t_name" "$1" "$2" "" "" "$tr_var" || return $?
        shift 2
    done
    return $X_RET_ENUM_OK
}

#-------------------------------------------------------------------------------

# ============================================================================
# 【批量写入双雄】
#
#   两个函数都是「快速/轻量」写入路径，核心诉求是快。
#
#   选型一句话：
#     - 父节点已知、只写一层、批量   → x_insert_token_dict（最快，零校验）
#     - 给完整路径、自动建中间节点   → x_insert_dict     （轻校验，单点写）
# ============================================================================

#-------------------------------------------------------------------------------
# x_insert_token_dict — 全库最快的批量写入路径（支持自动定位父节点）
#
# 【用途】
#   父节点已确定（或可通过物理路径定位），一次性给它挂上一批直接子节点 /
#   更新一批已知叶子的值。典型：从关联数组批量灌入一层 KV。
#
# 【两种用法模式】
#   1. 显式传父节点 ID（极速模式，零校验）：
#      x_insert_token_dict tree "$node_id" "$prefix" "{k1}" v1 "{k2}" v2
#      - 调用方必须保证 $node_id 和 $prefix 完全对应，否则结构会坏。
#
#   2. 传空字符串自动定位（懒人模式，轻校验）：
#      x_insert_token_dict tree "" "$prefix" "{k1}" v1 "{k2}" v2
#      - 内部自动解析 $prefix 找父节点，并校验父节点不能是叶子。
#      - 路径不存在会直接报错（绝不自动建路径）。
#
# 【支持的 token】
#   '{k}'  —— 对象键。若 $tr_prefix$tr_token 尚不存在，创建子节点并挂上；
#             若已存在（例如重复调用），直接更新其值，不新建。
#             注意：已存在的路径若是空容器 sentinel（{} / []），这里会按
#             “更新值”写入，保留 .t，值不可见 —— 结构会坏。调用方必须保证
#             该路径是普通叶子/标量，不能是空容器。
#   '<id>' —— 物理 id。必须指向已存在的叶子/预分配节点（有 .k 或 .t 或 .s）；
#             此时 $tr_prefix$tr_token 存在，走“更新值”分支，不建子节点。
#             若指向容器节点（无 .k 值），守卫失效，会创建影子节点、max_index
#             虚增、children 重复追加 —— 结构会坏，调用方须避免。
#
# 【不支持的 token】
#   '[i]' / '()' —— 索引 token。会被当作对象键写入，路径与索引语义错位（不报错）。
#
# 【显式传 ID 模式的契约】（违反不报错，但结构会坏）
#   1. $2 是树中已存在的容器节点 ID（OBJ 或 ARR）
#   2. $3 是该节点的物理全 key（与 $2 对应，用于拼子节点路径）
#   3. $4.. 的 token 是 '{k}'，或指向叶子/预分配节点的 '<id>'（不能指向容器）
#
# 【用法示例】
#   # 模式一：显式传 ID（如果在循环里，前面已经拿过 ID 了）
#   x_insert_token_dict my_tree "$node_id" "$physical_prefix" "{k1}" v1 "{k2}" v2
#
#   # 模式二：自动定位（一次性调用最省心）
#   local -A assoc=(['{1 2}']='a b' ['{3 4}']='c d')
#   x_insert_token_dict my_tree "" "{_cache}$X" "${assoc[@]@k}"
#
# @in  $1=树名  $2=已存在的父节点 ID（传空=自动查询）
#      $3=父节点物理全 key
#      $4..=token,value 交错（token 为 '{k}' 或叶子 '<id>'）
# @ret 0=OK  3=路径未找到  4=key 无效  8=父节点是叶子
#-------------------------------------------------------------------------------
x_insert_token_dict ()
{
    local -n tr_t=$1
    local tr_node=$2 tr_path_key= tr_child_id=
    # local tr_prefix=$3
    local -a tr_token_values=("${@:4}") tr_tokens=()
    local -i tr_index=0
    local tr_token tr_value

    # ---- 自动定位：$2 为空时，从 $3 走一遍树找父节点 ----
    if [[ -z "$tr_node" ]] ; then
        if [[ -z "$3" ]] ; then
            # 空前缀 → 根节点
            tr_node=$X_ROOT_ID
        else
            x_key_is_invalid "$3" || return $?

            local node tk cid
            local -a w_x_insert_token_dict__tks=()
            _split_tokens_fast w_x_insert_token_dict__tks \
                               "$3" 0 || return $?
            node=$X_ROOT_ID
            for tk in "${w_x_insert_token_dict__tks[@]}" ; do
                if [[ "$tk" == '<'*'>' ]] ; then
                    cid=${tk:1:-1}
                else
                    cid="${tr_t[$node.c.$tk]}"
                fi
                if [[ -z "$cid" ]] ; then
                    die ERR "x_insert_token_dict: path '${3}'"\
                            "not found (at token: ${tk})."
                    return $X_RET_ENUM_KEY_IS_NOTFOUND
                fi
                node=$cid
            done
            tr_node=$node

            # 防呆：父节点不能是叶子（既无 .t 也无 .s，说明是普通值或 NULL 叶子）
            # 因为这个快速函数不处理 NULL 升变
            if [[ -z "${tr_t[$tr_node.t]+_}" &&
                  -z "${tr_t[$tr_node.s]+_}" ]] ; then
                die ERR "x_insert_token_dict: parent '${3}' is a"\
                        "leaf, cannot have children."
                return $X_RET_ENUM_KEY_UP_LEV_TYPE_MISMATCH
            fi
        fi
    fi

    for((tr_index=0;tr_index<${#tr_token_values[@]};tr_index+=2)) ; do
        tr_token=${tr_token_values[tr_index]}
        tr_value=${tr_token_values[tr_index+1]}
        tr_path_key=$3$tr_token$X

        [[ ${tr_t[$tr_path_key]+_} ]] && {
            tr_t[$tr_path_key]=$tr_value
            continue
        }

        tr_child_id="${tr_t[max_index]}" ; ((tr_t[max_index]++))
        if [[ "$tr_token" != '<'*'>' ]] ; then
            tr_t["$tr_node.c.$tr_token"]=$tr_child_id
        fi
        tr_tokens+=("$tr_token")

        case "$tr_value" in
        "$X_VALUE_NULL_ARR")
            tr_t[$tr_child_id.t]="$X_TYPE_ARR"
            ;;
        "$X_VALUE_NULL_OBJ")
            tr_t[$tr_child_id.t]="$X_TYPE_OBJ"
            ;;
        *)
            tr_t[$tr_child_id.k]=$tr_path_key
            tr_t["$tr_path_key"]=$tr_value
            ;;
        esac
    done

    ((${#tr_tokens[@]})) &&
        tr_t[$tr_node.s]+="${tr_t[$tr_node.s]:+ }${tr_tokens[*]@Q}"
    return $X_RET_ENUM_OK
}

#-------------------------------------------------------------------------------
# x_insert_dict — 完整物理路径写入（只支持对象键，轻校验）
#
# 用途：给一个完整的物理路径，从起始节点往下走，路径上的 {} 缺失就自动建。
#       典型：xo_init 的类继承树、xo_debug_classes 的调试树。
#
# 支持：'{}' 对象键、'<>' 物理 id；
# 不支持：'[i]' / '()' 索引 token（直接 die）。
#
# 【不要用于】
#   1. 在 NULL 叶子上挂子节点
#      x_insert_dict 不会执行 leaf→object 升变；它可能留下 .k + .t + 子节点，
#      x_get_node_type 仍会把它判成 leaf，子节点不可见。
#      需要升变时用 x_insert。
#   2. 数组路径
#      需要 [] / () 时用 x_insert。
#   3. 父节点可能是 leaf / NULL / ARR
#      本函数不检查父节点类型；调用方必须保证父节点已经是 OBJ。
#   4. 完整路径已经是一个容器
#      本函数不检查最终节点是否已有子节点；误用会把值写到容器路径上。
#
# 轻校验（与 x_insert 对比）：
#   - 物理 id 不存在 → die（拦）
#   - 索引 token    → die（拦）
#   - NULL 叶子升变 → 不处理（危险，调用方保证不会发生）
#   - 父节点类型    → 不检查（危险，调用方保证是 OBJ）
#   - 最终节点有子  → 不检查（危险，调用方保证路径未存在）
#   结论：比 x_insert 快，但只适合“父节点已确定是 OBJ、路径可信”的写入。
#
# 调用方须保证：
#   1. $2 是从根开始的完整物理路径（不是相对路径），且只含 {} / <id>
#   2. 路径上的中间节点必须是 OBJ
#   3. 不要用它在 NULL 叶子上升变
#   4. $4 和 $5 必须配对：
#      - 都默认：从根开始
#      - 都传：$5 是已走过的前缀，$2 去掉 $5 后从 $4 往下走
#      - 只传其一：割裂，行为未定义
#
# 与 x_insert / x_insert_token_dict 的区别：
#   x_insert            —— 完整校验，支持 NULL 升变、数组、已有容器
#   x_insert_dict       —— 完整路径，只建 OBJ，单点写，轻校验
#   x_insert_token_dict —— 父节点已定，只铺一层，批量，零校验，最快
#
# 用法（父节点已经是 OBJ）：
#   x_insert_dict my_tree "{Base}$X{Device}$X{x}$X" 10
#   # 若 {Device} 中间节点不存在，会自动创建并挂上 {x}=10
#
# @in  $1=树名  $2=完整物理路径（从根开始）  $3=值
#      $4=起始节点 ID（默认 ROOT）  $5=已遍历物理前缀（默认空）
# @ret 0=OK  3=KEY_IS_NOTFOUND  4=KEY_IS_INVALID
#-------------------------------------------------------------------------------
x_insert_dict ()
{
    local -n tr_t=$1
    # local tr_full_key=$2
    # local tr_value=$3
    # local tr_start_node_id=${4:-"$X_ROOT_ID"}

    [[ ${tr_t["$2"]+_} ]] && {
        tr_t["$2"]=$3
        return ${X_RET_ENUM_OK}
    }

    local tr_token tr_child_key tr_child_id \
          tr_node=${4:-"$X_ROOT_ID"} tr_path_key=${5:-""}

    # Here tr_full_key needs to remove the tr_path_key prefix and start traversing
    local -a w_x_insert_dict__tr_tokens=()
    _split_tokens_fast w_x_insert_dict__tr_tokens \
                       "${2#"$tr_path_key"}" 0 || return $?

    for tr_token in "${w_x_insert_dict__tr_tokens[@]}" ; do
        local tr_token_pack="${tr_token:0:1}${tr_token: -1}"
        case "$tr_token_pack" in
        '<>')
            # 物理 id：直接取，必须已存在。物理 id 不能凭空创建，
            # 出现不存在的 <id> 说明调用者传了非物理路径或结构已坏。
            tr_child_id=${tr_token:1:-1}
            if [[ -z "${tr_t[$tr_child_id.k]+_}" ]] && \
               [[ -z "${tr_t[$tr_child_id.t]+_}" ]] && \
               [[ -z "${tr_t[$tr_child_id.s]+_}" ]] ; then
                die ERR "node:${tr_node}(token:${tr_token@Q}) is not exist."
                return $X_RET_ENUM_KEY_IS_NOTFOUND
            fi
            ;;
        '{}')
            # 快速定型：只补缺失的 OBJ 类型，不做叶子/ARR 校验（快速语义）
            [[ -z "${tr_t[$tr_node.t]+_}" ]] && tr_t[$tr_node.t]="$X_TYPE_OBJ"

            # 对象键：查 .c，缺失则建 .c
            tr_child_key="$tr_node.c.$tr_token"
            tr_child_id="${tr_t[$tr_child_key]}"
            [[ -z "$tr_child_id" ]] && {
                tr_child_id="${tr_t[max_index]}" ; ((tr_t[max_index]++))
                tr_t[$tr_node.s]+="${tr_t[$tr_node.s]:+ }${tr_token@Q}"
                tr_t["$tr_child_key"]=$tr_child_id
            }
            ;;
        *)
            # [i] / () 不在本函数支持范围：本函数不做索引解析
            die ERR "token:${tr_token@Q} is not supported by x_insert_dict (only '{k}' or '<id>')."
            return $X_RET_ENUM_KEY_IS_INVALID
            ;;
        esac

        tr_node=$tr_child_id
        tr_path_key+="$tr_token$X"
    done

    case "$3" in
    "$X_VALUE_NULL_ARR")
        tr_t[$tr_node.t]="$X_TYPE_ARR"
        return $X_RET_ENUM_OK
        ;;
    "$X_VALUE_NULL_OBJ")
        tr_t[$tr_node.t]="$X_TYPE_OBJ"
        return $X_RET_ENUM_OK
        ;;
    *)
        tr_t[$tr_node.k]=$tr_path_key
        tr_t["$tr_path_key"]=$3
        return $X_RET_ENUM_OK
    esac
}

#-------------------------------------------------------------------------------

# Returns the inserted node ID, used by external or object tracking systems to track the ID of the object.
#
# 核心插入：把 $3 插入到 $1 的 $2 位置，支持自动创建路径节点。
# @in  $1=树名  $2=物理全 key  $3=值（X_VALUE_NULL_OBJ/ARR 或叶值）
#      $4=起始节点 ID（默认 ROOT）  $5=已遍历物理前缀（默认空）
#      $6=可选输出数组名（调用方先声明 local -a；函数只追加，不清理；不传则不返回列表）
# @out $6=追加 "node_id physical_key"（可选）
# @ret 0=OK  4=X_RET_ENUM_KEY_IS_INVALID  8=X_RET_ENUM_KEY_UP_LEV_TYPE_MISMATCH
#
# 行为状态机:
#     操作                                          结果
#     空字典 -> 普通标量                            X rc=8 is null obj,but insert is not.
#     空字典 -> null 叶子                           X 同上
#     空字典 -> 空数组                              X 同上
#     空数组 -> 普通标量/null叶子/空字典            X rc=8 is null array,but insert is not.
#     空字典 -> 空字典（同类型，空）                OK rc=0（幂等重写）
#     空数组 -> 空数组（同类型，空）                OK rc=0
#     空字典 -> 加子节点 {a}{b}=1                   OK 变成非空字典
#     空数组 -> 加元素 {arr}[0]=1                   OK 变成非空数组
#     空字典下写 [0]                                X up layer is not array or null.
#     空数组下写 {k}                                X is not obj or null.
#     非空容器 -> 普通标量/空容器(哪怕同类型)       X have children.这种情况请先用删除API删除节点，再写空容器
#     普通叶子 -> 空字典 / 空数组                   OK 两种都行
#     null 叶子 -> 空字典 / 空数组                  OK 两种都行
#     普通叶子 <-> null 叶子                        OK 直接覆盖
#     路径上的 null 叶子 -> 下钻 {p}{c} 或 {p}[0]   OK 按第一个子 token 升变成 OBJ 或 ARR
#     路径上的普通叶子 -> 下钻                      X 只有 null 有“穿透升变”特权
x_insert ()
{
    # local - ; set +x
    local -n tr_t=$1
    # local tr_full_key=$2
    local -i tr_array_index=-1 tr_has_id_key_list=0

    x_key_is_invalid "$2" || return $?

    # local tr_value=$3
    # local tr_start_node_id=${4:-"$X_ROOT_ID"}
    local tr_path_key=${5:-""}
    if [[ -n "$6" ]] ; then
        # 这里是追加的语义，上层要负责清理
        local -n tr_w_k_id_key_list=$6
        tr_has_id_key_list=1
    fi

    if [[ -n "$tr_path_key" ]] ; then
        x_key_is_invalid "$tr_path_key" || return $?

        [[ "$tr_path_key" == *"]$X"* || "$tr_path_key" == *")$X"* ]] && {
            die ERR "path key:${tr_path_key@Q} is not physical key."
            return $X_RET_ENUM_KEY_IS_INVALID
        }
    fi

    # If it is a leaf node, update the value directly
    if  [[ ${tr_t["$2"]+_} ]] &&
        [[ "$3" != "$X_VALUE_NULL_ARR" ]] &&
        [[ "$3" != "$X_VALUE_NULL_OBJ" ]] ; then
        tr_t["$2"]=$3
        # 叶子覆盖只需要 node_id + physical_full_key。含 [i]/() 的路径需要索引
        # token 的物理解析，仍走完整版本；纯 {} / <> 路径走无 assoc 的快速查找。
        # 索引 token 的识别用“闭合 ]/)”+ 分隔符：早退路径只处理已存在的值键，
        # 数组元素的值存在物理 <id>$X 下，[i]/() 正常不会走到这里；这里是防御。
        local tr_node_id tr_node_phys_key
        if [[ "$2" == *"]$X"* || "$2" == *")$X"* ]] ; then
            local -A w_x_insert__ninfo=()
            _x_token_to_node_id w_x_insert__ninfo "$1" "$2" || return $?

            tr_node_id=${w_x_insert__ninfo[node_id]}
            tr_node_phys_key=${w_x_insert__ninfo[physical_full_key]}
        else
            _x_token_to_node_id_fast "$1" "$2" \
                    tr_node_id tr_node_phys_key || return $?
        fi
        if ((tr_has_id_key_list)) ; then
            tr_w_k_id_key_list+=("$tr_node_id" "$tr_node_phys_key")
        fi
        return ${X_RET_ENUM_OK}
    fi

    local tr_token tr_child_key tr_child_id tr_tokens_str

    # Here tr_full_key needs to remove the tr_path_key prefix and start traversing
    tr_tokens_str=${2#"$tr_path_key"}
    [[ -n "$tr_path_key" && "$tr_tokens_str" == "$2" ]] && {
        die ERR "path_key:${tr_path_key@Q} is not part of full key:${2@Q}."
        return $X_RET_ENUM_KEY_IS_INVALID
    }

    local -a w_x_insert__tr_tokens=()
    _split_tokens w_x_insert__tr_tokens "$tr_tokens_str" 1 || return $?
    local tr_node=${4:-"$X_ROOT_ID"}

    # Record the ID key of the created intermediate node, all need to be deleted
    local -A tr_tmp_node_ids_map=()

    local tr_key tr_token_pack
    for tr_token in "${w_x_insert__tr_tokens[@]}" ; do
        tr_key="${tr_t[$tr_node.k]}" \
        tr_array_index=-1 \
        tr_token_pack="${tr_token:0:1}${tr_token: -1}"
        case "$tr_token_pack" in
        '{}') 
            # The previous level must be null or obj or nothing (only nodes have tags)
            if [[ "${tr_t[$tr_node.t]}" == "$X_TYPE_OBJ" ]] ; then
                :
            elif [[ -n "$tr_key" ]] && [[ "${tr_t[$tr_key]}" == "$X_VALUE_NULL" ]] ; then
                # Become path empty obj
                unset -v 'tr_t[$tr_node.k]' 'tr_t[$tr_key]'
                tr_t[$tr_node.t]=$X_TYPE_OBJ
            # If tr_node has only node tags, then turn it into empty obj
            elif [[ ${tr_tmp_node_ids_map[$tr_node]+_} ]] &&
                [[ -z ${tr_t[$tr_node.k]+_} ]] &&
                [[ -z ${tr_t[$tr_node.s]+_} ]] &&
                [[ "${tr_t[$tr_node.t]}" != "$X_TYPE_ARR" ]] ; then
                tr_t[$tr_node.t]=$X_TYPE_OBJ
            else
                die ERR "node:${tr_node}(token:${tr_token@Q}) is not obj or null."
                return $X_RET_ENUM_KEY_UP_LEV_TYPE_MISMATCH
            fi
            ;;
        '[]'|'()')
            # If the previous layer is null, create an empty array path node.
            if [[ -n "$tr_key" ]] && [[ "${tr_t[$tr_key]}" == "$X_VALUE_NULL" ]] ; then
                unset -v 'tr_t[$tr_node.k]' 'tr_t[$tr_key]'
                tr_t[$tr_node.t]=$X_TYPE_ARR
            # Contains only node existence flags
            elif [[ ${tr_tmp_node_ids_map[$tr_node]+_} ]] &&
                [[ -z ${tr_t[$tr_node.k]+_} ]] &&
                [[ -z ${tr_t[$tr_node.s]+_} ]] &&
                [[ "${tr_t[$tr_node.t]}" != "$X_TYPE_OBJ" ]] ; then
                tr_t[$tr_node.t]=$X_TYPE_ARR
            fi

            [[ "${tr_t[$tr_node.t]}" != "$X_TYPE_ARR" ]] && {
                die ERR "node:${tr_node}(token:${tr_token@Q}) up layer is not array or null."
                return $X_RET_ENUM_KEY_UP_LEV_TYPE_MISMATCH
            }

            # Fill incomplete null nodes and update tr_token
            local -a "tr_array=(${tr_t[$tr_node.s]})"
            local -i tr_i tr_array_len=${#tr_array[@]}
            local -a tr_add_token=()

            _negative_token_to_positive "$tr_token" "$tr_array_len" "$tr_node" || return $?
            tr_token=$REPLY REPLY=

            for((tr_i=tr_array_len;tr_i<${tr_token:1:-1};tr_i++)) ; do
                local tr_new_id=${tr_t[max_index]} ; ((tr_t[max_index]++))
                # tr_tmp_node_ids_map[$tr_new_id]=1
                tr_t[$tr_new_id.k]="$tr_path_key<$tr_new_id>$X"
                tr_t["$tr_path_key<$tr_new_id>$X"]="$X_VALUE_NULL"
                # Attach parent node children
                # ["1.c.<2>"]="2"
                # array not need to contains child
                # tr_t["$tr_node.c.<$tr_new_id>"]=$tr_new_id
                tr_add_token+=("<$tr_new_id>")
            done

            tr_array_index=${tr_token:1:-1}

            if ((${#tr_add_token[@]})) ; then
                # Populate the parent node's children list
                tr_array=("${tr_array[@]:0:tr_array_len}" "${tr_add_token[@]}" "${tr_array[@]:tr_array_len}")
                tr_t[$tr_node.s]=${tr_array[*]@Q}
                tr_token="<${tr_t[max_index]}>"
            else
                tr_token="${tr_array[tr_array_index]}"

                if [[ -z "$tr_token" ]] ||
                   [[ "$tr_token_pack" == '()' ]] ; then
                    tr_token="<${tr_t[max_index]}>"
                fi
            fi
            ;;
        '<>')
            # The previous level must be an array and elements must exist
            if [[ "${tr_t[$tr_node.t]}" != "$X_TYPE_ARR" ]] ; then
                die ERR "node:${tr_node}(token:${tr_token@Q}) up layer is not array."
                return $X_RET_ENUM_KEY_UP_LEV_TYPE_MISMATCH
            fi

            # <id> 中的 id 是全局唯一节点 id，直接检查节点是否活跃即可
            local tr_ref_id=${tr_token:1:-1}
            if [[ -z "${tr_t[$tr_ref_id.k]+_}" ]] && \
               [[ -z "${tr_t[$tr_ref_id.t]+_}" ]] && \
               [[ -z "${tr_t[$tr_ref_id.s]+_}" ]] ; then
                die ERR "node:${tr_node}(token:${tr_token@Q}) is not exist."
                return $X_RET_ENUM_KEY_UP_LEV_TYPE_MISMATCH
            fi
            ;;
        esac

        if [[ "$tr_token" == '<'*'>' ]] ; then
            tr_child_id=${tr_token:1:-1}
        else
            tr_child_key="$tr_node.c.$tr_token"
            tr_child_id="${tr_t[$tr_child_key]}"
        fi

        # Child node does not exist -> create
        #   - 非 <id> token：按 .c. 查不到
        #   - <id> token：节点三个标记键都不存在（预分配节点有 .k）
        if [[ -z "$tr_child_id" || ( "$tr_token" == '<'*'>' &&
            -z "${tr_t[${tr_token:1:-1}.k]+_}"  &&
            -z "${tr_t[${tr_token:1:-1}.t]+_}"  &&
            -z "${tr_t[${tr_token:1:-1}.s]+_}" ) ]] ; then
            if [[ "$tr_token" == '<'*'>' ]] ; then
                # 全新 <id> token（来自 tr_token="<max_index>"）：id 就是 max_index 当前值
                tr_child_id=${tr_token:1:-1}
                ((tr_t[max_index]++))
            else
                tr_child_id="${tr_t[max_index]}" ; ((tr_t[max_index]++))
                # 对象键才建 .c.
                tr_t["$tr_child_key"]=$tr_child_id
            fi
            tr_tmp_node_ids_map[$tr_child_id]=1

            if ((tr_array_index!=-1)) ; then
                local -a "tr_children=(${tr_t[$tr_node.s]})"
                if [[ "$tr_token_pack" == '()' ]] ; then
                    tr_children=("${tr_children[@]:0:tr_array_index}" "$tr_token" "${tr_children[@]:tr_array_index}")
                else
                    tr_children[$tr_array_index]="$tr_token"
                fi
                tr_t[$tr_node.s]=${tr_children[*]@Q}
            else
                # 字典/<id> 的新子节点只追加到末尾：.c 已确认不存在，直接拼到 .s。
                # 用 += 保留旧 .s；:+ 只在旧值非空时补空格（判空，不是判“是否设置”），
                # 这样 .s 未设置或被置空都不会产生前导空格。
                tr_t[$tr_node.s]+=${tr_t[$tr_node.s]:+ }${tr_token@Q}
            fi
        fi

        tr_node=$tr_child_id
        tr_path_key+="$tr_token$X"
    done

    # Write leaf key
    # Leaf nodes may be empty obj or empty array
    # Leaf nodes are set to provide better coverage.
    # Intermediate nodes are strictly limited. x_graft (xe.sh) maintains the same semantics.
    # If it is found at the end that there are children at the inserted place,
    # it proves to be an existing structure node,
    # and the leaf is not allowed to be inserted.
    [[ -n "${tr_t[$tr_node.s]}" ]] && {
        die ERR "node:${tr_node}(token:${tr_token@Q}) have children."
        return $X_RET_ENUM_KEY_UP_LEV_TYPE_MISMATCH
    }

    # If it is found at the end that the inserted place is an empty obj or an
    # empty array, but the content to be inserted does not match,
    # an error will be reported.
    if  [[ "${tr_t[$tr_node.t]}" == "$X_TYPE_OBJ" ]] &&
        [[ "$3" != "$X_VALUE_NULL_OBJ" ]] ; then
        die ERR "node:${tr_node}(token:${tr_token@Q}) is null obj,but insert is not."
        return $X_RET_ENUM_KEY_UP_LEV_TYPE_MISMATCH
    fi

    if  [[ "${tr_t[$tr_node.t]}" == "$X_TYPE_ARR" ]] &&
        [[ "$3" != "$X_VALUE_NULL_ARR" ]] ; then
        die ERR "node:${tr_node}(token:${tr_token@Q}) is null array,but insert is not."
        return $X_RET_ENUM_KEY_UP_LEV_TYPE_MISMATCH
    fi

    local tr_new_type
    case "$3" in
        "$X_VALUE_NULL_ARR")   tr_new_type="$X_TYPE_ARR" ;;
        "$X_VALUE_NULL_OBJ")   tr_new_type="$X_TYPE_OBJ" ;;
        *)
            tr_t[$tr_node.k]=$tr_path_key
            tr_t["$tr_path_key"]=$3
            # 返回节点 ID
            if ((tr_has_id_key_list)) ; then
                tr_w_k_id_key_list+=("$tr_node" "$tr_path_key")
            fi
            return $X_RET_ENUM_OK
    esac

    # The current leaf strings, values and bool can be overwritten into
    # empty objects and empty arrays.
    # Leaves null are naturally OK
    local tr_key="${tr_t[$tr_node.k]}"
    unset -v 'tr_t[$tr_node.k]'
    [[ -n "$tr_key" ]] && unset -v 'tr_t[$tr_key]'
    tr_t[$tr_node.t]="$tr_new_type"
    if ((tr_has_id_key_list)) ; then
        tr_w_k_id_key_list+=("$tr_node" "$tr_path_key")
    fi
    return $X_RET_ENUM_OK
}

#-------------------------------------------------------------------------------

# 打印整棵树（调试用）。
# @in  $1=树名  $2=起始物理全 key（空=根）  $3=缩进宽度（默认 4）
#      $4=打印掩码（bit0=ID，bit1=值，bit2=数组索引，默认 0b111）
# @ret 0
x_dump ()
{
    # local - ; set +x
    local tr_t_name=$1 tr_full_key=$2 \
          tr_indent_cnt=${3:-4} tr_print_mask=${4:-$((2#111))}
    local -n tr_t=$1
    # bit0: id is need to print
    # bit1: value is need to print
    # 0: id 1: value 2: array index
    local tr_id_need_print tr_value_need_print tr_print_array_index
    var_bitmap_unpack   "$tr_print_mask" \
                        "tr_id_need_print:0" \
                        "tr_value_need_print:1" \
                        "tr_print_array_index:2"

    local tr_node
    local -A w_x_dump__ninfo=()
    _x_token_to_node_id w_x_dump__ninfo "$tr_t_name" "$tr_full_key" || return $?

    tr_node=${w_x_dump__ninfo[node_id]}
    str_repeat ' ' "$tr_indent_cnt" ; local tr_indent=$REPLY ; REPLY=

    printf '%s(%s) -> %s\n' "$tr_t_name" "$tr_node" "${w_x_dump__ninfo[physical_full_key]}"

    [[ "${tr_t[$tr_node.t]}" == "$X_TYPE_OBJ" ]] &&
    [[ -z "${tr_t[$tr_node.s]}" ]] && {
        str_escape_keep_nl "$X_VALUE_NULL_OBJ"
        printf '%s%s\n' "$tr_indent" "$REPLY"
        printf '%smax_index => %s\n' "$tr_indent" "${tr_t[max_index]}"
        return
    }

    [[ "${tr_t[$tr_node.t]}" == "$X_TYPE_ARR" ]] &&
    [[ -z "${tr_t[$tr_node.s]}" ]] && {
        str_escape_keep_nl "$X_VALUE_NULL_ARR"
        printf '%s%s\n' "$tr_indent" "$REPLY"
        printf '%smax_index => %s\n' "$tr_indent" "${tr_t[max_index]}"
        return
    }

    _x_dump  "$tr_t_name" "$tr_node" "$tr_indent_cnt" "$tr_indent" \
                "$tr_id_need_print" "$tr_value_need_print" \
                "$tr_print_array_index"
    printf '%smax_index => %s\n' "$tr_indent" "${tr_t[max_index]}"
}

#-------------------------------------------------------------------------------

# 递归打印内部引擎，由 x_dump 调用，不建议直接使用。
_x_dump ()
{
    local -n tr_t=$1
    local tr_node=$2 tr_indent_cnt=$3 tr_indent=$4 \
          tr_id_need_print=$5 tr_value_need_print=$6
    local tr_print_array_index=$7
    
    str_repeat ' ' "$tr_indent_cnt" ; local tr_indent_new=$REPLY ; REPLY=
    tr_indent_new+="$tr_indent"

    # Traverse children
    local -a "tr_children=(${tr_t[$tr_node.s]})"
    local -i tr_index=0

    # There cannot be duplicate elements in the array
    # The output order of hash keys is output in accordance with the hash bucket.
    # If a conflict occurs in the bucket, it is output in the order of the linked list.
    # So the order here is very unstable. It is OK when there are few elements,
    # but if there are too many elements,hash table will trigger expansion,
    # and if there are too few elements, the hash bucket will trigger shrinkage.
    # So here is just an approximate fix, It is not absolutely fixed. This
    # feature can be used to stabilize the display key when the number of
    # elements is small.
    [[ "${tr_children[0]}" == '{'* ]] && {
        local tr_children_sorted=
        printf -v tr_children_sorted '[%s]= ' "${tr_children[@]@Q}"
        local -A "tr_children_sorted=($tr_children_sorted)"
        tr_children=("${!tr_children_sorted[@]}")
    }

    local tr_token tr_mark='=>'
    for tr_token in "${tr_children[@]}"; do
        if [[ "$tr_token" == '<'*'>' ]] ; then
            local tr_child_id=${tr_token:1:-1}
        else
            local tr_child_id="${tr_t[$tr_node.c.$tr_token]}"
        fi
        local tr_child_id_p='' tr_value_p=''
        local tr_token_safe tr_token_disp

        tr_mark='=>'
        if [[ "${tr_t[$tr_node.t]}" == "${X_TYPE_ARR}" ]]; then
            tr_mark='='
            ((tr_print_array_index)) && tr_token=$tr_index || tr_token='o'
            # 数组 token 是索引或 'o'，无危险字符，直接透传
            tr_token_safe=$tr_token tr_token_disp=$tr_token
        else
            # 字典键：统一走自定义转义（保留 \n，内部的 }转义），不再用 %q/@Q
            str_escape_key "${tr_token:1:-1}"
            tr_token_safe="{$REPLY}"
            # 多行键的续行加 | 补位：| 与第一行的 { 对齐，
            # 使行首空格明确属于键内容而非缩进
            tr_token_disp="${tr_token_safe//$'\n'/$'\n'$tr_indent|}"
        fi

        ((tr_id_need_print)) && tr_child_id_p="($tr_child_id)"

        if [[ -n "${tr_t[$tr_child_id.k]}" ]]; then
            local tr_key=${tr_t[$tr_child_id.k]}
            local tr_value=${tr_t["$tr_key"]}
            ((tr_value_need_print)) && {
                local tr_value_indent="${tr_token_safe}"
                ((tr_id_need_print)) && tr_value_indent+="(${tr_child_id})"
                tr_value_indent=${tr_value_indent##*$'\n'}
                local _XDump_w ; str_display_width "$tr_value_indent" _XDump_w
                printf -v tr_value_indent '%*s' "$_XDump_w" ''

                # 多行键最后一行多了 |，值续行补偿加一个空格
                [[ $tr_token_safe == *$'\n'* ]] && tr_value_indent+=" "
                # 值除了第一行其它的行都由 | 开头
                if [[ "$tr_mark" == '=' ]]; then
                    tr_value_indent+="${tr_indent}  |"
                else
                    tr_value_indent+="${tr_indent}   |"
                fi
                tr_value_p="${tr_value//$'\n'/$'\n'$tr_value_indent}"
                str_escape_keep_nl "$tr_value_p"
                tr_value_p=$REPLY
            }

            printf '%s%s%s %s %s\n' \
                "$tr_indent" \
                "$tr_token_disp" \
                "$tr_child_id_p" \
                "$tr_mark" \
                "$tr_value_p"
        elif [[ "${tr_t[$tr_child_id.t]}" == "$X_TYPE_ARR" ]] && [[ -z "${tr_t[$tr_child_id.s]}" ]] ; then
            ((tr_value_need_print)) && {
                str_escape_keep_nl "$X_VALUE_NULL_ARR"
                tr_value_p=$REPLY

            }

            printf '%s%s%s %s %s\n' \
                "$tr_indent" \
                "$tr_token_disp" \
                "$tr_child_id_p" \
                "$tr_mark" \
                "$tr_value_p"
        elif [[ "${tr_t[$tr_child_id.t]}" == "$X_TYPE_OBJ" ]] && [[ -z "${tr_t[$tr_child_id.s]}" ]] ; then
            ((tr_value_need_print)) && {
                str_escape_keep_nl "$X_VALUE_NULL_OBJ"
                tr_value_p=$REPLY
            }

            printf '%s%s%s %s %s\n' \
                "$tr_indent" \
                "$tr_token_disp" \
                "$tr_child_id_p" \
                "$tr_mark" \
                "$tr_value_p"
        else
            printf '%s%s%s\n' \
                "$tr_indent" \
                "$tr_token_disp" \
                "$tr_child_id_p"
        fi

        _x_dump "$1" "$tr_child_id" "$tr_indent_cnt" "$tr_indent_new" "$tr_id_need_print" "$tr_value_need_print" "$tr_print_array_index"
        ((tr_index++))
    done
}

#-------------------------------------------------------------------------------

# 物理/索引 token 解析为节点 ID，结果直接写入调用方关联数组。
# 调用方先声明 local -A，函数直接写，不使用 REPLY / @K / 反序列化。
# @in  $1=输出关联数组变量名
#      $2=树名  $3=物理全 key
#      $4=需要 index_full_key(0/1)  $5=需要 child_cnt(0/1)  $6=需要 value(0/1)
# @out $1=关联数组 KV：node_id physical_full_key index_full_key type
#             child_cnt(可选) value(可选)
# @ret 0=OK  3=X_RET_ENUM_KEY_IS_NOTFOUND  4=X_RET_ENUM_KEY_IS_INVALID
#
_x_token_to_node_id ()
{
    # 返回上层的关联数组
    local -n w_tr_node_info=$1 ; w_tr_node_info=()
    local -n tr_t=$2
    # local tr_full_key=$3
    local -i    tr_need_index_full_key=${4:-0} \
                tr_need_child_cnt=${5:-0} \
                tr_need_value=${6:-0}

    [[ -z "$3" ]] && {
        # ROOT
        if ((tr_need_child_cnt)) ; then
            if [[ -n "${tr_t[$X_ROOT_ID.s]}" ]] ; then
                local -a "tr_children_tmp=(${tr_t[$X_ROOT_ID.s]})"
                w_tr_node_info[child_cnt]=${#tr_children_tmp[@]}
            else
                w_tr_node_info[child_cnt]=0
            fi
        fi

        w_tr_node_info+=(
            [node_id]="$X_ROOT_ID"
            [physical_full_key]=""
            [index_full_key]=""
            [type]=${tr_t[$X_ROOT_ID.t]}
            [value]=""
            )
        return ${X_RET_ENUM_OK}
    }

    x_key_is_invalid "$3" || return $?

    local -a w__x_token_to_node_id__tr_tokens=()
    _split_tokens w__x_token_to_node_id__tr_tokens \
                  "$3" || return $?
    local tr_node=$X_ROOT_ID tr_token tr_child_id tr_token_raw tr_real_full_key=''
    local tr_token_index= tr_index_full_key=
    for tr_token in "${w__x_token_to_node_id__tr_tokens[@]}" ; do
        tr_token_raw=$tr_token

        tr_resolve_index_token "$2" "$tr_token" "$tr_node" || return $?
        tr_token=$REPLY REPLY=
        [[ -z "$tr_token" ]] && {
            die ERR "node:${tr_node}(token:${tr_token_raw@Q}) is not found physical token!"
            return $X_RET_ENUM_KEY_IS_NOTFOUND
        }
        tr_real_full_key+="$tr_token$X"

        ((tr_need_index_full_key)) && {
            # 树默认合法：<id> 不应缺失；这里不接 4=KEY_IS_INVALID，统一按空值返回 3=NOTFOUND。
            tr_resolve_physical_token "$2" "$tr_token" "$tr_node" ; tr_token_index=$REPLY REPLY=
            [[ -z "$tr_token_index" ]] && {
                die ERR "node:${tr_node}(token:${tr_token_raw@Q}) is not found index token!"
                return $X_RET_ENUM_KEY_IS_NOTFOUND
            }
            tr_index_full_key+="$tr_token_index$X"
        }

        if [[ "$tr_token" == '<'*'>' ]] ; then
            tr_child_id=${tr_token:1:-1}
        else
            tr_child_id="${tr_t[$tr_node.c.$tr_token]}"
        fi
        [[ -z "$tr_child_id" ]] && {
            die ERR "node:${tr_node}(token:${tr_token@Q}) key is not found!"
            return "$X_RET_ENUM_KEY_IS_NOTFOUND"
        }
        tr_node=$tr_child_id
    done

    ((tr_need_index_full_key)) && w_tr_node_info[index_full_key]=$tr_index_full_key

    if ((tr_need_child_cnt)) ; then
        if [[ -n "${tr_t[$tr_node.s]}" ]] ; then
            local -a "tr_children_tmp=(${tr_t[$tr_node.s]})"
            w_tr_node_info[child_cnt]=${#tr_children_tmp[@]}
        else
            w_tr_node_info[child_cnt]=0
        fi
    fi

    ((tr_need_value)) && {
        local tr_key=${tr_t[$tr_node.k]} tr_value=
        [[ -n "$tr_key" ]] && tr_value=${tr_t["$tr_key"]}
        w_tr_node_info[value]=$tr_value
    }

    w_tr_node_info+=(
        [node_id]="$tr_node"
        [physical_full_key]="$tr_real_full_key"
        [type]=${tr_t[$tr_node.t]}
        )
    return ${X_RET_ENUM_OK}
}

#-------------------------------------------------------------------------------
# 内部快速查节点：只接受“已校验、且只含 {} / <> token”的物理路径。
#
# x_insert 的叶子覆盖路径只需要 node_id + physical_full_key，不需要 type /
# value / child_cnt，也不需要索引 token 的物理解析；因此这里跳过 key 校验、
# assoc 拼装和 @K/array_to_kv_q_str 序列化。含 [i]/() 的路径必须由调用方
# 回退到 _x_token_to_node_id（数组索引要做物理 token 解析）。
#
# @in  $1=树名  $2=物理路径  $3=node_id 输出变量名  $4=physical key 输出变量名
# @ret 0=OK  3=X_RET_ENUM_KEY_IS_NOTFOUND
_x_token_to_node_id_fast ()
{
    local -n _xtf_t=$1
    local -n _xtf_id=$3
    local -n _xtf_phys=$4
    # local _xtf_key=$2
    local _xtf_token _xtf_child _xtf_path='' _xtf_node=$X_ROOT_ID

    local -a w__x_token_to_node_id_fast__tokens=()
    _split_tokens_fast w__x_token_to_node_id_fast__tokens \
                       "$2" || return $?

    for _xtf_token in "${w__x_token_to_node_id_fast__tokens[@]}" ; do
        if [[ "$_xtf_token" == '<'*'>' ]] ; then
            _xtf_child=${_xtf_token:1:-1}
        else
            _xtf_child=${_xtf_t[$_xtf_node.c.$_xtf_token]}
        fi
        [[ -z "$_xtf_child" ]] && {
            die ERR "node:${_xtf_node}(token:${_xtf_token@Q}) key is not found!"
            return "$X_RET_ENUM_KEY_IS_NOTFOUND"
        }
        _xtf_node=$_xtf_child
        _xtf_path+="$_xtf_token$X"
    done

    _xtf_id=$_xtf_node
    _xtf_phys=$_xtf_path
    return ${X_RET_ENUM_OK}
}

#-------------------------------------------------------------------------------

# 删除节点（含全部子树）。空 key 会重置整棵树。
# @in  $1=树名  $2=物理全 key（空=清空树）
#      $3=输出数组名（可空；空=不收集被删除的子树根）
# @out $3=列表 "node_id physical_key"（$3 非空时）
# @ret 0=OK  4=X_RET_ENUM_KEY_IS_INVALID
x_delete () 
{
    # local - ; set +x
    local -n tr_t=$1
    local tr_full_key=$2

    if [[ -n "$3" ]] ; then
        local -n tr_w_delete_out=$3
        tr_w_delete_out=()
    fi

    # Empty key is legal. Only ROOT nodes are reserved.
    [[ -z "$tr_full_key" ]] && {
        x_init "$1" "${tr_t[$X_ROOT_ID.t]}"
        [[ -n "$3" ]] && tr_w_delete_out=("$X_ROOT_ID" "")
        return ${X_RET_ENUM_OK}
    }

    x_key_is_invalid "$tr_full_key" || return $?
    
    local -a w_x_delete__tr_tokens=()
    _split_tokens w_x_delete__tr_tokens "$tr_full_key" || return $?

    # 2. Path search: go all the way from root to the node to be deleted
    local tr_node=$X_ROOT_ID
    local -a tr_path_nodes=("$tr_node")
    local -a tr_path_tokens=("")

    local tr_token tr_child_id tr_index
    for tr_token in "${w_x_delete__tr_tokens[@]}"; do
        tr_resolve_index_token "$1" "$tr_token" "$tr_node" || return $?
        tr_token=$REPLY REPLY=
        [[ -z "$tr_token" ]] && return $X_RET_ENUM_OK

        if [[ "$tr_token" == '<'*'>' ]] ;then
            tr_child_id=${tr_token:1:-1}
        else
            tr_child_id="${tr_t[$tr_node.c.$tr_token]}"
        fi
        [[ -z "$tr_child_id" ]] && {
            # die ERR "key is not found!"
            # Keys that do not exist are returned directly.
            return "$X_RET_ENUM_OK"
        }
        tr_path_nodes+=("$tr_child_id")
        tr_path_tokens+=("$tr_token")
        tr_node=$tr_child_id
    done

    printf -v tr_full_key "%s$X" "${tr_path_tokens[@]:1}"

    # At this time, tr_node is the node corresponding to tr_full_key
    # (it can be a leaf or an intermediate node)

    # 3. First delete the value/key/type attached to the current node
    unset -v 'tr_t["$tr_full_key"]' 'tr_t["$tr_node.k"]' 'tr_t["$tr_node.t"]'

    # 4. Kill all subtrees rooted at the current node
    #   (even if it is a single leaf)
    local -a tr_stack=("$tr_node")
    local tr_cur tr_tk tr_cid
    while ((${#tr_stack[@]})); do
        tr_cur=${tr_stack[-1]}
        unset -v 'tr_stack[-1]'

        # Get the current node children tr_token list
        local -a "tr_children=(${tr_t[$tr_cur.s]})"

        for tr_tk in "${tr_children[@]}"; do
            if [[ "$tr_tk" == '<'*'>' ]] ; then
                tr_cid=${tr_tk:1:-1}
            else
                tr_cid="${tr_t[$tr_cur.c.$tr_tk]}"
                unset -v 'tr_t["$tr_cur.c.$tr_tk"]'
            fi
            tr_stack+=("$tr_cid")
        done

        # If this node has its own key/value, clear it as well.
        local tr_key=${tr_t["$tr_cur.k"]}
        [[ -n "$tr_key" ]] && unset -v 'tr_t[$tr_key]'
        unset -v 'tr_t["$tr_cur.k"]' 'tr_t["$tr_cur.s"]' 'tr_t["$tr_cur.t"]'

        # Do not delete the root node itself
        # unset -v "tr_t[$tr_cur]"
    done

    # Update the children of the upper node
    local tr_parent=${tr_path_nodes[-2]}
    tr_token=${tr_path_tokens[-1]}
    local -a "tr_children=(${tr_t[$tr_parent.s]})"
    array_delete_first_e tr_children "$tr_token"
    if ((${#tr_children[@]})) ; then
        tr_t[$tr_parent.s]=${tr_children[*]@Q}
    else
        unset -v 'tr_t[$tr_parent.s]'
    fi

    unset -v 'tr_t["$tr_parent.c.$tr_token"]'

    [[ -n "$3" ]] && tr_w_delete_out=("$tr_node" "$tr_full_key")

    return "$X_RET_ENUM_OK"
}

#-------------------------------------------------------------------------------

# This is just an example to demonstrate the callback function of x_walk,
# processing the entire tree
#
# 示例回调：把遍历元组打印为一行。演示 x_walk 用法，不用于生产。
x_cb_print ()
{
    # leaf / leaf_null / obj / obj_empty / arr / arr_empty
    local node_kind=$1
    # "{k}" or "[0]"
    local index_token=$2
    # "{a}$X[0]$X{b}$X"
    local index_full_key=$3
    # only meaningful for leaf/leaf_null
    local value=$4
    # Internal tokens like "<123>" (if needed)
    local physical_token=$5
    # "{a}$X<12>$X<56>$X"
    local physical_full_key=$6
    local node_id=$7
    local parent_id=$8
    local printf_info
    printf_info+="node kind:$node_kind "
    printf_info+="index token:$index_token "
    printf_info+="index full key:$index_full_key "
    printf_info+="value:$value "
    printf_info+="physical token:$physical_token "
    printf_info+="physical full key:$physical_full_key "
    printf_info+="node id:$node_id "
    printf_info+="parent id:$parent_id"
    printf '%s\n' "$printf_info"
    return $X_RET_ENUM_OK
}

#-------------------------------------------------------------------------------

# 获取节点类型。
# @in  $1=树名  $2=节点 ID
# @ret X_NODE_KIND_OBJ=1 / ARR=2 / OBJ_EMPTY=3 / ARR_EMPTY=4
#      / LEAF=5 / LEAF_NULL=6 / UNKNOWN=7
x_get_node_type ()
{
    # local - ; set +x
    local -n tr_t=$1
    local tr_node=$2
    local tr_input_kind=${3:-id}
    local tr_key

    if [[ "$tr_input_kind" == 'path' ]] ; then
        local -A w_x_get_node_type__ninfo=()
        _x_token_to_node_id w_x_get_node_type__ninfo \
                           "$1" "$tr_node" 0 0 0 2>/dev/null
        (( $? )) && return $X_NODE_KIND_UNKNOWN
        tr_node=${w_x_get_node_type__ninfo[node_id]}
    fi

    if [[ ${tr_t[$tr_node.k]+_} ]] ; then
        tr_key="${tr_t["$tr_node.k"]}"
        if [[ "${tr_t["$tr_key"]}" == "$X_VALUE_NULL" ]] ; then
            return $X_NODE_KIND_LEAF_NULL
        else
            return $X_NODE_KIND_LEAF
        fi
    elif [[ "${tr_t[$tr_node.t]}" == "$X_TYPE_OBJ" ]] ; then
        if [[ -n "${tr_t[$tr_node.s]}" ]] ; then
            return $X_NODE_KIND_OBJ
        else
            return $X_NODE_KIND_OBJ_EMPTY
        fi
    elif [[ "${tr_t[$tr_node.t]}" == "$X_TYPE_ARR" ]] ; then
        if [[ -n "${tr_t[$tr_node.s]}" ]] ; then
            return $X_NODE_KIND_ARR
        else
            return $X_NODE_KIND_ARR_EMPTY
        fi
    else
        return $X_NODE_KIND_UNKNOWN
    fi
}

#-------------------------------------------------------------------------------

# Iterate children under prefix
#                                  Arrays do not need to be wrapped with []
#                   phy_token type index_token value node
# default               1       1       0        0    0
# bit                   0       1       2        3    4
#
# 遍历子节点，每行元组："phy_token type index_token value node"。
# 未请求的字段为空串。
#
# 【消费契约】每行一个元组，字段间是空格，但每个字段都是独立的 @Q 引用。
# 不能用 read -a / awk / 普通空格 split —— 字段内容可能含空格。
# 必须让 shell 重新解析引用：
#     if [[ -n "$iter_str" ]] ; then
#         while IFS= read -r line ; do
#             local -a "tuple=($line)"
#         done <<< "$iter_str"
#     fi
# 空白 here-string 也会让 read 读到一行空串，所以必须先判空。
# 换行在字段内已被 @Q 转义，所以按行拆是安全的。
#
# @in  $1=树名  $2=物理前缀（默认空=根）  $3=迭代掩码
#      （bit0=phy_token bit1=type bit2=index_token bit3=value bit4=node）
#      $4=节点 ID（可选，省略则按前缀解析）
# @out REPLY=多行元组（@Q 格式，行内字段空格分隔）
# @ret 0=OK  4=X_RET_ENUM_KEY_IS_INVALID
x_iter ()
{
    REPLY=
    # local - ; set +x
    local -n tr_t=$1
    local tr_prefix=$2
    local -i tr_is_iter_{phy_token,type,index_token,value,node}=0
    local tr_iter_bitmap=${3:-$((2#00011))}
    local tr_node_id=$4
    var_bitmap_unpack   "$tr_iter_bitmap"          \
                        "tr_is_iter_phy_token:0"   \
                        "tr_is_iter_type:1"        \
                        "tr_is_iter_index_token:2" \
                        "tr_is_iter_value:3"       \
                        "tr_is_iter_node:4"

    [[ -z "$tr_node_id" ]] && {
        [[ -n "$tr_prefix" ]] && {
            x_key_is_invalid "$tr_prefix" || return $?
        }
        local -A w_x_iter__ninfo=()
        _x_token_to_node_id w_x_iter__ninfo \
                            "$1" "$tr_prefix" || return $?
        tr_node_id=${w_x_iter__ninfo[node_id]}
    }

    # If tr_node_id is empty, traverse the root node
    tr_node_id=${tr_node_id:-"$X_ROOT_ID"}

    local -a "tr_children=(${tr_t[$tr_node_id.s]})"

    local tr_tk tr_child_id tr_type tr_key
    local tr_tk_p tr_type_p tr_value_p tr_node_p tr_index_tk_p

    local -i tr_index=0
    local tr_parent_type=${tr_t[$tr_node_id.t]}

    # The safest method for REPLY can only be separate assignment. If you want
    # to append a string to it, it is best to use a separate intermediate
    # variable to process it, and finally assign it to REPLY all at once,
    # or you must clear the value of REPLY first.
    REPLY=
    for tr_tk in "${tr_children[@]}"; do
        if [[ "$tr_tk" == '<'*'>' ]] ; then
            tr_child_id=${tr_tk:1:-1}
        else
            tr_child_id=${tr_t["$tr_node_id.c.$tr_tk"]}
        fi
        if ((tr_is_iter_type)) ; then
            x_get_node_type "$1" "$tr_child_id" ; tr_type=$?
            tr_type_p=${tr_type@Q}
        else
            tr_type_p=''
        fi

        if ((tr_is_iter_index_token)) ; then
            if [[ "$tr_parent_type" == "$X_TYPE_ARR" ]] ; then
                tr_index_tk_p=${tr_index@Q}
            else
                tr_index_tk_p=${tr_tk@Q}
            fi
        else
            tr_index_tk_p=''
        fi

        if ((tr_is_iter_value)) ; then
            tr_key="${tr_t["$tr_child_id.k"]}"
            [[ -n "$tr_key" ]] && tr_value_p=${tr_t["$tr_key"]}

            ((tr_is_iter_type)) || { x_get_node_type "$1" "$tr_child_id" ; tr_type=$? ; }

            # Empty objects and empty arrays return simulated values
            case "$tr_type" in
            $X_NODE_KIND_OBJ_EMPTY)    tr_value_p="$X_VALUE_NULL_OBJ" ;;
            $X_NODE_KIND_ARR_EMPTY)    tr_value_p="$X_VALUE_NULL_ARR" ;;
            esac
            tr_value_p=${tr_value_p@Q}
        else
            tr_value_p=''
        fi

        ((tr_is_iter_phy_token)) && tr_tk_p=${tr_tk@Q}         || tr_tk_p=''
        ((tr_is_iter_node))      && tr_node_p=${tr_child_id@Q} || tr_node_p=''

        #                      phy_token      type       index_token       value         node
        REPLY+="${REPLY:+$'\n'}${tr_tk_p} ${tr_type_p} ${tr_index_tk_p} ${tr_value_p} ${tr_node_p}"
        ((tr_index++))
    done

    return ${X_RET_ENUM_OK}
}

#-------------------------------------------------------------------------------
# 契约（调用方可依赖）：
#   1. 回调签名：kind, index_token, index_full_key, value,
#                phys_token, phys_full_key, node_id, parent_id
#   2. 拓扑序：父节点回调一定早于其所有后代节点回调
#   3. 每个节点回调恰好一次
#   4. 回调返回非 0，遍历提前终止
#
# 实现细节（调用方不应依赖）：
#   - 兄弟子树的相对展开顺序（当前是栈 LIFO，未来可能变）
#   - 同层 children 的回调顺序（当前按 children 数组顺序）
#
# OOP 字段继承只依赖契约 2（拓扑序），不依赖实现细节。
#
# 深度优先遍历子树，每个节点调用 $3 回调。
# 回调参数：node_kind index_token index_full_key value
#           physical_token physical_full_key node_id parent_id
# @in  $1=树名  $2=起始物理全 key（空=根）  $3=回调函数名（默认 x_cb_print）
# @ret 0=OK  其他=回调返回的非 0 值（提前终止）
x_walk ()
{
    # local - ; set +x
    local -n tr_t=$1
    # local tr_prefix=$2
    # local tr_cb=${3:-x_cb_print}

    local tr_physical_full_key tr_index_full_key tr_node_kind \
          tr_node_id tr_index_prefix tr_physical_prefix \
          tr_tk tr_child_id tr_value tr_index_token
    local -i tr_index=0
    local -A w_x_walk__ninfo=()
    _x_token_to_node_id w_x_walk__ninfo \
                        "$1" "$2" 1 || return $?

    # MSYS2 Bash 5.2 的 local 复合数组赋值会吞掉 CR；这里必须
    # 先声明、再赋值，不能合成 local -a tr_stack=(...)。
    # 但是库里面类似的风险还有不少，只能 msys2 用户自己去避免
    local -a tr_stack=()
    tr_stack=(
        "${w_x_walk__ninfo[physical_full_key]}"
        "${w_x_walk__ninfo[index_full_key]}"
        "${w_x_walk__ninfo[node_id]}"
    )

    while ((${#tr_stack[@]})); do
        tr_node_id=${tr_stack[-1]} ; unset -v 'tr_stack[-1]'
        tr_index_prefix=${tr_stack[-1]} ; unset -v 'tr_stack[-1]'
        tr_physical_prefix=${tr_stack[-1]} ; unset -v 'tr_stack[-1]'

        local -a "tr_children=(${tr_t[$tr_node_id.s]})"
        tr_index=0
        for tr_tk in "${tr_children[@]}"; do
            if [[ "$tr_tk" == '<'*'>' ]] ; then
                tr_child_id=${tr_tk:1:-1}
            else
                tr_child_id=${tr_t["$tr_node_id.c.$tr_tk"]}
            fi

            x_get_node_type "$1" "$tr_child_id" ; tr_node_kind=$?
            local tr_key="${tr_t["$tr_child_id.k"]}"
            [[ -n "$tr_key" ]] && tr_value=${tr_t["$tr_key"]} || tr_value=''

            # There are special cases here. Empty arrays and empty
            # objects also return simulated values.
            case "$tr_node_kind" in
            $X_NODE_KIND_OBJ_EMPTY)
                tr_value="$X_VALUE_NULL_OBJ"   ;;
            $X_NODE_KIND_ARR_EMPTY)
                tr_value="$X_VALUE_NULL_ARR"   ;;
            esac

            tr_index_token=$tr_tk
            [[ "${tr_tk:0:1}" == '<' ]] && tr_index_token="[$tr_index]"
            tr_index_full_key="$tr_index_prefix$tr_index_token$X"
            tr_physical_full_key="$tr_physical_prefix$tr_tk$X"

            "${3:-x_cb_print}"  "$tr_node_kind" \
                                "$tr_index_token" \
                                "$tr_index_full_key" \
                                "$tr_value" \
                                "$tr_tk" \
                                "$tr_physical_full_key" \
                                "$tr_child_id" \
                                "$tr_node_id" || return $?

            case "$tr_node_kind" in
            $X_NODE_KIND_OBJ|$X_NODE_KIND_ARR)
                tr_stack+=("$tr_physical_full_key" "$tr_index_full_key" "$tr_child_id")
                ;;
            esac

            ((tr_index++))
        done
    done
    return $X_RET_ENUM_OK
}

#-------------------------------------------------------------------------------

# 纯字典树专用遍历：只处理 {} 对象键，不支持 [] / <>。
# 与 x_walk 的回调签名一致（8 个参数），但跳过了 x_get_node_type 和索引路径计算。
# @in  $1=树名  $2=起始物理全 key（空=根）  $3=回调函数名（默认 x_cb_print）
# @ret 0=OK  其他=回调返回的非 0 值
x_walk_dict_tree ()
{
    local -n tr_t=$1
    # local tr_prefix=$2
    # local tr_cb=${3:-x_cb_print}

    local tr_root_id=$X_ROOT_ID tr_root_path=''
    if [[ -n "$2" ]] ; then
        local -A w_x_walk_dict_tree__ninfo=()
        _x_token_to_node_id w_x_walk_dict_tree__ninfo \
                            "$1" "$2" 1 || return $?
        tr_root_id=${w_x_walk_dict_tree__ninfo[node_id]}
        tr_root_path=${w_x_walk_dict_tree__ninfo[physical_full_key]}
    fi

    local -a tr_stack_ids=("$tr_root_id") tr_stack_paths=("$tr_root_path")
    local tr_node_id tr_node_path tr_tk tr_child_id tr_child_path tr_kind tr_value tr_child_key

    while ((${#tr_stack_ids[@]})) ; do
        tr_node_id=${tr_stack_ids[-1]} tr_node_path=${tr_stack_paths[-1]}
        unset -v 'tr_stack_ids[-1]' 'tr_stack_paths[-1]'

        local -a "tr_children=(${tr_t[$tr_node_id.s]})"
        for tr_tk in "${tr_children[@]}" ; do
            tr_child_id=${tr_t["$tr_node_id.c.$tr_tk"]}
            [[ -n "$tr_child_id" ]] || continue

            tr_child_path="$tr_node_path$tr_tk$X" tr_value=
            if [[ ${tr_t[$tr_child_id.k]+_} ]] ; then
                tr_child_key=${tr_t["$tr_child_id.k"]} \
                tr_value=${tr_t["$tr_child_key"]}
                if [[ "$tr_value" == "$X_VALUE_NULL" ]] ; then
                    tr_kind=$X_NODE_KIND_LEAF_NULL
                else
                    tr_kind=$X_NODE_KIND_LEAF
                fi
            elif [[ "${tr_t[$tr_child_id.t]}" == "$X_TYPE_OBJ" ]] ; then
                if [[ -n "${tr_t[$tr_child_id.s]}" ]] ; then
                    tr_kind=$X_NODE_KIND_OBJ
                else
                    tr_kind=$X_NODE_KIND_OBJ_EMPTY \
                    tr_value=$X_VALUE_NULL_OBJ
                fi
            elif [[ "${tr_t[$tr_child_id.t]}" == "$X_TYPE_ARR" ]] ; then
                die ERR "x_walk_dict_tree: array node is not supported (path:${tr_child_path@Q})"
                return $X_RET_ENUM_KEY_IS_INVALID
            else
                die ERR "x_walk_dict_tree: unknown node kind (path:${tr_child_path@Q})"
                return $X_RET_ENUM_KEY_IS_INVALID
            fi

            "${3:-x_cb_print}" "$tr_kind" "$tr_tk" "$tr_child_path" "$tr_value" \
                     "$tr_tk" "$tr_child_path" "$tr_child_id" "$tr_node_id" || return $?

            [[ "$tr_kind" == "$X_NODE_KIND_OBJ" ]] && {
                tr_stack_ids+=("$tr_child_id") tr_stack_paths+=("$tr_child_path")
            }
        done
    done
    return $X_RET_ENUM_OK
}

#-------------------------------------------------------------------------------
# t1(1) -> 
#     0(2)
#         {aa ge}(4) => value2
#         {b}(3) => value1
#     1(5)
#         {c2}(8) => []
#         {c8}(14) => strwxx
#         {c7}(13) => false\u001c
#         { gge
#         | gege g
#         |ggegg geg\t\t\u0002\u0003\u0004ge我是中文}(6) =>
#                                                          | 响铃 geg
#                                                          | gg  ee\u0001\u0002\u0003\u0004\u0005\u0006\u0007\b\t
#                                                          |\u000b\f\r\u000e\u000f\u0010\u0011\u0012\u0013\u0014\u0015\u0016\u0017\u0018\u0019\u001a\u001b\u001c\u001d\u001e\u001f ;over
#         {
#         |key
#         |}(21) => value_line1
#                  |value_line2
#         {c6}(12) => true\u001c
#         {c5*[]@!{}}(11) => 190.23*[]@!{}
#         {c3}(9) => null\u001c
#         {c4}(10) => 190.22\u001c
#         {c1}(7) => {}
#         {
#         | ge中各
#         | ge\\g
#         |}(15)
#             0(16) = null
#             1(17) =
#                    |gege
#                    |gege
#                    |
#             2(18) = true\u001c
#             3(19) = 1010\u001c
#             4(20) = 1010.22
#             5(22) = gegege
#     2(23)
#         {x}(24) => value3
#     3(25)
#         {y}(26) => value4
#     4(27)
#         {z}(28) => value5
#     5(29)
#         0(30) = null\u001c
#         1(31) = null\u001c
#         2(32) = null\u001c
#         3(33) = value5
#     6(34)
#         {key1ggggggggg}(35)
#             {keeeeeeeey2}(36) => valueX
#     max_index => 37
#
#
#   实现的时候可以定义很多个数组，每个数组下标都是行号，内容放置每行的属性。
#
#   1. 初始化
#       针对每行做清洗，满足下面条件的行先干掉
#           a. 所有空行和全是空字符(空格\r\n)的行
#           b. 所有的注释行(不含空格缩进的情况下的 # 开头的行)
#   2. 按照第一行的缩进前置空格数，删除每一行的前面的这么多的空格，保持树缩进干净
#   3. 删除最后一个 max_index 的行
#   4. 当前的字符串做这样的替换
#       `$'\n'   |` 替换成 `'\n'`
#       这里解释下，可能需要多行替换模式，要考虑下怎么才能实现。大概意思就是
#       `$'\n'` 这个真正的换行符换行后跟上若干个空格然后跟一个`|`竖线，这种东西替换
#       成 `'\n'` 转义。
#       这样所有的行都是单行的了。
#   5. 初始化3个容器，一个是 tr_path_stack，一个是 tr_leafs，一个是 tr_array_indexs
#       a. tr_path_stack 初始化一个元素为 ""，空字符串，代表根节点的路径，一旦遇到树节点，就把当前树
#           节点压进去，如果树节点层级减少，就从尾部弹出相应层级的节点 token.
#       b. tr_leafs 里面装当前扁平层的叶子节点键和值元组，如果是数组，键就是索引，
#           结构是(0 element1 1 element2)。如果是字典，键就是字典的键，结构是
#           (key1 value1 key2 value2)。
#       c. tr_array_indexs 里面存的是每级数组当前索引最大值，键是每个数组层级的 full_key
#           比如: 
#               t1(1) -> 
#                   0(2)           <--------- A(缓存 "" = 1)
#                       {aa ge}(4) => value2
#                       {b}(3) => value1
#                   1(5)           <--------- B(缓存 "" = 2)
#                       {c1}(7) => {}
#                       {key1}(15)
#                           0(16) = null    <---------- C(缓存 ""[1]$X{key1}$X = 1)
#                           1(18) = true\u001c   <------- D(缓存 ""[1]$X{key1}$X = 2)
#                           2(19)  <------- E(缓存 ""[1]$X{key1}$X = 3)
#                               0(58) <------- F(缓存 ""[1]$X{key1}$X[2]$X = 1)
#                                   {other_key}(69) => value1
#                   2(29)   <------  G(缓存 "" = 3)
#                       0(30) = null\u001c <-------  H(缓存 ""[2]$X = 1)
#                       1(31) = null\u001c <-------  I(缓存 ""[2]$X = 2)
#                   3(89) = xxvalue        <-------  J(缓存 "" = 4)
#           就上面这棵树来说，只要遇到数组键，那么都要缓存它的当前最大索引。
#           这样下次遍历到它的时候直接从缓存中取索引，如果发现缓存不存在，那么证明是第一次遇到
#           这个数组，索引为0。
#   6. 缓存每一行的缩进层级，以备后面方便使用。下面的情况中，空字典和空数组都属于叶子，不是树，记住这个约定。
#       为了方便处理，其它的信息也可以用数组来缓存，每个数组缓存一个属性，比如：当前的键和值，当前的节点类
#       型：字典树、数组树、键、值。
#   7. 从第二行开始读行，策略是这样的：
#       a. 如果当前行不是`{`开头(忽略前置空格)，那么证明是数组。
#           1). 如果索引后面紧跟着 = ，那么是叶子节点，把叶子索引和值推进 tr_leafs 数组
#               数组中的格式是 (0 element1 1 element2)，数组的索引从 tr_array_indexs 缓存中拿，
#               索引的键 = tr_path_stack 中前 level 个元素（含根哨兵 ""，跳过它拼接） + $X。
#               如果找不到缓存，证明是第一次，那么索引为0。缓存取完后记得让缓存计数增加1。
#               tr_path_stack 更新变成 前 level 个元素。
#               推入后判断是否触发 x_qinserts 写叶子的条件是三个。
#               1>. (J)已经没有下一行
#               2>. (I)下层的缩进层级发生改变(这里只可能减少，不可能增加！)
#               3>. (E)下层是树节点(不管是字典树还是数组树都一样)
#               使用 x_qinserts 把 tr_path_stack(剪枝后的) 和 tr_leafs 所有叶子节点处理掉，
#               然后清空 tr_leafs 数组。
#           2). 如果索引后面没有 = 标识，证明当前节点是数组树节点，那么需要做如下处理(长树枝和砍树枝)。
#               1>. 长树枝(F)：如果当前的缩进层级比 tr_path_stack 多(大于等于它的数量)，先用 tr_path_stack 从缓存中拿索引，
#                   拿不到就用0，拿完后更新缓存的最大索引，把当前拿到的索引压入 tr_path_stack 中。
#               2>. 砍树枝(G)：如果当前的缩进层级比 tr_path_stack 少(小于它的数量)，那么弹出数组中
#                   多出来的元素，使用剩余的键取 tr_array_indexs 索引缓存，并且更新索引缓存，再把当前的键压入
#                   tr_path_stack 中。
#       b. 如果当前行是`{`开头(忽略前置空格)，那么证明是字典。
#          第一件事情是获取真实的字典的键。先取第一个 { 字符，然后从这个字符开始往后扫描，
#          遇到 `\` 就放行后面的那个字符。直到遇到裸的 `}` 字符，我们取到的字典的键。如果这个键后面
#          有 ` =>` 标识，标识当前是字典叶子；如果没有标识，证明是字典树。针对树和叶子，分别按照下面来
#          处理。
#           1). 如果是字典叶子：把叶子的键和值推进 tr_leafs 数组，数组中的格式是
#               (key1 value1 key2 value2)，字典的键 = 解析出的原始 key 经 str_unescape 还原，
#               token 为 {key}$X。tr_path_stack 更新为前 level 个元素（和数组叶子同一个砍树枝动作，
#               叶子不压新 token）。字典不涉及 tr_array_indexs 缓存，不取索引、不更新缓存。推入后判
#               断是否触发 x_qinserts 写叶子的条件是三个：
#               1>. 已经没有下一行
#               2>. 下层缩进层级发生改变(这里只可能减少，不可能增加！)
#               3>. 下层是树节点(不管是字典树还是数组树都一样)
#              使用 x_qinserts 把 tr_path_stack(剪枝后的) 和 tr_leafs 所有叶子节点处理掉，
#              然后清空 tr_leafs 数组。
#           2). 如果是字典树，证明当前节点是字典树节点，那么需要根据是长树枝还是砍树枝做下面的处理。
#               1>. 长树枝：如果当前的缩进层级比 tr_path_stack 多(大于等于它的数量)，那么直接把当前树
#                  节点压进去即可。
#               2>. 砍树枝：如果当前的缩进层级比 tr_path_stack 少(小于它的数量)，那么弹出数组中
#                  多出来的元素，然后把当前键压入进去。
#   具体流程详解：
#
#               t1(1) -> 
#                  0(2)           <--------- A(缓存 "" = 1)
#                      {aa ge}(4) => value2
#                      {b}(3) => value1          <------------ M
#                  1(5)           <--------- B(缓存 "" = 2)
#                      {c1}(7) => {}
#                      {key1}(15)
#                          0(16) = null    <---------- C(缓存 ""[1]$X{key1}$X = 1)
#                          1(18) = true\u001c   <------- D(缓存 ""[1]$X{key1}$X = 2)
#                          2(19)  <------- E(缓存 ""[1]$X{key1}$X = 3)
#                              0(58) <------- F(缓存 ""[1]$X{key1}$X[2]$X = 1)
#                                  {other_key}(69) => value1
#                  2(29)   <------  G(缓存 "" = 3)
#                      0(30) = null\u001c <-------  H(缓存 ""[2]$X = 1)
#                      1(31) = null\u001c <-------  I(缓存 ""[2]$X = 2)
#                  3(89) = xxvalue        <-------  J(缓存 "" = 4)
#               E 处理前：path_stack = ["", "[1]", "{key1}"] , max_index = 2     路径缓存是三层
#               E 走长树枝：我们的缩进也是三层，直接压 E 的 token → ["", "[1]", "{key1}", "[2]"]
#               然后父节点 "" -> [1] -> {key1}, max_index = 3
#               
#               F 处理时：level = 4，max_index = 空    level4 = 缩进4 长树枝 ✓
#               F 处理前：path_stack = ["", "[1], "{key1}", "[2]"], max_index = 0(空)
#               F 走长树枝：取缓存拿索引，["", "[1]", "{key1}", "[2]"] 一定是拿不到的！这个成立，所以索引为 0
#                   并且写入 缓存 ["", "[1]", "{key1}", "[2]"] , max_index = 1
#                   压入 path_stack ["", "[1]", "{key1}", "[2]", "[0]"]
#               
#               G 处理时：level = 1, path_stack = ["", "[1]", "{key1}", "[2]", "[0]"], level5 > 缩进 1
#               G 处理前：path_stack = ["", "[1]", "{key1}", "2", "[0]"]
#               G 走砍树枝：
#                   实际的弹出步骤应该是这样：
#                       先弹出 "1", "{key1}", "2", "[0]"，剩下的路径 "" 取它的 tr_array_indexs 为 2，
#                       并且更新剩下的路径(这里是 "")的 tr_array_indexs 为3.
#                       然后，把新的路径索引压进去 path_stack = ["", "[2]"]。并且更新 tr_array_indexs 的 [""] 键 为 3.
#               
#               
#               
#               t1(1) -> 
#                  {key1}
#                      {aa ge}(4) => value2
#                      {b}(3) => value1
#                  {key2} <------------- A
#                      {c1}(7) => {}
#                      {key1}(15)
#               
#               A 处理时：level = 1, path_stack = ["", "{key1}"]，砍树枝，弹出 "{key1}"，压入我们的 "{key2}".
_x_rebuild_from_dump_get_dict_kv ()
{
    # key 结束位置 = 第一个未转义的 '}'。
    # 绝大多数行没有转义：直接两次参数展开（去 '{' 前缀、截到第一个 '}'），
    # 避免逐字符切片；只有 key 里出现 '\' 时才走慢路径逐字符扫描。
    local tr_rest=${tr_dump_list[tr_i]} tr_out= tr_after_key tr_rest_after='' tr_ch
    tr_after_key=${tr_rest#*'{'} tr_out=${tr_after_key%%'}'*}
    if [[ "$tr_out" == *\\* ]] ; then
        # 慢路径：key 里有转义，逐字符找第一个未转义的 '}'
        local -i tr_begin=-1 tr_pos=0 tr_len=${#tr_rest} tr_end=-1
        while ((tr_pos < tr_len)) ; do
            tr_ch=${tr_rest:tr_pos:1}
            ((tr_pos++))
            if ((tr_begin < 0)) ; then
                [[ "$tr_ch" == '{' ]] && tr_begin=$tr_pos
                continue
            fi
            if [[ "$tr_ch" == '\' ]] ; then
                ((tr_pos++))
                continue
            fi
            [[ "$tr_ch" == '}' ]] && { tr_end=$((tr_pos-1)) ; break ; }
        done
        if ((tr_begin < 0)) ; then
            tr_out=''
            tr_rest_after=$tr_rest
        else
            ((tr_end < 0)) && tr_end=$tr_len
            tr_out=${tr_rest:tr_begin:tr_end-tr_begin}
            tr_rest_after=${tr_rest:tr_end+1}
        fi
    elif [[ "$tr_after_key" == *'}'* ]] ; then
        tr_rest_after=${tr_after_key#*'}'}
    fi

    if [[ "$tr_out" == *\\* ]] ; then
        str_unescape "$tr_out" ; tr_out=$REPLY REPLY=
    fi

    tr_key[tr_i]="{$tr_out}$X"

    # 函数如果返回 0 表示有值(是叶子字典)
    # 函数如果返回 1 表示无值(是字典树)
    # 函数如果返回 2 表示格式错误（调用方必须中止重建，不能降级成树）
    if [[ "$tr_rest_after" == *'=>'* ]] ; then
        # 规范：=> 后必须跟一个空格（语法空格）
        [[ "$tr_rest_after" == *'=> '* ]] || {
            die ERR "template line has '=>' without trailing space: ${tr_dump_list[tr_i]@Q}"
            return 2
        }

        # 把值写了
        tr_out=${tr_rest_after#*'=> '}
        if [[ "$tr_out" == *\\* ]] ; then
            str_unescape "$tr_out" ; tr_out=$REPLY REPLY=
        fi
        tr_value[tr_i]=$tr_out
        return 0
    else
        return 1
    fi
}

_x_rebuild_from_dump_get_array ()
{
    # 数组的 key 在这里没有意义，我们只返回值
    # 函数如果返回 0 表示有值(是叶子数组)
    # 函数如果返回 1 表示无值(是数组树)

    local tr_out=${tr_dump_list[tr_i]}
    if [[ "$tr_out" == *'='* ]] ; then
        tr_out=${tr_out#*'= '}
        if [[ "$tr_out" == *\\* ]] ; then
            str_unescape "$tr_out" ; tr_out=$REPLY REPLY=
        fi
        tr_value[tr_i]=$tr_out
        return 0
    else
        return 1
    fi
}

# 从 dump 重建树，结果直接写入调用方关联数组。
# @in  $1=输出关联数组名（调用方先声明 local -A / declare -gA）
#      $2=dump 字符串
# @out $1=重建后的树
# @ret 0=OK  其他=透传内部错误
x_rebuild_from_dump ()
{
    local -n tr_w_tree=$1 ; tr_w_tree=()
    local tr_dump_str=$2 tr_line tr_line1_indent= tr_line1_enter=0
    local -a tr_dump_list=() tr_raw_lines=()
    mapfile -t tr_raw_lines <<< "$tr_dump_str"
    for tr_line in "${tr_raw_lines[@]}" ; do
        [[ $tr_line == *[![:space:]]* ]] || continue
        # 注释行：去掉前导空白后以 # 开头
        local tr_nonws=${tr_line#"${tr_line%%[![:space:]]*}"}
        [[ $tr_nonws == '#'* ]] && continue

        ((tr_line1_enter)) || {
            tr_line1_indent=${tr_line%%[! ]*}
            tr_line1_enter=1
        }
        tr_dump_list[${#tr_dump_list[@]}]="${tr_line#$tr_line1_indent}"
    done

    # 如果数组的最后一个元素是 max_index => 那么剔除它
    if [[ "${tr_dump_list[-1]//[[:space:]]/}" == max_index* ]] ; then
        unset -v 'tr_dump_list[-1]'
    fi

    # 通过 tr_dump_list[1] 的前置空格和 tr_dump_list[0] 的前置空格来判断当前的
    # 缩进空格数

    local tr_indent=${tr_dump_list[1]%%[! ]*}
    local tr_indent_cnt=${#tr_indent}

    # 先处理空字典和空列表
    # 注意：只有两行也可能是“根节点下只有一个叶子”，不能把 len==2
    # 一律当成空容器；不匹配时继续走正常解析。
    if ((${#tr_dump_list[@]}==2)) ; then
        case "${tr_dump_list[1]}" in
        *${X_VALUE_NULL_OBJ})
            x_init "$1" "$X_TYPE_OBJ" ; return ${X_RET_ENUM_OK}
        ;;
        *${X_VALUE_NULL_ARR})
            x_init "$1" "$X_TYPE_ARR" ; return ${X_RET_ENUM_OK}
        ;;
        esac
    fi

    # 多行字符串变单行字符串
    # [[ ]] 中 extglob 自 4.1 起默认可用；但下面的 pattern 在参数替换里，
    # 参数替换的 extglob 仍需要 shopt -s extglob。
    if [[ $tr_dump_str == *'|'* ]]; then
        local tr_ifs_was_set=${IFS+x} tr_old_ifs=${IFS-}
        local IFS=$'\n'
        tr_dump_str=${tr_dump_list[*]}
        if [[ -n "$tr_ifs_was_set" ]] ; then
            IFS=$tr_old_ifs
        else
            unset -v IFS
        fi
        local tr_extglob=0
        shopt -q extglob || { shopt -s extglob ; tr_extglob=1 ; }
        tr_dump_str=${tr_dump_str//$'\n'*( )|/'\n'}
        ((tr_extglob)) && shopt -u extglob
        mapfile -t tr_dump_list <<<"$tr_dump_str"
    fi

    local -a tr_path_stack=("$X") tr_leafs=() tr_qinfo=()
    local -A tr_array_indexs=()
    # tr_type
    #   a_tree 数组树
    #   d_tree 字典树
    #   a_leaf 数组叶子
    #   d_leaf 字典叶子
    local -a tr_lev=() tr_type=() tr_key=() tr_value=()

    local tr_i tr_ret
    for ((tr_i=1;tr_i<${#tr_dump_list[@]};tr_i++)) ; do
        tr_indent=${tr_dump_list[tr_i]%%[! ]*}
        tr_lev[tr_i]=$((${#tr_indent}/tr_indent_cnt))
        # if [[ "${tr_dump_list[tr_i]}" == *( )'{'* ]] ; then
        if [[ "${tr_dump_list[tr_i]:${#tr_indent}:1}" == '{' ]] ; then
            # 字典
            _x_rebuild_from_dump_get_dict_kv ; tr_ret=$?
            (( tr_ret > 1 )) && return $X_RET_ENUM_TREE_IS_INVALID
            if [[ "$tr_ret" == '0' ]] ; then
                tr_type[tr_i]=d_leaf
            else
                tr_type[tr_i]=d_tree
            fi
        else
            _x_rebuild_from_dump_get_array ; tr_ret=$?
            if [[ "$tr_ret" == '0' ]] ; then
                tr_type[tr_i]=a_leaf
            else
                tr_type[tr_i]=a_tree
            fi
        fi
    done

    # 先创建根节点
    if [[   "${tr_type[1]}" == a_leaf ||
            "${tr_type[1]}" == a_tree ]] ; then
        x_init "$1" "$X_TYPE_ARR"
    else
        x_init "$1" "$X_TYPE_OBJ"
    fi

    # local i
    # for ((i=1;i<${#tr_dump_list[@]}; i++)) ; do
    #     echo "i:$i lev:${tr_lev[i]} type:${tr_type[i]} k:${tr_key[i]} v:${tr_value[i]}"
    # done
    # return 0

    # 开始处理
    local tr_idx tr_idx_key tr_n_lev
    for (( tr_i=1;tr_i<${#tr_dump_list[@]};tr_i++ )) ; do
        tr_n_lev=${tr_lev[tr_i]}
        case "${tr_type[tr_i]}" in
        a_leaf)
            if ((tr_n_lev<${#tr_path_stack[@]})) ; then
                tr_path_stack=("${tr_path_stack[@]:0:tr_n_lev}")
            fi
            printf -v tr_idx_key "%s" "${tr_path_stack[@]}"
            tr_idx=${tr_array_indexs[$tr_idx_key]:-0}
            tr_array_indexs[$tr_idx_key]=$((tr_idx+1))
            tr_leafs+=("[$tr_idx]$X" "${tr_value[tr_i]}")

            # 判断是否触发写叶子
            if ((tr_i+1==${#tr_dump_list[@]})) ||
                [[ "$tr_n_lev" != "${tr_lev[tr_i+1]}" ]] ||
                [[ "${tr_type[tr_i+1]}" == [ad]_tree ]] ; then
                x_qinserts "$1" common:tr_qinfo \
                    "${tr_idx_key#$X}" "${tr_leafs[@]}" || return $?
                # 清空叶子缓存
                tr_leafs=()
            fi
        ;;
        d_leaf)
            if ((tr_n_lev<${#tr_path_stack[@]})) ; then
                tr_path_stack=("${tr_path_stack[@]:0:tr_n_lev}")
            fi
            printf -v tr_idx_key "%s" "${tr_path_stack[@]}"
            tr_leafs+=("${tr_key[tr_i]}" "${tr_value[tr_i]}")
            # 判断是否触发写叶子
            if ((tr_i+1==${#tr_dump_list[@]})) ||
                [[ "$tr_n_lev" != "${tr_lev[tr_i+1]}" ]] ||
                [[ "${tr_type[tr_i+1]}" == [ad]_tree ]] ; then
                x_qinserts "$1" common:tr_qinfo \
                    "${tr_idx_key#$X}" "${tr_leafs[@]}" || return $?
                # 清空叶子缓存
                tr_leafs=()
            fi
        ;;
        a_tree)
            if ((tr_n_lev<${#tr_path_stack[@]})) ; then
                tr_path_stack=("${tr_path_stack[@]:0:tr_n_lev}")
            fi
            printf -v tr_idx_key "%s" "${tr_path_stack[@]}"
            tr_idx=${tr_array_indexs[$tr_idx_key]:-0}
            tr_array_indexs[$tr_idx_key]=$((tr_idx+1))
            tr_path_stack+=("[$tr_idx]$X")
        ;;
        d_tree)
            if ((tr_n_lev<${#tr_path_stack[@]})) ; then
                tr_path_stack=("${tr_path_stack[@]:0:tr_n_lev}")
            fi
            tr_path_stack+=("${tr_key[tr_i]}")
        ;;
        esac
    done

    return $X_RET_ENUM_OK
}

return 0

