((_TRIE_IMPORTED++)) && return 0

. "${BASH_SOURCE[0]%/*}/array.sh"
. "${BASH_SOURCE[0]%/*}/var.sh"
. "${BASH_SOURCE[0]%/*}/str.sh"
. "${BASH_SOURCE[0]%/*}/meta.sh"

# ================================================================================
# Importantly, if you want to save trie data, it is recommended to directly
# serialize it into JSON standard format(trie_to_json), and then convert JSON
# into trie(trie_from_json) before use. Because the implementation details inside
# the tree may change, If directly `declare -p tree` saves it to a file and reuses
# it through the source method. If the implementation details of the tree change,
# it will cause failure.
# All variable names in the library start with tr_.
# Be careful to avoid external variables.
# tr_
# ================================================================================



#-------------------------------------------------------------------------------

# If you want more powerful anti-collision capabilities, you can set it as follows
# But usually $'\034' is enough.
# Be careful not to change this value casually, as it may affect the re-import of the variable.
# The semantics will change after importing
# readonly X=$'\034\035\036\037'
readonly X=$'\034'
readonly TR_ROOT_ID=1

readonly TR_RET_ENUM_OK=0

readonly TR_RET_ENUM_KEY_IS_TREE=1
readonly TR_RET_ENUM_KEY_IS_LEAF=2
readonly TR_RET_ENUM_KEY_IS_NOTFOUND=3
readonly TR_RET_ENUM_KEY_IS_INVALID=4
readonly TR_RET_ENUM_KEY_OUT_OF_INDEX=5
readonly TR_RET_ENUM_KEY_IS_NOT_LEAF=6
readonly TR_RET_ENUM_KEY_IS_NULL=7
readonly TR_RET_ENUM_KEY_UP_LEV_TYPE_MISMATCH=8
readonly TR_RET_ENUM_KEY_CHILD_CNT_IS_ZERO=9
readonly TR_RET_ENUM_KEY_OTHER_TOOL_NOT_INSTALLED=10
readonly TR_RET_ENUM_KEY_BJSON_TYPE_INVALID=11
readonly TR_RET_ENUM_KEY_BJSON_TYPE_OBJ=12
readonly TR_RET_ENUM_KEY_BJSON_TYPE_ARR=13
readonly TR_RET_ENUM_KEY_PARAMETER_LENGTH_EXCEEDS_LIMIT=14

readonly TR_RET_ENUM_TREE_IS_INVALID=50
readonly TR_RET_ENUM_TREE_IS_EMPTY=51
readonly TR_RET_ENUM_TREE_NOT_HAVE_ROOT=52
readonly TR_RET_ENUM_TREE_IS_NOT_SAME=53

# type field (dedicated to container identification)
readonly TR_TYPE_OBJ=1
readonly TR_TYPE_ARR=2

# Node type (walk-specific)
readonly TR_NODE_KIND_OBJ=1
readonly TR_NODE_KIND_ARR=2
readonly TR_NODE_KIND_OBJ_EMPTY=3
readonly TR_NODE_KIND_ARR_EMPTY=4
readonly TR_NODE_KIND_LEAF=5
readonly TR_NODE_KIND_LEAF_NULL=6
readonly TR_NODE_KIND_UNKNOWN=7

# Value types (only for writing and printing)
readonly TR_VALUE_NULL="null$X"
readonly TR_VALUE_TRUE="true$X"
readonly TR_VALUE_FALSE="false$X"
readonly TR_VALUE_NULL_OBJ="{}$X"
readonly TR_VALUE_NULL_ARR="[]$X"

# Flat layer judgment
readonly TR_FLAT_IS_MATCH=0
readonly TR_FLAT_IS_NOT_MATCH=1
readonly TR_FLAT_ARRAY_NULL=2
readonly TR_FLAT_ASSOC_NULL=3

# gobolt JSON Object type return value
readonly TR_GOBOLT_JSONTYPENULL=1
readonly TR_GOBOLT_JSONTYPETRUE=2
readonly TR_GOBOLT_JSONTYPEFALSE=3
readonly TR_GOBOLT_JSONTYPENUMBER=4
readonly TR_GOBOLT_JSONTYPESTRING=5
readonly TR_GOBOLT_JSONTYPEARRAY=6
readonly TR_GOBOLT_JSONTYPEOBJECT=7
readonly TR_GOBOLT_JSONTYPEUNKNOWN=8

#-------------------------------------------------------------------------------

# $1: The value of the string that needs to be converted
# $2: Variable name saved after conversion
trie_bjson_key_escape ()
{
    local -n bjsonKeyEscapeR_ekey="$2"

    bjsonKeyEscapeR_ekey="$1"

    if ((${#bjsonKeyEscapeR_ekey}>6666)) ; then
        bjsonKeyEscapeR_ekey=$(printf "%s" "$bjsonKeyEscapeR_ekey" | gobolt json -m e -k stdin)
        bjsonKeyEscapeR_ekey=${bjsonKeyEscapeR_ekey%?}
    else
        local bjsonKeyEscapeR_is_patsub_replacement_on=0
        shopt -q patsub_replacement || {
            shopt -s patsub_replacement
            bjsonKeyEscapeR_is_patsub_replacement_on=1
        }

        # 5.2 patsub_replacement
        bjsonKeyEscapeR_ekey=${bjsonKeyEscapeR_ekey//[$'][\\.*?|@#{}!']/\\&}
        ((bjsonKeyEscapeR_is_patsub_replacement_on)) && shopt -u patsub_replacement
    fi
}

#-------------------------------------------------------------------------------

_split_tokens ()
{
    local tokens_str=$1
    local is_insertion_semantics=${2:-0}
    local -a tokens=()
    local token

    while [[ -n "$tokens_str" ]] ; do
        token=${tokens_str%%"$X"*}
        ((${#token}<=2)) && return $TR_RET_ENUM_KEY_IS_INVALID
        case "${token:0:1}${token: -1}" in
        '()')
            # Must have insertion semantics and must be a positive integer
            ((is_insertion_semantics)) || {
                die "now are not in insertion semantics. key:$1 is invalid!"
                return $TR_RET_ENUM_KEY_IS_INVALID
            }
            str_is_decimal_positive_int "${token:1:-1}" || {
                die "key:$1 is invalid!"
                return $TR_RET_ENUM_KEY_IS_INVALID
            }
            ;;
        '[]')
            str_is_decimal_int "${token:1:-1}" || {
                die "key:$1 is invalid!"
                return $TR_RET_ENUM_KEY_IS_INVALID
            }
            ;;
        '{}'|'<>')  : ;;
        *)  die "key:$1 is invalid!"
            return $TR_RET_ENUM_KEY_IS_INVALID
            ;;
        esac
        tokens+=("$token")

        tokens_str="${tokens_str#*"$X"}"
    done
    
    REPLY="${tokens[*]@Q}"
    return $TR_RET_ENUM_OK
}

#-------------------------------------------------------------------------------

# index -> physical
tr_resolve_index_token ()
{
    local -n tr_t=$1
    local tr_token=$2 tr_node=$3
    if [[ "${tr_token:0:1}${tr_token: -1}" == '[]' ]] ; then
        local -a "tr_child_ids=(${tr_t[$tr_node.children]})"
        tr_token=${|_negative_token_to_positive "$tr_token" "${#tr_child_ids[@]}" "$tr_node";} || return $?
        tr_token=${tr_child_ids[${tr_token:1:-1}]}
    fi
    REPLY="$tr_token"
}

#-------------------------------------------------------------------------------

# physical -> index
tr_resolve_physical_token ()
{
    local -n tr_t=$1
    local tr_token=$2 tr_node=$3

    if [[ "${tr_token:0:1}${tr_token: -1}" == '<>' ]] ; then
        local -a "tr_child_ids=(${tr_t[$tr_node.children]})"
        local -i tr_index=${|array_index "${tr_token}" ${tr_child_ids[@]};}
        ((tr_index==-1)) && {
            die "node:${tr_node}(token:${tr_token}) can not find index."
            return $TR_RET_ENUM_KEY_IS_INVALID
        }
        tr_token="[$tr_index]"
    fi
    REPLY="$tr_token"
}

#-------------------------------------------------------------------------------

# Convert negative index of array to positive index
# a=(1 2 3 4) index=-1 -> index=3
#                         index=(($len+index))
_negative_token_to_positive ()
{
    local tr_token=$1 tr_array_len=$2 tr_node=$3
    if ((${tr_token:1:-1}<0)) ; then
        local -i tr_token_abs=${tr_token:1:-1}
        ((tr_token_abs=-tr_token_abs))
        ((tr_token_abs>tr_array_len)) && {
            die "node:${tr_node}(token:${tr_token}) index:${tr_token:1:-1} is out of index."
            return $TR_RET_ENUM_KEY_OUT_OF_INDEX
        }
        ((tr_token_abs=tr_array_len-tr_token_abs))
        REPLY="${tr_token:0:1}$tr_token_abs${tr_token: -1}"
    else
        REPLY="$tr_token"
    fi
    return $TR_RET_ENUM_OK
}

#-------------------------------------------------------------------------------

trie_init ()
{
    local -A t=()
    # t[$TR_ROOT_ID]=1
    t[$TR_ROOT_ID.type]=${1:-"$TR_TYPE_OBJ"}
    # t[$TR_ROOT_ID.children]=''
    # t[$TR_ROOT_ID.key]=''

    # Next available node ID
    t[max_index]=2
    REPLY=${t[*]@K}
}

#-------------------------------------------------------------------------------

# Verify whether the subtree is a basic trie
_trie_tree_is_valid ()
{
    local -n tr_tree=$1

    [[ "${tr_tree@a}" != *A* ]] && {
        die "invalid tree: $1 is not an associative array!"
        return ${TR_RET_ENUM_TREE_IS_INVALID}
    }

    ((${#tr_tree[@]})) || {
        die "invalid tree: $1 is empty!"
        return ${TR_RET_ENUM_TREE_IS_EMPTY}
    }

    [[ -v tr_tree[$TR_ROOT_ID.type] ]] || {
        die "invalid tree: $1 not have root node!"
        return ${TR_RET_ENUM_TREE_NOT_HAVE_ROOT}
    }

    return ${TR_RET_ENUM_OK}
}

#-------------------------------------------------------------------------------

_tokens_insert_to_overwrite ()
{
    local tokens_str=$1
    [[ -z "$tokens_str" ]] && return $TR_RET_ENUM_OK
    local -a tokens=()
    local token
    while [[ -n "$tokens_str" ]] ; do
        token=${tokens_str%%"$X"*}
        [[ "${token:0:1}" == '(' ]] && token="[${token:1:-1}]"
        tokens+=("$token")
        tokens_str="${tokens_str#*"$X"}"
    done
    printf -v REPLY "%s$X" "${tokens[@]}"
    return $TR_RET_ENUM_OK
}

#-------------------------------------------------------------------------------

# Subtree mount
# Reuse trie_insert, so it is not the most efficient implementation version
# is the simplest implementation
#
# REPLY: (node_id node_phy_path)
trie_graft ()
{
    # local - ; set +x
    local tr_target_name=$1
    # If tr_prefix contains '()', it can only be used for the first time
    local tr_graft_prefix=$2
    local tr_sub_name=$3
    local tr_graft_is_first_insert=1
    local tr_graft_start_token_id=${TR_ROOT_ID}
    local tr_graft_start_path_token=""
    local tr_graft_reply=()

    # 2. Simply check the legality of the subtree
    _trie_tree_is_valid "$3" || return $?

    # 3. Use the trie_walk function to traverse a subtree
    trie_graft_walk_callback ()
    {
        local tr_node_kind=$1
        local tr_index_full_key=$3
        local tr_value=$4
        local tr_prefix=$tr_graft_prefix

        case "$tr_node_kind" in
        $TR_NODE_KIND_LEAF|$TR_NODE_KIND_LEAF_NULL|$TR_NODE_KIND_OBJ_EMPTY|$TR_NODE_KIND_ARR_EMPTY)

            trie_insert "$tr_target_name" \
                        "$tr_prefix$tr_index_full_key" \
                        "$tr_value" \
                        "$tr_graft_start_token_id" \
                        "$tr_graft_start_path_token" || return $?

            if ((tr_graft_is_first_insert)) ; then
                tr_graft_is_first_insert=0
                tr_graft_prefix=${|_tokens_insert_to_overwrite "$tr_graft_prefix";}
                local -A "tr_prefix_token_info=(${|_trie_token_to_node_id "$tr_target_name" "$tr_graft_prefix";})"
                tr_graft_start_token_id=${tr_prefix_token_info[node_id]}
                tr_graft_start_path_token=${tr_prefix_token_info[physical_full_key]}
                tr_graft_prefix=$tr_graft_start_path_token
            fi
            ;;
        esac
        return 0
    }
    
    trie_walk "$tr_sub_name" "" trie_graft_walk_callback || return $?
    tr_graft_reply=("$tr_graft_start_token_id" "$tr_graft_start_path_token")
    REPLY=${tr_graft_reply[*]@Q}
}

#-------------------------------------------------------------------------------

trie_key_is_invalid ()
{
    if [[ "$1" == "$X"* ]] ||
        [[ "$1" == *"$X$X"* ]] ||
        [[ "$1" == "$X" ]] ||
        [[ "$1" != *"$X" ]] ; then
        die "key is null or invalid!"
        return $TR_RET_ENUM_KEY_IS_NULL
    else
        return $TR_RET_ENUM_OK
    fi
}

#-------------------------------------------------------------------------------

# Insert with public prefix
# trie_inserts t1 "{prefix1}$X{prefix2}$X" "[0]$X" "array_value1" \
#                                          "[1]$X" "array_value2" \
#                                          "[2]$X" "array_value3"
trie_qinserts ()
{
    # local - ; set +x
    local tr_t_name=$1
    # leaves or common
    local tr_return_mode=$2
    local tr_common_prefix=$3
    shift 3
    local -a tr_insert_kv=("${@}")
    local tr_insert_info
    local -a tr_qinserts_reply=()

    # If the number of parameters is 1, it means only writing a single value, not a key
    ((${#tr_insert_kv[@]}==1)) && {
        REPLY=${|trie_insert "$tr_t_name" "$tr_common_prefix" "${tr_insert_kv[0]}";}
        return $?
    }

    ((${#tr_insert_kv[@]}<2)) && return $TR_RET_ENUM_OK

    # The first insertion uses the original KEY
    tr_insert_info=${|trie_insert "$tr_t_name" "$tr_common_prefix${tr_insert_kv[0]}" "${tr_insert_kv[1]}";} || return $?
    local -a "tr_insert_info=($tr_insert_info)"
    [[ "$tr_return_mode" == 'leaves' ]] && tr_qinserts_reply+=("${tr_insert_info[@]}")
    

    # The subsequent insertion prefix uses the physical key and brings the node id for acceleration.
    local tr_k_index=2 tr_v_index=3

    tr_common_prefix=${|_tokens_insert_to_overwrite "$tr_common_prefix";}
    local -A "tr_prefix_token_info=(${|_trie_token_to_node_id "$tr_t_name" "$tr_common_prefix";})"
    tr_common_prefix=${tr_prefix_token_info[physical_full_key]}
    local tr_common_id=${tr_prefix_token_info[node_id]}
    [[ "$tr_return_mode" == 'common' ]] && {
        tr_qinserts_reply=("$tr_common_id" "$tr_common_prefix")

        REPLY=${tr_qinserts_reply[*]@Q}
    }

    for((tr_k_index=2,tr_v_index=3;tr_v_index<${#tr_insert_kv[@]};tr_k_index+=2,tr_v_index+=2)) ; do
        tr_insert_info=${|trie_insert "$tr_t_name" \
                                    "${tr_common_prefix}${tr_insert_kv[tr_k_index]}" \
                                    "${tr_insert_kv[tr_v_index]}" \
                                    "$tr_common_id" \
                                    "$tr_common_prefix";} || return $?
        
        local -a "tr_insert_info=($tr_insert_info)"

        [[ "$tr_return_mode" == 'leaves' ]] && tr_qinserts_reply+=("${tr_insert_info[@]}")
    done

    REPLY=${tr_qinserts_reply[*]@Q}
    return $TR_RET_ENUM_OK
}

#-------------------------------------------------------------------------------

# Returns an array of node IDs
trie_inserts ()
{
    # local - ; set +x
    set -- "${@:2}" "$1"
    local tr_insert_info
    local -a tr_inserts_reply=()
    while (($#>1)) ; do
        tr_insert_info=${|trie_insert "${!#}" "$1" "$2";} || return $?
        shift 2
        local -a "tr_insert_info=($tr_insert_info)"

        tr_inserts_reply+=("${tr_insert_info[@]}")
    done
    REPLY=${tr_inserts_reply[*]@Q}
    return $TR_RET_ENUM_OK
}

#-------------------------------------------------------------------------------

# Only insert and do not return any data
# Fast writing of associative arrays that can be used directly for flat layers
# local -A assoc=(['{1 2}']='a b' ['{3 4}']='c d')
# trie_insert_token_dict my_tree '134' '{lev1}' "${assoc[@]@k}"
trie_insert_token_dict ()
{
    local -n tr_t=$1

    local tr_node=$2 tr_preifx=$3
    local -a tr_token_values=("${@:4}")
    local tr_path_key=
    local -a tr_tokens=()
    local -i tr_index=0
    local tr_child_key tr_child_id
    local tr_token tr_value

    for((tr_index=0;tr_index<${#tr_token_values[@]};tr_index+=2)) ; do
        tr_token=${tr_token_values[tr_index]}
        tr_value=${tr_token_values[tr_index+1]}
        tr_path_key=$tr_preifx$tr_token$X

        [[ -v 'tr_t[$tr_path_key]' ]] && {
            tr_t[$tr_path_key]=$tr_value
            continue
        }

        tr_child_id="${tr_t[max_index]}" ; ((tr_t[max_index]++))
        tr_t["$tr_node.child.$tr_token"]=$tr_child_id
        tr_tokens+=("$tr_token")

        case "$tr_value" in
        "$TR_VALUE_NULL_ARR")
            tr_t[$tr_child_id.type]="$TR_TYPE_ARR"
            ;;
        "$TR_VALUE_NULL_OBJ")
            tr_t[$tr_child_id.type]="$TR_TYPE_OBJ"
            ;;
        *)
            tr_t[$tr_child_id.key]=$tr_path_key
            tr_t["$tr_path_key"]=$tr_value
            ;;
        esac
    done
    
    ((${#tr_tokens[@]})) && tr_t[$tr_node.children]+=" ${tr_tokens[*]@Q}"
    return $TR_RET_ENUM_OK
}

#-------------------------------------------------------------------------------

# Only insert and do not return any data
trie_insert_dict ()
{
    local -n tr_t=$1
    local tr_full_key=$2

    local tr_value=$3
    local tr_start_node_id=${4:-"$TR_ROOT_ID"}
    local tr_path_key=${5:-""}

    [[ -v 'tr_t["$tr_full_key"]' ]] && {
        tr_t["$tr_full_key"]=$tr_value
        return ${TR_RET_ENUM_OK}
    }

    local tr_token tr_child_key tr_child_id tr_tokens_str

    # Here tr_full_key needs to remove the tr_path_key prefix and start traversing
    tr_tokens_str=${|_split_tokens "${tr_full_key#"$tr_path_key"}" 1;} || return $?
    local -a "tr_tokens=($tr_tokens_str)"

    local tr_node=${tr_start_node_id}

    for tr_token in "${tr_tokens[@]}" ; do
        tr_child_key="$tr_node.child.$tr_token"
        tr_child_id="${tr_t[$tr_child_key]}"

        # Child node does not exist -> create
        [[ -z "$tr_child_id" ]] && {
            tr_child_id="${tr_t[max_index]}" ; ((tr_t[max_index]++))
            tr_t[$tr_node.children]+=" ${tr_token@Q}"
            tr_t["$tr_child_key"]=$tr_child_id
        }

        tr_node=$tr_child_id
        tr_path_key+="$tr_token$X"
    done

    case "$tr_value" in
    "$TR_VALUE_NULL_ARR")
        tr_t[$tr_node.type]="$TR_TYPE_ARR"
        return $TR_RET_ENUM_OK
        ;;
    "$TR_VALUE_NULL_OBJ")
        tr_t[$tr_node.type]="$TR_TYPE_OBJ"
        return $TR_RET_ENUM_OK
        ;;
    *)
        tr_t[$tr_node.key]=$tr_path_key
        tr_t["$tr_path_key"]=$tr_value
        return $TR_RET_ENUM_OK
    esac
}

#-------------------------------------------------------------------------------

# Returns the inserted node ID, used by external or object tracking systems to track the ID of the object.
trie_insert ()
{
    # local - ; set +x
    local -n tr_t=$1
    local tr_full_key=$2
    local -i tr_array_index=-1
    local -a tr_insert_reply=()

    trie_key_is_invalid "$tr_full_key" || return $?

    local tr_value=$3
    local tr_start_node_id=${4:-"$TR_ROOT_ID"}
    local tr_path_key=${5:-""}

    if [[ -n "$tr_path_key" ]] ; then
        trie_key_is_invalid "$tr_path_key" || return $?

        [[ "$tr_path_key" == *"]$X"* || "$tr_path_key" == *")$X"* ]] && {
            die "path key:${tr_path_key} is not physical key."
            return $TR_RET_ENUM_KEY_IS_INVALID
        }
    fi

    # If it is a leaf node, update the value directly
    if  [[ -v 'tr_t["$tr_full_key"]' ]] &&
        [[ "$tr_value" != "$TR_VALUE_NULL_ARR" ]] &&
        [[ "$tr_value" != "$TR_VALUE_NULL_OBJ" ]] ; then
        tr_t["$tr_full_key"]=$tr_value
        local -A "tr_node_info=(${|_trie_token_to_node_id "$1" "$tr_full_key";})"
        tr_insert_reply=("${tr_node_info[node_id]}" "${tr_node_info[physical_full_key]}")
        REPLY=${tr_insert_reply[*]@Q}
        return ${TR_RET_ENUM_OK}
    fi

    local tr_token tr_child_key tr_child_id tr_tokens_str

    # Here tr_full_key needs to remove the tr_path_key prefix and start traversing
    tr_tokens_str=${tr_full_key#"$tr_path_key"}
    [[ -n "$tr_path_key" && "$tr_tokens_str" == "$tr_full_key" ]] && {
        die "path_key:${tr_path_key} is not part of full key:${tr_full_key}."
        return $TR_RET_ENUM_KEY_IS_INVALID
    }
    tr_tokens_str=${|_split_tokens "$tr_tokens_str" 1;} || return $?
    local -a "tr_tokens=($tr_tokens_str)"

    local tr_node=${tr_start_node_id}

    # Record the ID key of the created intermediate node, all need to be deleted
    local -a tr_tmp_node_ids=()

    _trie_insert_delete_tmp_node_ids ()
    {
        local tr_tmp_node

        for tr_tmp_node in "${tr_tmp_node_ids[@]}" ; do
            unset -v 'tr_t[$tr_tmp_node]'
        done
    }

    for tr_token in "${tr_tokens[@]}" ; do
        local tr_key="${tr_t[$tr_node.key]}"
        local -i tr_array_index=-1
        local tr_token_pack="${tr_token:0:1}${tr_token: -1}"
        case "$tr_token_pack" in
        '{}') 
            # The previous level must be null or obj or nothing (only nodes have tags)
            if [[ "${tr_t[$tr_node.type]}" == "$TR_TYPE_OBJ" ]] ; then
                :
            elif [[ -n "$tr_key" ]] && [[ "${tr_t[$tr_key]}" == "$TR_VALUE_NULL" ]] ; then
                # Become path empty obj
                unset -v 'tr_t[$tr_node.key]'
                unset -v 'tr_t[$tr_key]'
                tr_t[$tr_node.type]=$TR_TYPE_OBJ
            # If tr_node has only node tags, then turn it into empty obj
            elif [[ -v 'tr_t[$tr_node]' ]] &&
                [[ ! -v 'tr_t[$tr_node.key]' ]] &&
                [[ ! -v 'tr_t[$tr_node.children]' ]] &&
                [[ "${tr_t[$tr_node.type]}" != "$TR_TYPE_ARR" ]] ; then
                tr_t[$tr_node.type]=$TR_TYPE_OBJ
            else
                die "node:${tr_node}(token:${tr_token}) is not obj or null."
                _trie_insert_delete_tmp_node_ids
                return $TR_RET_ENUM_KEY_UP_LEV_TYPE_MISMATCH
            fi
            ;;
        '[]'|'()')
            # If the previous layer is null, create an empty array path node.
            if [[ -n "$tr_key" ]] && [[ "${tr_t[$tr_key]}" == "$TR_VALUE_NULL" ]] ; then
                unset -v 'tr_t[$tr_node.key]'
                unset -v 'tr_t[$tr_key]'
                tr_t[$tr_node.type]=$TR_TYPE_ARR
            # Contains only node existence flags
            elif [[ -v 'tr_t[$tr_node]' ]] &&
                [[ ! -v 'tr_t[$tr_node.key]' ]] &&
                [[ ! -v 'tr_t[$tr_node.children]' ]] &&
                [[ "${tr_t[$tr_node.type]}" != "$TR_TYPE_OBJ" ]] ; then
                tr_t[$tr_node.type]=$TR_TYPE_ARR
            fi

            [[ "${tr_t[$tr_node.type]}" != "$TR_TYPE_ARR" ]] && {
                die "node:${tr_node}(token:${tr_token}) up layer is not array or null."
                _trie_insert_delete_tmp_node_ids
                return $TR_RET_ENUM_KEY_UP_LEV_TYPE_MISMATCH
            }

            # Fill incomplete null nodes and update tr_token
            local -a "tr_array=(${tr_t[$tr_node.children]})"
            local -i tr_i tr_array_len=${#tr_array[@]}
            local -a tr_add_token=()
            
            local tr_token_ret
            tr_token=${|_negative_token_to_positive "$tr_token" "$tr_array_len" "$tr_node";} ; tr_token_ret=$?
            ((tr_token_ret)) && {
                _trie_insert_delete_tmp_node_ids
                return $tr_token_ret
            }

            for((tr_i=tr_array_len;tr_i<${tr_token:1:-1};tr_i++)) ; do
                local tr_new_id=${tr_t[max_index]} ; ((tr_t[max_index]++))
                # tr_t[$tr_new_id]=1
                tr_t[$tr_new_id.key]="$tr_path_key<$tr_new_id>$X"
                tr_t["$tr_path_key<$tr_new_id>$X"]="$TR_VALUE_NULL"
                # Attach parent node children
                tr_t["$tr_node.child.<$tr_new_id>"]=$tr_new_id
                tr_add_token+=("<$tr_new_id>")
            done

            tr_array_index=${tr_token:1:-1}

            if ((${#tr_add_token[@]})) ; then
                # Populate the parent node's children list
                tr_array=("${tr_array[@]:0:tr_array_len}" "${tr_add_token[@]}" "${tr_array[@]:tr_array_len}")
                tr_t[$tr_node.children]=${tr_array[*]@Q}
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
            if [[ "${tr_t[$tr_node.type]}" != "$TR_TYPE_ARR" ]] ; then
                die "node:${tr_node}(token:${tr_token}) up layer is not array."
                _trie_insert_delete_tmp_node_ids
                return $TR_RET_ENUM_KEY_UP_LEV_TYPE_MISMATCH
            fi

            if [[ -z "${tr_t[$tr_node.child.$tr_token]}" ]] ; then
                die "node:${tr_node}(token:${tr_token}) is not exist."
                _trie_insert_delete_tmp_node_ids
                return $TR_RET_ENUM_KEY_UP_LEV_TYPE_MISMATCH
            fi
            ;;
        esac
            
        tr_child_key="$tr_node.child.$tr_token"
        tr_child_id="${tr_t[$tr_child_key]}"

        # Child node does not exist -> create
        if [[ -z "$tr_child_id" ]] ; then
            tr_child_id="${tr_t[max_index]}" ; ((tr_t[max_index]++))
            tr_t[$tr_child_id]=1
            tr_tmp_node_ids+=("$tr_child_id")
            # tr_t[$tr_child_id.children]=''
            # tr_t[$tr_child_id.key]=''

            local -a "tr_children=(${tr_t[$tr_node.children]})"
            
            if ((tr_array_index!=-1)) ; then
                if [[ "$tr_token_pack" == '()' ]] ; then
                    tr_children=("${tr_children[@]:0:tr_array_index}" "$tr_token" "${tr_children[@]:tr_array_index}")
                else
                    tr_children[$tr_array_index]="$tr_token"
                fi
            else
                # Descending ASCII lexicographic order
                # array_sorted_insert tr_children "$tr_token" '<'
                tr_children+=("$tr_token")
            fi

            tr_t[$tr_node.children]=${tr_children[*]@Q}
            tr_t["$tr_child_key"]=$tr_child_id
        fi

        tr_node=$tr_child_id
        tr_path_key+="$tr_token$X"
    done

    # Write leaf key
    # Leaf nodes may be empty obj or empty array
    # Leaf nodes are set to provide better coverage.
    # Intermediate nodes are strictly limited. trie_graft also maintain the same semantics.
    # If it is found at the end that there are children at the inserted place,
    # it proves to be an existing structure node,
    # and the leaf is not allowed to be inserted.
    [[ -n "${tr_t[$tr_node.children]}" ]] && {
        die "node:${tr_node}(token:${tr_token}) have children."
        _trie_insert_delete_tmp_node_ids
        return $TR_RET_ENUM_KEY_UP_LEV_TYPE_MISMATCH
    }

    # If it is found at the end that the inserted place is an empty obj or an
    # empty array, but the content to be inserted does not match,
    # an error will be reported.
    if  [[ "${tr_t[$tr_node.type]}" == "$TR_TYPE_OBJ" ]] &&
        [[ "$tr_value" != "$TR_VALUE_NULL_OBJ" ]] ; then
        die "node:${tr_node}(token:${tr_token}) is null obj,but insert is not."
        _trie_insert_delete_tmp_node_ids
        return $TR_RET_ENUM_KEY_UP_LEV_TYPE_MISMATCH
    fi

    if  [[ "${tr_t[$tr_node.type]}" == "$TR_TYPE_ARR" ]] &&
        [[ "$tr_value" != "$TR_VALUE_NULL_ARR" ]] ; then
        die "node:${tr_node}(token:${tr_token}) is null array,but insert is not."
        _trie_insert_delete_tmp_node_ids
        return $TR_RET_ENUM_KEY_UP_LEV_TYPE_MISMATCH
    fi

    local tr_new_type
    case "$tr_value" in
        "$TR_VALUE_NULL_ARR")   tr_new_type="$TR_TYPE_ARR" ;;
        "$TR_VALUE_NULL_OBJ")   tr_new_type="$TR_TYPE_OBJ" ;;
        *)
            tr_t[$tr_node.key]=$tr_path_key
            tr_t["$tr_path_key"]=$tr_value
            # 返回节点 ID
            tr_insert_reply=("$tr_node" "$tr_path_key")
            REPLY=${tr_insert_reply[*]@Q}
            _trie_insert_delete_tmp_node_ids
            return $TR_RET_ENUM_OK
    esac

    # The current leaf strings, values and bool can be overwritten into
    # empty objects and empty arrays.
    # Leaves null are naturally OK
    local tr_key="${tr_t[$tr_node.key]}"
    unset -v 'tr_t[$tr_node.key]'
    [[ -n "$tr_key" ]] && unset -v 'tr_t[$tr_key]'
    tr_t[$tr_node.type]="$tr_new_type"
    tr_insert_reply=("$tr_node" "$tr_path_key")
    REPLY=${tr_insert_reply[*]@Q}
    _trie_insert_delete_tmp_node_ids
    return $TR_RET_ENUM_OK
}

#-------------------------------------------------------------------------------

trie_dump ()
{
    # local - ; set +x
    local tr_t_name=$1
    local -n tr_t=$1
    local tr_full_key=$2
    # bit0: id is need to print
    # bit1: value is need to print
    local tr_indent_cnt=${3:-4}
    local tr_print_mask=${4:-$((2#111))}
    # 0: id 1: value 2: array index
    local tr_id_need_print tr_value_need_print
    local tr_print_array_index
    var_bitmap_unpack   "$tr_print_mask" \
                        "tr_id_need_print:0" \
                        "tr_value_need_print:1" \
                        "tr_print_array_index:2"

    local tr_node tr_node_info
    tr_node_info=${|_trie_token_to_node_id "$tr_t_name" "$tr_full_key";} || return $?
    local -A "tr_node_info=($tr_node_info)"
    tr_node=${tr_node_info[node_id]}

    local tr_indent=${|str_repeat ' ' "$tr_indent_cnt";}

    printf "%s(%s) -> %s\n" "$tr_t_name" "$tr_node" "${tr_node_info[physical_full_key]}"

    [[ "${tr_t[$tr_node.type]}" == "$TR_TYPE_OBJ" ]] &&
    [[ -z "${tr_t[$tr_node.children]}" ]] && {
        printf "${tr_indent}%s\n" "$TR_VALUE_NULL_OBJ"
        return
    }

    [[ "${tr_t[$tr_node.type]}" == "$TR_TYPE_ARR" ]] &&
    [[ -z "${tr_t[$tr_node.children]}" ]] && {
        printf "${tr_indent}%s\n" "$TR_VALUE_NULL_ARR"
        return
    }

    _trie_dump  "$tr_t_name" "$tr_node" "$tr_indent_cnt" "$tr_indent" \
                "$tr_id_need_print" "$tr_value_need_print" \
                "$tr_print_array_index"
    printf "${tr_indent}max_index => %s\n" "${tr_t[max_index]}"
}

#-------------------------------------------------------------------------------

_trie_dump ()
{
    local -n tr_t=$1
    local tr_node=$2
    local tr_indent_cnt=$3
    local tr_indent=$4
    local tr_id_need_print=$5
    local tr_value_need_print=$6
    local tr_print_array_index=$7
    local tr_indent_new=${|str_repeat ' ' "$tr_indent_cnt";}
    tr_indent_new+="$tr_indent"

    # Traverse children
    local -a "tr_children=(${tr_t[$tr_node.children]})"
    local tr_index=0

    local tr_token tr_mark='=>'
    for tr_token in "${tr_children[@]}"; do
        local tr_child_id="${tr_t[$tr_node.child.$tr_token]}"
        local tr_child_id_p='' tr_value_p=''

        tr_mark='=>'
        [[ "${tr_t[$tr_node.type]}" == "${TR_TYPE_ARR}" ]] && {
            tr_mark='='
            ((tr_print_array_index)) && tr_token=$tr_index || tr_token='o'
        }
            
        ((tr_id_need_print)) && tr_child_id_p="($tr_child_id)"

        if [[ -n "${tr_t[$tr_child_id.key]}" ]]; then
            local tr_key=${tr_t[$tr_child_id.key]}
            local tr_value=${tr_t["$tr_key"]}
            # :TODO: Double-width aligned display of Chinese has not been considered for
            # the time being.
            ((tr_value_need_print)) && {
                local tr_value_indent="${tr_token}"
                ((tr_id_need_print)) && tr_value_indent+="(${tr_child_id})"
                tr_value_indent=${tr_value_indent##*$'\n'}
                tr_value_indent=${tr_value_indent//?/ }
                tr_value_indent+="${tr_indent}    "
                tr_value_p="${tr_value//$'\n'/$'\n'$tr_value_indent}"
            }

            printf "%s%s%s ${tr_mark} %s\n" \
                "$tr_indent" "${tr_token//$'\n'/$'\n'$tr_indent}" "$tr_child_id_p" "$tr_value_p"
        elif [[ "${tr_t[$tr_child_id.type]}" == "$TR_TYPE_ARR" ]] && [[ -z "${tr_t[$tr_child_id.children]}" ]] ; then
            ((tr_value_need_print)) && tr_value_p="$TR_VALUE_NULL_ARR"
            printf "%s%s%s ${tr_mark} %s\n" \
                "$tr_indent" "${tr_token//$'\n'/$'\n'$tr_indent}" "$tr_child_id_p" "$tr_value_p"
        elif [[ "${tr_t[$tr_child_id.type]}" == "$TR_TYPE_OBJ" ]] && [[ -z "${tr_t[$tr_child_id.children]}" ]] ; then
            ((tr_value_need_print)) && tr_value_p="$TR_VALUE_NULL_OBJ"
            printf "%s%s%s ${tr_mark} %s\n" \
                "$tr_indent" "${tr_token//$'\n'/$'\n'$tr_indent}" "$tr_child_id_p" "$tr_value_p"
        else
            printf "%s%s%s\n" "${tr_indent}" "${tr_token//$'\n'/$'\n'$tr_indent}" "$tr_child_id_p"
        fi

        _trie_dump "$1" "$tr_child_id" "$tr_indent_cnt" "$tr_indent_new" "$tr_id_need_print" "$tr_value_need_print" "$tr_print_array_index"
        ((tr_index++))
    done
}

#-------------------------------------------------------------------------------

_trie_token_to_node_id ()
{
    local -n tr_t=$1
    local tr_full_key=$2
    local -A tr_node_info=()
    local -i tr_child_cnt=0

    [[ -z "$tr_full_key" ]] && {
        # ROOT
        [[ -n "${tr_t[$TR_ROOT_ID.children]}" ]] && {
            local -a "tr_children_tmp=(${tr_t[$TR_ROOT_ID.children]})"
            tr_child_cnt=${#tr_children_tmp[@]}
        }
        tr_node_info=(
            [node_id]="$TR_ROOT_ID"
            [physical_full_key]=""
            [index_full_key]=""
            [child_cnt]=$tr_child_cnt
            [type]=${tr_t[$TR_ROOT_ID.type]}
            [value]=""
            )
        REPLY=${tr_node_info[*]@K}
        return ${TR_RET_ENUM_OK}
    }

    trie_key_is_invalid "$tr_full_key" || return $?

    local tr_tokens_str ; tr_tokens_str=${|_split_tokens "$tr_full_key";} || return $?
    local -a "tr_tokens=($tr_tokens_str)"
    local tr_node=$TR_ROOT_ID tr_token tr_child_id tr_token_raw tr_real_full_key=''
    local tr_token_index tr_index_full_key=''
    for tr_token in "${tr_tokens[@]}" ; do
        tr_token_raw=$tr_token
        tr_token=${|tr_resolve_index_token "$1" "$tr_token" "$tr_node";}
        [[ -z "$tr_token" ]] && {
            die "node:${tr_node}(token:${tr_token_raw}) is not found physical token!"
            return $TR_RET_ENUM_KEY_IS_NOTFOUND
        }

        tr_token_index=${|tr_resolve_physical_token "$1" "$tr_token" "$tr_node";}
        [[ -z "$tr_token_index" ]] && {
            die "node:${tr_node}(token:${tr_token_raw}) is not found index token!"
            return $TR_RET_ENUM_KEY_IS_NOTFOUND
        }

        tr_child_id="${tr_t[$tr_node.child.$tr_token]}"
        [[ -z "$tr_child_id" ]] && {
            die "node:${tr_node}(token:${tr_token}) key is not found!"
            return "$TR_RET_ENUM_KEY_IS_NOTFOUND"
        }
        tr_node=$tr_child_id
        tr_real_full_key+="$tr_token$X"
        tr_index_full_key+="$tr_token_index$X"
    done

    [[ -n "${tr_t[$tr_node.children]}" ]] && {
        local -a "tr_children_tmp=(${tr_t[$tr_node.children]})"
        tr_child_cnt=${#tr_children_tmp[@]}
    }

    local tr_key=${tr_t[$tr_node.key]} tr_value=''
    [[ -n "$tr_key" ]] && tr_value=${tr_t["$tr_key"]}

    tr_node_info=(
        [node_id]="$tr_node"
        [physical_full_key]="$tr_real_full_key"
        [index_full_key]="$tr_index_full_key"
        [child_cnt]=$tr_child_cnt
        [type]=${tr_t[$tr_node.type]}
        [value]=$tr_value
        )
    REPLY=${tr_node_info[*]@K}
    return ${TR_RET_ENUM_OK}
}

#-------------------------------------------------------------------------------

trie_delete () 
{
    # local - ; set +x
    local -n tr_t=$1
    local tr_full_key=$2
    local -a tr_delete_reply=()

    # Empty key is legal. Only ROOT nodes are reserved.
    [[ -z "$tr_full_key" ]] && {
        eval -- tr_t=(${|trie_init "${tr_t[$TR_ROOT_ID.type]}";})
        tr_delete_reply=("$TR_ROOT_ID" "")
        REPLY=${tr_delete_reply[*]@Q}
        return ${TR_RET_ENUM_OK}
    }

    trie_key_is_invalid "$tr_full_key" || return $?
    
    local tr_tokens_str ; tr_tokens_str=${|_split_tokens "$tr_full_key";} || return $?
    local -a "tr_tokens=($tr_tokens_str)"

    # 2. Path search: go all the way from root to the node to be deleted
    local tr_node=$TR_ROOT_ID
    local -a tr_path_nodes=("$tr_node")
    local -a tr_path_tokens=("")

    local tr_token tr_child_id tr_index
    for tr_token in "${tr_tokens[@]}"; do
        tr_token=${|tr_resolve_index_token "$1" "$tr_token" "$tr_node";}
        [[ -z "$tr_token" ]] && return $TR_RET_ENUM_OK

        tr_child_id="${tr_t[$tr_node.child.$tr_token]}"
        [[ -z "$tr_child_id" ]] && {
            # die "key is not found!"
            # Keys that do not exist are returned directly.
            return "$TR_RET_ENUM_OK"
        }
        tr_path_nodes+=("$tr_child_id")
        tr_path_tokens+=("$tr_token")
        tr_node=$tr_child_id
    done

    printf -v tr_full_key "%s$X" "${tr_path_tokens[@]:1}"

    # At this time, tr_node is the node corresponding to tr_full_key
    # (it can be a leaf or an intermediate node)

    # 3. First delete the value/key attached to the current node
    unset -v 'tr_t["$tr_full_key"]'   # delete value
    unset -v 'tr_t["$tr_node.key"]'   # delete key
    unset -v 'tr_t["$tr_node.type"]'  # delete type

    # 4. Kill all subtrees rooted at the current node
    #   (even if it is a single leaf)
    local -a tr_stack=("$tr_node")
    local tr_cur tr_tk tr_cid
    while ((${#tr_stack[@]})); do
        tr_cur=${tr_stack[-1]}
        unset -v 'tr_stack[-1]'

        # Get the current node children tr_token list
        local -a "tr_children=(${tr_t[$tr_cur.children]})"

        for tr_tk in "${tr_children[@]}"; do
            tr_cid="${tr_t[$tr_cur.child.$tr_tk]}"
            tr_stack+=("$tr_cid")
            unset -v 'tr_t["$tr_cur.child.$tr_tk"]'
        done

        # If this node has its own key/value, clear it as well.
        local tr_key=${tr_t["$tr_cur.key"]}
        [[ -n "$tr_key" ]] && unset -v 'tr_t[$tr_key]'
        unset -v 'tr_t["$tr_cur.key"]'
        unset -v 'tr_t["$tr_cur.children"]'
        unset -v 'tr_t["$tr_cur.type"]'

        # Do not delete the root node itself
        # unset -v "tr_t[$tr_cur]"
    done

    # Update the children of the upper node
    local tr_parent=${tr_path_nodes[-2]}
    tr_token=${tr_path_tokens[-1]}
    local -a "tr_children=(${tr_t[$tr_parent.children]})"
    array_delete_first_e tr_children "$tr_token"
    if ((${#tr_children[@]})) ; then
        tr_t[$tr_parent.children]=${tr_children[*]@Q}
    else
        unset -v 'tr_t[$tr_parent.children]'
    fi

    unset -v 'tr_t["$tr_parent.child.$tr_token"]'
    
    tr_delete_reply=("$tr_node" "$tr_full_key")
    REPLY=${tr_delete_reply[*]@Q}

    return "$TR_RET_ENUM_OK"
}

#-------------------------------------------------------------------------------

trie_get_leaf ()
{
    # local - ; set +x
    local -n tr_t=$1
    local tr_full_key=$2

    [[ -z "$tr_full_key" ]] && {
        die "key is null."
        return $TR_RET_ENUM_KEY_IS_NULL
    }
    local tr_node_info
    tr_node_info=${|_trie_token_to_node_id "$1" "$tr_full_key";} || return $?
    local -A "tr_node_info=($tr_node_info)"
    local tr_physical_full_key=${tr_node_info[physical_full_key]}
    if [[ -v 'tr_t["$tr_physical_full_key"]' ]] ; then
        REPLY=${tr_t["$tr_physical_full_key"]}
        return $TR_RET_ENUM_OK
    else
        die "full key:${tr_full_key} physical full key:${tr_physical_full_key} not found leaf!"
        return $TR_RET_ENUM_KEY_IS_NOT_LEAF
    fi
}

#-------------------------------------------------------------------------------

trie_get_tree ()
{
    # local - ; set +x
    local tr_t_name=$1
    local -n tr_t=$1
    local tr_full_key=$2
    local tr_node=$3
    local tr_real_full_key=$4

    if [[ -n "$tr_node" && -n "$tr_real_full_key" ]] ; then
        # 2. Determine whether tr_full_key is legal
        trie_key_is_invalid "$tr_full_key" || return $?
    else
        # 1. If tr_full_key is empty, return the entire tree directly
        [[ -z "$tr_full_key" ]] && {
            REPLY="${tr_t[*]@K}"
            return ${TR_RET_ENUM_OK}
        }
        
        # 2. Determine whether tr_full_key is legal
        trie_key_is_invalid "$tr_full_key" || return $?

        # 4. Find the node ID corresponding to tr_full_key
        local tr_node_info
        tr_node_info=${|_trie_token_to_node_id "$tr_t_name" "$tr_full_key";} || return $?
        local -A "tr_node_info=($tr_node_info)"
        tr_node=${tr_node_info[node_id]}
        tr_real_full_key=${tr_node_info[physical_full_key]}
    fi

    [[ -v 'tr_t["$tr_real_full_key"]' ]] && {
        die "key is leaf!"
        return ${TR_RET_ENUM_KEY_IS_LEAF}
    }

    # 5. Get the children of the node (the first-level node of the subtree)
    local -a "tr_root_children=(${tr_t[$tr_node.children]})"

    # 6. Create a new tree
    local -A "tr_new=(${|trie_init "${tr_t[$tr_node.type]}";})"

    # If the subtree root is empty, it is returned directly.
    ((${#tr_root_children[@]})) || { REPLY=${tr_new[*]@K} ; return ${TR_RET_ENUM_OK} ; }
    
    # 7. The children of the new tree are reset to the current tr_root_children
    tr_new[$TR_ROOT_ID.children]=${tr_root_children[*]@Q}

    # 8. Mount all root children
    local tr_tk tr_cid
    local -a tr_stack=()
    for tr_tk in "${tr_root_children[@]}" ; do
        tr_cid=${tr_t[$tr_node.child.$tr_tk]}
        tr_new["$TR_ROOT_ID.child.$tr_tk"]="$tr_cid"
        tr_stack+=("$tr_cid")
    done

    # 9. DFS copy child node
    local tr_max_id=1
    while ((${#tr_stack[@]})) ; do
        local tr_cur=${tr_stack[-1]}
        unset -v 'tr_stack[-1]'
        ((tr_max_id=(tr_cur>tr_max_id)?tr_cur:tr_max_id))

        # tr_new[$tr_cur]=1
        [[ -n "${tr_t[$tr_cur.children]}" ]] && tr_new[$tr_cur.children]=${tr_t[$tr_cur.children]}
        [[ -n "${tr_t[$tr_cur.type]}" ]] && tr_new[$tr_cur.type]=${tr_t[$tr_cur.type]}

        # The key here cannot be copied directly from the old tree, and 
        # the prefix needs to be cut off.
        local tr_key=${tr_t["$tr_cur.key"]}

        if [[ -n "$tr_key" ]] ; then
            tr_new[$tr_cur.key]=${tr_key#"$tr_real_full_key"}
            local tr_new_key=${tr_new["$tr_cur.key"]}
            tr_new["$tr_new_key"]=${tr_t["$tr_key"]}
        fi

        local -a "tr_children=(${tr_t[$tr_cur.children]})"

        for tr_tk in "${tr_children[@]}" ; do
            tr_cid="${tr_t["$tr_cur.child.$tr_tk"]}"
            tr_new["$tr_cur.child.$tr_tk"]="$tr_cid"
            tr_stack+=("$tr_cid")
        done
    done

    tr_new[max_index]=$((tr_max_id+1))

    REPLY=${tr_new[*]@K}
    return ${TR_RET_ENUM_OK}
}

#-------------------------------------------------------------------------------

# Iterate children under prefix
#                                  Arrays do not need to be wrapped with []
#                   phy_token type index_token value node 
# default               1       1       0        0    0
# bit                   0       1       2        3    4
trie_iter ()
{
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
            trie_key_is_invalid "$tr_prefix" || return $?
        }
        local tr_node_info
        tr_node_info=${|_trie_token_to_node_id "$1" "$tr_prefix";} || return $?
        local -A "tr_node_info=($tr_node_info)"
        tr_node_id=${tr_node_info[node_id]}
    }

    # If tr_node_id is empty, traverse the root node
    tr_node_id=${tr_node_id:-"$TR_ROOT_ID"}

    local -a "tr_children=(${tr_t[$tr_node_id.children]})"

    local tr_tk tr_child_id tr_type tr_value tr_key
    local tr_tk_p tr_type_p tr_value_p tr_node_p tr_index_tk_p

    local -i tr_index=0
    local tr_parent_type=${tr_t[$tr_node_id.type]}
    for tr_tk in "${tr_children[@]}"; do
        tr_child_id=${tr_t["$tr_node_id.child.$tr_tk"]}
        trie_get_node_type "$1" "$tr_child_id" ; tr_type=$?

        tr_key="${tr_t["$tr_child_id.key"]}"
        tr_value='' ; [[ -n "$tr_key" ]] && tr_value=${tr_t["$tr_key"]}

        if ((tr_is_iter_index_token)) ; then
            if [[ "$tr_parent_type" == "$TR_TYPE_ARR" ]] ; then
                tr_index_tk_p=${tr_index@Q}
            else
                tr_index_tk_p=${tr_tk@Q}
            fi
        else
            tr_index_tk_p=''
        fi
        
        # Empty objects and empty arrays return simulated values
        case "$tr_type" in
        $TR_NODE_KIND_OBJ_EMPTY)    tr_value="$TR_VALUE_NULL_OBJ" ;;
        $TR_NODE_KIND_ARR_EMPTY)    tr_value=$"$TR_VALUE_NULL_ARR" ;;
        esac

        ((tr_is_iter_phy_token)) && tr_tk_p=${tr_tk@Q}         || tr_tk_p=''
        ((tr_is_iter_type))      && tr_type_p=${tr_type@Q}     || tr_type_p=''
        ((tr_is_iter_value))     && tr_value_p=${tr_value@Q}   || tr_value_p=''
        ((tr_is_iter_node))      && tr_node_p=${tr_child_id@Q} || tr_node_p=''

        #                      phy_token      type       index_token       value         node
        REPLY+="${REPLY:+$'\n'}${tr_tk_p} ${tr_type_p} ${tr_index_tk_p} ${tr_value_p} ${tr_node_p}"
        ((tr_index++))
    done

    return ${TR_RET_ENUM_OK}
}

#-------------------------------------------------------------------------------

# This is just an example to demonstrate the callback function of trie_walk,
# processing the entire tree
trie_callback_print ()
{
    local node_kind=$1         # leaf / leaf_null / obj / obj_empty / arr / arr_empty
    local index_token=$2       # "{k}" or "[0]"
    local index_full_key=$3    # "{a}$X[0]$X{b}$X"
    local value=$4             # only meaningful for leaf/leaf_null
    local physical_token=$5    # Internal tokens like "<123>" (if needed)
    local physical_full_key=$6 # "{a}$X<12>$X<56>$X"
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
    printf "%s\n" "$printf_info"
    return $TR_RET_ENUM_OK
}

#-------------------------------------------------------------------------------

trie_get_node_type ()
{
    # local - ; set +x
    local -n tr_t=$1
    local tr_node=$2
    local tr_key
    
    if [[ -v 'tr_t["$tr_node.key"]' ]] ; then
        tr_key="${tr_t["$tr_node.key"]}"
        if [[ "${tr_t["$tr_key"]}" == "$TR_VALUE_NULL" ]] ; then
            return $TR_NODE_KIND_LEAF_NULL
        else
            return $TR_NODE_KIND_LEAF
        fi
    elif [[ "${tr_t[$tr_node.type]}" == "$TR_TYPE_OBJ" ]] ; then
        if [[ -n "${tr_t[$tr_node.children]}" ]] ; then
            return $TR_NODE_KIND_OBJ
        else
            return $TR_NODE_KIND_OBJ_EMPTY
        fi
    elif [[ "${tr_t[$tr_node.type]}" == "$TR_TYPE_ARR" ]] ; then
        if [[ -n "${tr_t[$tr_node.children]}" ]] ; then
            return $TR_NODE_KIND_ARR
        else
            return $TR_NODE_KIND_ARR_EMPTY
        fi
    else
        return $TR_NODE_KIND_UNKNOWN
    fi
}

#-------------------------------------------------------------------------------

trie_layer_child_is_flat ()
{
    case "$1" in
    $TR_NODE_KIND_OBJ_EMPTY|$TR_NODE_KIND_ARR_EMPTY|$TR_NODE_KIND_LEAF_NULL|$TR_NODE_KIND_LEAF)
        return 0
        ;;
    esac
    
    return 1
}

#-------------------------------------------------------------------------------

trie_walk ()
{
    # local - ; set +x
    local -n tr_t=$1
    local tr_prefix=$2
    local tr_callback=${3:-trie_callback_print}

    local tr_root_id tr_physical_full_key tr_index_full_key
    local tr_node_info tr_node_kind
    tr_node_info=${|_trie_token_to_node_id "$1" "$tr_prefix";} || return $?
    local -A "tr_node_info=($tr_node_info)"
    tr_root_id=${tr_node_info[node_id]}
    tr_physical_full_key=${tr_node_info[physical_full_key]}
    tr_index_full_key=${tr_node_info[index_full_key]}

    local -a tr_stack=()
    tr_stack+=("$tr_physical_full_key" "$tr_index_full_key" "$tr_root_id")

    while ((${#tr_stack[@]})); do
        local tr_node_id=${tr_stack[-1]} ; unset -v 'tr_stack[-1]'
        local tr_index_prefix=${tr_stack[-1]} ; unset -v 'tr_stack[-1]'
        local tr_physical_prefix=${tr_stack[-1]} ; unset -v 'tr_stack[-1]'

        local -a "tr_children=(${tr_t[$tr_node_id.children]})"
        local tr_tk tr_child_id tr_value tr_index_token

        local -i tr_index=0
        for tr_tk in "${tr_children[@]}"; do
            tr_child_id=${tr_t["$tr_node_id.child.$tr_tk"]}

            trie_get_node_type "$1" "$tr_child_id" ; tr_node_kind=$?
            local tr_key="${tr_t["$tr_child_id.key"]}"
            [[ -n "$tr_key" ]] && tr_value=${tr_t["$tr_key"]} || tr_value=''
            
            # There are special cases here. Empty arrays and empty
            # objects also return simulated values.
            case "$tr_node_kind" in
            $TR_NODE_KIND_OBJ_EMPTY)
                tr_value="$TR_VALUE_NULL_OBJ"   ;;
            $TR_NODE_KIND_ARR_EMPTY)
                tr_value="$TR_VALUE_NULL_ARR"   ;;
            esac

            tr_index_token=$tr_tk
            [[ "${tr_tk:0:1}" == '<' ]] && tr_index_token="[$tr_index]"
            tr_index_full_key="$tr_index_prefix$tr_index_token$X"
            tr_physical_full_key="$tr_physical_prefix$tr_tk$X"

            "$tr_callback"  "$tr_node_kind" \
                            "$tr_index_token" \
                            "$tr_index_full_key" \
                            "$tr_value" \
                            "$tr_tk" \
                            "$tr_physical_full_key" \
                            "$tr_child_id" \
                            "$tr_node_id" || return $?

            case "$tr_node_kind" in
            $TR_NODE_KIND_OBJ|$TR_NODE_KIND_ARR)
                tr_stack+=("$tr_physical_full_key" "$tr_index_full_key" "$tr_child_id")
                ;;
            esac

            ((tr_index++))
        done
    done
    return $TR_RET_ENUM_OK
}

#-------------------------------------------------------------------------------

trie_id_rebuild ()
{
    # local - ; set +x
    local -n tr_old=$1
    local -a tr_id_list=()

    trie_id_rebuild_collect_ids_callback ()
    {
        local old_id=$7
        tr_id_list+=("$old_id")
    }
    trie_walk "$1" '' trie_id_rebuild_collect_ids_callback

    # There is absolutely no need to waste time sorting here.
    # array_qsort tr_id_list '-gt'
    local -A tr_id_map=()
    local tr_new_id=$((TR_ROOT_ID+1))
    local tr_old_id
    for tr_old_id in "${tr_id_list[@]}" ; do
        tr_id_map[$tr_old_id]=$tr_new_id
        ((tr_new_id++))
    done

    tr_id_map[$TR_ROOT_ID]=1

    local -A "tr_new=(${|trie_init "${tr_old[$TR_ROOT_ID.type]}";})"

    trie_id_rebuild_callback ()
    {
        local type=$1 value=$4 token=$5 full_key=$6 old_id=$7 parent_old_id=$8 
        local index_token=$2

        local new_id=${tr_id_map[$old_id]}
        local new_parent_id=${tr_id_map[$parent_old_id]}

        # tr_new[$new_id]=1
        
        # write type tag
        case "$type" in
        $TR_NODE_KIND_OBJ|$TR_NODE_KIND_OBJ_EMPTY)
            tr_new[$new_id.type]=$TR_TYPE_OBJ   ;;
        $TR_NODE_KIND_ARR|$TR_NODE_KIND_ARR_EMPTY)
            tr_new[$new_id.type]=$TR_TYPE_ARR   ;;
        # Other leaf keys need to write values
        *)  tr_new[$new_id.key]="$full_key"
            tr_new["$full_key"]="$value"
            ;;
        esac

        # If the parent is an array, special handling is required.
        if str_is_decimal_positive_int "$index_token" ; then
            # Update new token
            tr_new["$new_parent_id.child.<$new_id>"]="$new_id"
            local tr_real_token="<$new_id>"
            tr_new[$new_parent_id.children]+=" ${tr_real_token@Q}"
        else
            tr_new[$new_parent_id.child.$token]="$new_id"
            tr_new[$new_parent_id.children]+=" ${token@Q}"
        fi
    }
    trie_walk $1 '' trie_id_rebuild_callback

    tr_new[max_index]=$tr_new_id
    
    REPLY=${tr_new[*]@K}
    return ${TR_RET_ENUM_OK}
}

#-------------------------------------------------------------------------------

trie_equals ()
{
    # local - ; set +x
    local -n tr_trie_equals_1=$1 tr_trie_equals_2=$2
    local tr_trie_equals_1_name=$1 tr_trie_equals_2_name=$2
    local tr_ok=1
    local -A tr_trie_equals_1_check=()
    local -A tr_trie_equals_2_check=()
    local tr_key

    _trie_equals_fail ()
    { 
        die "$tr_trie_equals_1_name $tr_trie_equals_2_name is not the same!"
        return $TR_RET_ENUM_TREE_IS_NOT_SAME
    }

    [[ "${tr_trie_equals_1[$TR_ROOT_ID.type]}" == "${tr_trie_equals_2[$TR_ROOT_ID.type]}" ]] || {
        _trie_equals_fail ; return $?
    }

    [[ "${#tr_trie_equals_1[@]}" == "${#tr_trie_equals_2[@]}" ]] || {
        _trie_equals_fail ; return $?
    }

    # Iterate over tr_1, check tr_2
    trie_equals_check_ab ()
    {
        local kind=$1 index_full_key=$3 value=$4
        tr_trie_equals_1_check["$index_full_key"]="$kind$X$value$X"

        return $TR_RET_ENUM_OK
    }

    trie_walk "$tr_trie_equals_1_name" '' trie_equals_check_ab || return $?

    # Iterate over tr_2, check tr_1
    trie_equals_check_ba ()
    {
        local kind=$1 index_full_key=$3 value=$4

        tr_trie_equals_2_check["$index_full_key"]="$kind$X$value$X"

        return $TR_RET_ENUM_OK
    }

    trie_walk "$tr_trie_equals_2_name" '' trie_equals_check_ba || return $?

    [[ "${#tr_trie_equals_1_check[@]}" == "${#tr_trie_equals_2_check[@]}" ]] || {
        _trie_equals_fail ; return $?
    }

    for tr_key in "${!tr_trie_equals_1_check[@]}" ; do
        [[ -v 'tr_trie_equals_2_check[$tr_key]' ]] || {
            _trie_equals_fail ; return $?
        }
        [[ "${tr_trie_equals_1_check[$tr_key]}" == "${tr_trie_equals_2_check[$tr_key]}" ]] || {
            _trie_equals_fail ; return $?
        }
    done

    for tr_key in "${!tr_trie_equals_2_check[@]}" ; do
        [[ -v 'tr_trie_equals_1_check[$tr_key]' ]] || {
            _trie_equals_fail ; return $?
        }
        [[ "${tr_trie_equals_1_check[$tr_key]}" == "${tr_trie_equals_2_check[$tr_key]}" ]] || {
            _trie_equals_fail ; return $?
        }
    done

    return $TR_RET_ENUM_OK
}

#-------------------------------------------------------------------------------

_trie_array_next_key ()
{
    local tr_name=$1
    local tr_up_key=$2
    # push/unshift/pop/shift
    local tr_mode=$3
    local tr_child_cnt

    # Get the up node type, if it exists, it must be an array or null
    # If it does not exist create an array and write position 0
    local tr_node_info tr_node_info_ret
    tr_node_info=${|_trie_token_to_node_id "$tr_name" "$tr_up_key" 2>/dev/null;}
    tr_node_info_ret=$?

    case "$tr_node_info_ret" in
    $TR_RET_ENUM_KEY_IS_NOTFOUND)
        case "$tr_mode" in
        push)   REPLY="$tr_up_key[0]$X" ;;
        unshift)
                REPLY="$tr_up_key(0)$X" ;;
        pop|shift)
                return $tr_node_info_ret ;;
        esac
        ;;
    $TR_RET_ENUM_OK)
        # Get the up node type
        local -A "tr_node_info=($tr_node_info)"
        if  [[ "${tr_node_info[type]}" == "$TR_TYPE_ARR" ]] ||
            [[ "${tr_node_info[value]}" == "$TR_VALUE_NULL" ]] ; then
            tr_child_cnt=${tr_node_info[child_cnt]}
            case "$tr_mode" in
            push)   REPLY="${tr_node_info[physical_full_key]}[$tr_child_cnt]$X" ;;
            unshift)
                    REPLY="${tr_node_info[physical_full_key]}(0)$X" ;;
            pop|shift)    
                # First check if the child is empty
                ((tr_child_cnt)) || {
                    die "node:${tr_node_info[node_id]} child cnt is 0."
                    return $TR_RET_ENUM_KEY_CHILD_CNT_IS_ZERO
                }
                ;;&
            pop)    REPLY="${tr_node_info[physical_full_key]}[$((tr_child_cnt-1))]$X" ;;
            shift)  REPLY="${tr_node_info[physical_full_key]}[0]$X" ;;
            esac
        else
            die "node:${tr_node_info[node_id]} type is not array or null."
            return $TR_RET_ENUM_KEY_UP_LEV_TYPE_MISMATCH
        fi
        ;;
    *)
        return $tr_node_info_ret
        ;;
    esac

    return ${TR_RET_ENUM_OK}
}

#-------------------------------------------------------------------------------

# Pushing empty leaves and empty arrays is OK
_trie_array_write ()
{
    # local - ; set +x
    local tr_name=$1 tr_up_key=$2
    local tr_mode=$3      # push / unshift
    local tr_write=$4     # leaf / tree
    local tr_value=$5     # leaf value or subtree name

    local tr_next_key
    tr_next_key=${|_trie_array_next_key "$tr_name" "$tr_up_key" "$tr_mode";} || return $?

    case "$tr_write" in
    leaf)   trie_insert "$tr_name" "$tr_next_key" "$tr_value" ;;
    tree)   trie_graft "$tr_name" "$tr_next_key" "$tr_value" ;;
    esac
}

#-------------------------------------------------------------------------------

# The return values of leaf and tree are the return values of insert and graft
trie_push_leaf () { _trie_array_write "$1" "$2" push leaf "$3" ; }
trie_push_tree () { _trie_array_write "$1" "$2" push tree "$3" ; }
trie_unshift_leaf () { _trie_array_write "$1" "$2" unshift leaf "$3" ; }
trie_unshift_tree () { _trie_array_write "$1" "$2" unshift tree "$3" ; }

#-------------------------------------------------------------------------------

_trie_array_get ()
{
    # local - ; set +x
    local tr_name=$1 tr_up_key=$2
    local tr_mode=$3      # pop / shift
    local tr_read=$4      # leaf / tree

    local tr_next_key
    tr_next_key=${|_trie_array_next_key "$tr_name" "$tr_up_key" "$tr_mode";} || return $?

    case "$tr_read" in
    leaf)   trie_get_leaf "$tr_name" "$tr_next_key" ;;
    tree)   trie_get_tree "$tr_name" "$tr_next_key" ;;
    esac
}

#-------------------------------------------------------------------------------

trie_pop_leaf ()
{
    # REPLY It will be rewritten directly in the sub-function. The explicit
    # assignment here is just for higher readability.
    local tr_pop_leaf_reply=
    tr_pop_leaf_reply=${|_trie_array_get "$1" "$2" pop leaf;} || return $?
    trie_delete "$1" "$2[-1]$X" || return $?
    REPLY=$tr_pop_leaf_reply
}

#-------------------------------------------------------------------------------

trie_pop_tree ()
{
    local tr_pop_tree_reply=
    tr_pop_tree_reply=${|_trie_array_get "$1" "$2" pop tree;} || return $?
    trie_delete "$1" "$2[-1]$X" || return $?
    REPLY=$tr_pop_tree_reply
}

#-------------------------------------------------------------------------------

trie_shift_leaf ()
{ 
    local tr_shift_leaf_reply=
    tr_shift_leaf_reply=${|_trie_array_get "$1" "$2" shift leaf;} || return $?
    trie_delete "$1" "$2[0]$X" || return $?
    REPLY=$tr_shift_leaf_reply
}

#-------------------------------------------------------------------------------

trie_shift_tree ()
{
    local tr_shift_tree_reply=
    tr_shift_tree_reply=${|_trie_array_get "$1" "$2" shift tree;} || return $?
    trie_delete "$1" "$2[0]$X" || return $?
    REPLY=$tr_shift_tree_reply
}

#-------------------------------------------------------------------------------

trie_layer_get_flat ()
{
    # local - ; set +x
    local tr_expect=$1
    local -n tr_t=$2
    local tr_full_key=$3
    local tr_node_id=$4
    # 'arr' or 'obj'

    if [[ -z "$tr_node_id" ]] ; then
        [[ -n "$tr_full_key" ]] && {
            trie_key_is_invalid "$tr_full_key" || return $?
        }
        local tr_node_info
        tr_node_info=${|_trie_token_to_node_id "$2" "$tr_full_key";} || return $?
        local -A "tr_node_info=($tr_node_info)"
        tr_node_id=${tr_node_info[node_id]}
    fi

    # If tr_node_id is empty, determine the root node
    tr_node_id=${tr_node_id:-"$TR_ROOT_ID"}

    # First determine whether the current layer is null
    local tr_key=${tr_t[$tr_node_id.key]}
    if [[ -n "$tr_key" && -v 'tr_t[$tr_key]' ]] ; then
        if [[ "${tr_t[$tr_key]}" == "$TR_VALUE_NULL" ]] ; then
            return $TR_FLAT_IS_MATCH
        else
            die "node id:${tr_node_id} flat type not match."
            return $TR_FLAT_IS_NOT_MATCH
        fi
    fi

    # Object or array to determine whether the child has children (non-flat)
    local tr_old_ifs=$IFS IFS=$'\n' tr_tuple 
    case "${tr_t[$tr_node_id.type]}" in
    $TR_TYPE_ARR)
        [[ "$tr_expect" == 'arr' ]] || {
            die "node id:${tr_node_id} flat type not match."
            return $TR_FLAT_IS_NOT_MATCH
        }
        local -a tr_plat_arr=()
        for tr_tuple in ${|trie_iter "$2" '' $((2#11111)) "$tr_node_id";} ; do
            IFS=$tr_old_ifs ; local -a "tr_tuple=($tr_tuple)"
            trie_layer_child_is_flat "${tr_tuple[1]}" || {
                die "node id:${tr_node_id} flat type not match."
                return $TR_FLAT_IS_NOT_MATCH
            }
            tr_plat_arr+=("${tr_tuple[3]}")
        done
        REPLY=${tr_plat_arr[*]@Q}
        ;;
    $TR_TYPE_OBJ)
        [[ "$tr_expect" == 'obj' ]] || {
            die "node id:${tr_node_id} flat type not match."
            return $TR_FLAT_IS_NOT_MATCH
        }
        local -A tr_plat_arr=()
        for tr_tuple in ${|trie_iter "$2" '' $((2#11111)) "$tr_node_id";} ; do
            IFS=$tr_old_ifs ; local -a "tr_tuple=($tr_tuple)"
            trie_layer_child_is_flat "${tr_tuple[1]}" || {
                die "node id:${tr_node_id} flat type not match."
                return $TR_FLAT_IS_NOT_MATCH
            }
            tr_plat_arr["${tr_tuple[0]:1:-1}"]="${tr_tuple[3]}"
        done
        REPLY=${tr_plat_arr[*]@K}
        ;;
    esac
    
    return $TR_FLAT_IS_MATCH
}

#-------------------------------------------------------------------------------

trie_to_flat_array () { trie_layer_get_flat 'arr' "$@" ; }
trie_to_flat_assoc () { trie_layer_get_flat 'obj' "$@" ; }

#-------------------------------------------------------------------------------

trie_pop_to_flat_array ()
{
    local tr_pop_fa_reply=
    tr_pop_fa_reply=${|trie_to_flat_array "$1" "$2[-1]$X";} || return $?
    trie_delete "$1" "$2[-1]$X" || return $?
    REPLY=$tr_pop_fa_reply
}

#-------------------------------------------------------------------------------

trie_pop_to_flat_assoc ()
{
    local tr_pop_fs_reply=
    tr_pop_fs_reply=${|trie_to_flat_assoc "$1" "$2[-1]$X";} || return $?
    trie_delete "$1" "$2[-1]$X" || return $?
    REPLY=$tr_pop_fs_reply
}

#-------------------------------------------------------------------------------

trie_shift_to_flat_array ()
{
    local tr_shif_fa_reply=
    tr_shif_fa_reply=${|trie_to_flat_array "$1" "$2[0]$X";} || return $?
    trie_delete "$1" "$2[0]$X" || return $?
    REPLY=$tr_shif_fa_reply
}

#-------------------------------------------------------------------------------

trie_shift_to_flat_assoc ()
{
    local tr_shift_fs_reply=
    tr_shift_fs_reply=${|trie_to_flat_assoc "$1" "$2[0]$X";} || return $?
    trie_delete "$1" "$2[0]$X" || return $?
    REPLY=$tr_shift_fs_reply
}

#-------------------------------------------------------------------------------

# Hooks have no deletion semantics, but writes to flat layers do
trie_flat_to_tree ()
{
    # local - ; set +x
    local tr_prefix=$2
    local -n tr_array=$3
    local -i tr_array_is_assoc=0

    [[ "${tr_array@a}" == *A* ]] && tr_array_is_assoc=1

    [[ "$tr_prefix" == *")$X"* ]] || {
        trie_delete "$1" "$tr_prefix" || return $?
    }

    local tr_index
    local -a tr_params=()
    for tr_index in "${!tr_array[@]}" ; do
        if ((tr_array_is_assoc)) ; then
            tr_params+=("{$tr_index}$X" "${tr_array[$tr_index]}")
        else
            tr_params+=("[$tr_index]$X" "${tr_array[$tr_index]}")
        fi
    done

    ((${#tr_params[@]})) || {
        if ((tr_array_is_assoc)) ; then
            tr_params=("$TR_VALUE_NULL_OBJ")
        else
            tr_params=("$TR_VALUE_NULL_ARR")
        fi
    }

    trie_qinserts "$1" common "$tr_prefix" "${tr_params[@]}"
}

#-------------------------------------------------------------------------------

# Not implemented, users can define it themselves through trie_walk
trie_search () { : ; }

#-------------------------------------------------------------------------------

_trie_flat_insert ()
{
    # local - ; set +x
    local tr_next_key
    tr_next_key=${|_trie_array_next_key "$1" "$2" "$3";} || return $?

    local -a tr_params=()
    local tr_index tr_token
    local -i tr_is_assoc=0
    local -n tr_array=$4

    [[ "${tr_array@a}" == *A* ]] && tr_is_assoc=1
    
    for tr_index in "${!tr_array[@]}" ; do
        ((tr_is_assoc)) && tr_token="{$tr_index}$X" || tr_token="[$tr_index]$X"
        tr_params+=("$tr_token" "${tr_array[$tr_index]}")
    done

    ((${#tr_array[@]})) || {
        if ((tr_is_assoc)) ; then
            tr_params=("$TR_VALUE_NULL_OBJ")
        else
            tr_params=("$TR_VALUE_NULL_ARR")
        fi
    }

    trie_qinserts "$1" common "$tr_next_key" "${tr_params[@]}"
}

#-------------------------------------------------------------------------------

trie_push_flat () { _trie_flat_insert "$1" "$2" push "$3" ; }
trie_unshift_flat () { _trie_flat_insert "$1" "$2" unshift "$3" ; }

#-------------------------------------------------------------------------------

# This function is very slow and is only used for verification.
trie_to_json_slow ()
{
    # local - ; set +x
    local tr_name=$1
    local -n tr_t=$1
    local tr_full_key=$2
    local tr_jstr
    local tr_temp_file=$(mktemp)
    trap 'rm -f "$tr_temp_file"' RETURN

    command -v gobolt &>/dev/null || {
        die "gobolt tool is not installed."
        return $TR_RET_ENUM_KEY_OTHER_TOOL_NOT_INSTALLED
    }

    [[ -z "${tr_t[$TR_ROOT_ID.children]}" ]] && {
        case "${tr_t[$TR_ROOT_ID.type]}" in
        $TR_TYPE_OBJ)   REPLY='{}' ; return $TR_RET_ENUM_OK ;;
        $TR_TYPE_ARR)   REPLY='[]' ; return $TR_RET_ENUM_OK ;;
        *)  return $TR_RET_ENUM_TREE_NOT_HAVE_ROOT  ;;
        esac
    }

    trie_to_json_slow_callback ()
    {
        local node_kind=$1
        local index_full_key=$3 value=$4
        local -a "tokens=(${|_split_tokens "$index_full_key";})"
        local -a bjson_params=()
        local token
        local write_jstr_param='-f'

        case "$node_kind" in
        $TR_NODE_KIND_LEAF)
            case "$value" in
            $TR_VALUE_TRUE) value='true'   ;;
            $TR_VALUE_FALSE) value='false' ;;
            *"$X")  value=${value%"$X"}    ;;
            *) write_jstr_param='-o'       ;;
            esac
            ;;
        $TR_NODE_KIND_LEAF_NULL) value='null' ;;
        $TR_NODE_KIND_ARR_EMPTY) value='[]'   ;;
        $TR_NODE_KIND_OBJ_EMPTY) value='{}'   ;;
        *)  return $TR_RET_ENUM_OK            ;;
        esac

        for token in "${tokens[@]}" ; do
            case "$token" in
            '{'*'}') bjson_params+=(":${token:1:-1}")   ;;
            '['*']') bjson_params+=("${token:1:-1}")    ;;
            esac
        done

        printf "%s" "$value" >"$tr_temp_file"
        
        tr_jstr=${ printf "%s" "$tr_jstr" | \
            gobolt json -m w -k stdin "$write_jstr_param" "$tr_temp_file" \
            -P -- "${bjson_params[@]}";} || return $?
        return $TR_RET_ENUM_OK
    }

    trie_walk "$tr_name" "$tr_full_key" trie_to_json_slow_callback || return $?
    REPLY=$tr_jstr
}

#-------------------------------------------------------------------------------

trie_to_json ()
{
    # local - ; set +x
    local tr_name=$1
    local -n tr_t=$1
    local tr_full_key=$2
    local -a tr_gobolt_params=()

    command -v gobolt &>/dev/null || {
        die "gobolt tool is not installed."
        return $TR_RET_ENUM_KEY_OTHER_TOOL_NOT_INSTALLED
    }

    [[ -z "${tr_t[$TR_ROOT_ID.children]}" ]] && {
        case "${tr_t[$TR_ROOT_ID.type]}" in
        $TR_TYPE_OBJ)   REPLY='{}' ; return $TR_RET_ENUM_OK ;;
        $TR_TYPE_ARR)   REPLY='[]' ; return $TR_RET_ENUM_OK ;;
        *)  return $TR_RET_ENUM_TREE_NOT_HAVE_ROOT  ;;
        esac
    }

    trie_to_json_callback ()
    {
        local node_kind=$1
        local index_full_key=$3 value=$4
        local -a "tokens=(${|_split_tokens "$index_full_key";})"
        local -a bjson_params=()
        local token

        case "$node_kind" in
        $TR_NODE_KIND_LEAF)
            case "$value" in
            $TR_VALUE_TRUE)     value='j:true'        ;;
            $TR_VALUE_FALSE)    value='j:false'       ;;
            *"$X")              value=j:${value%"$X"} ;;
            *)                  value=s:${value}      ;;
            esac
            ;;
        $TR_NODE_KIND_LEAF_NULL) value='j:null' ;;
        $TR_NODE_KIND_ARR_EMPTY) value='j:[]'   ;;
        $TR_NODE_KIND_OBJ_EMPTY) value='j:{}'   ;;
        *)  return $TR_RET_ENUM_OK            ;;
        esac

        for token in "${tokens[@]}" ; do
            case "$token" in
            '{'*'}')
                trie_bjson_key_escape "${token:1:-1}" token
                if ((${#bjson_params[@]})) ; then
                    bjson_params+=(".:$token")
                else
                    bjson_params+=(":$token")
                fi
                ;;
            '['*']')
                if ((${#bjson_params[@]})) ; then
                    bjson_params+=(".${token:1:-1}")
                else
                    bjson_params+=("${token:1:-1}")
                fi
                ;;
            esac
        done

        printf -v 'tr_gobolt_params[${#tr_gobolt_params[@]}]' "%s" "${bjson_params[@]}"
        tr_gobolt_params+=("$value")

        return $TR_RET_ENUM_OK
    }

    trie_walk "$tr_name" "$tr_full_key" trie_to_json_callback || return $?

    # printf "%s\n" "${tr_gobolt_params[@]}"

    local tr_i
    local -A "tr_system_limits=(${|trie_get_arg_limits;})"

    # Check if each parameter exceeds
    # If it is found to be exceeded, the report will fail.

    for((tr_i=0;tr_i<${#tr_gobolt_params[@]};tr_i+=2)) ; do
        local -i tr_key_len=${|str_bytes "${tr_gobolt_params[tr_i]}";}

        ((  tr_key_len>=${tr_system_limits[MAX_ARG_STRLEN]} )) && {
            die "Command line parameters exceed limit"
            return $TR_RET_ENUM_KEY_PARAMETER_LENGTH_EXCEEDS_LIMIT
        }
    done

    local -i tr_all_param_byte_len=${|str_bytes "${tr_gobolt_params[*]}";}

    if ((tr_all_param_byte_len>=${tr_system_limits[AVAILABLE]})) ; then
        trie_to_json_slow "$tr_name" "$tr_full_key" ; return $?
    else
        REPLY=${ printf '' | gobolt json -m w -k stdin -s '' -M -- "${tr_gobolt_params[@]}";}
    fi
}

#-------------------------------------------------------------------------------

trie_from_json ()
{
    # local - ; set +x
    local tr_json_str=$1
    local tr_bjson_keys="${@:2}"

    command -v gobolt &>/dev/null || {
        die "gobolt tool is not installed."
        return $TR_RET_ENUM_KEY_OTHER_TOOL_NOT_INSTALLED
    }

    local tr_assoc ; tr_assoc=${ printf "%s" "$tr_json_str" | \
        gobolt json -m r -t txt -k stdin -F trie -x "$X" -P -- "${tr_bjson_keys[@]}";}
    case "$?" in
    $TR_GOBOLT_JSONTYPEARRAY|$TR_GOBOLT_JSONTYPEOBJECT)
        local -A "tr_assoc=($tr_assoc)" ;;&
    $TR_GOBOLT_JSONTYPEARRAY)
        local -A "tr_init_tree=(${|trie_init "$TR_TYPE_ARR";})" ;;
    $TR_GOBOLT_JSONTYPEOBJECT)
        local -A "tr_init_tree=(${|trie_init "$TR_TYPE_OBJ";})" ;;
    *)
        die "bjson key:${tr_bjson_keys[*]} type is known."
        return $TR_RET_ENUM_KEY_BJSON_TYPE_INVALID
        ;;
    esac

    local tr_key
    for tr_key in "${!tr_assoc[@]}" ; do
        trie_insert tr_init_tree "$tr_key" "${tr_assoc[$tr_key]}"
    done
    
    # trie_dump tr_init_tree

    REPLY=${tr_init_tree[*]@K}
}

#-------------------------------------------------------------------------------

trie_get_arg_limits ()
{
    # Linux: getconf ARG_MAX
    # Windows/MSYS2: fallback to 8191
    local -A args=()
    local argmax=${ getconf ARG_MAX 2>/dev/null;}

    if [[ -z "$argmax" || "$argmax" == "undefined" ]] ; then
        # Windows hard limits
        # x=${|str_repeat 'a' 32708;}
        # printf "" | gobolt json -m w -k stdin -s "$x" -P -- :key1
        local -i safety=1024
        # 32KB
        args[AVAILABLE]=$((32768-safety))
        args[MAX_ARG_STRLEN]=$((32768-safety))
    else
        # Linux Kernel constants MAX_ARG_STRLEN = 131072(128KB)
        local -i safety=4096
        local -i env_bytes=${|str_bytes "${ export -p;}";}
        args[MAX_ARG_STRLEN]=$((131072-safety))
        args[AVAILABLE]=$((argmax-env_bytes-safety))
    fi

    REPLY=${args[*]@K}
}

#-------------------------------------------------------------------------------

return 0

