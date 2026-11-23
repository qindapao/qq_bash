declare -gA _BASHLIB_IMPORTED
((_BASHLIB_IMPORTED[xj]++)) && return 0

. "${BASH_SOURCE[0]%/*}/x.sh"

# gobolt JSON Object type return value
readonly X_GOBOLT_JSONTYPENULL=1
readonly X_GOBOLT_JSONTYPETRUE=2
readonly X_GOBOLT_JSONTYPEFALSE=3
readonly X_GOBOLT_JSONTYPENUMBER=4
readonly X_GOBOLT_JSONTYPESTRING=5
readonly X_GOBOLT_JSONTYPEARRAY=6
readonly X_GOBOLT_JSONTYPEOBJECT=7
readonly X_GOBOLT_JSONTYPEUNKNOWN=8

readonly X_RET_ENUM_KEY_OTHER_TOOL_NOT_INSTALLED=10
readonly X_RET_ENUM_KEY_BJSON_TYPE_INVALID=11
readonly X_RET_ENUM_KEY_BJSON_TYPE_OBJ=12
# 暂时没有使用，但是建议保留
readonly X_RET_ENUM_KEY_BJSON_TYPE_ARR=13
readonly X_RET_ENUM_KEY_PARAMETER_LENGTH_EXCEEDS_LIMIT=14

#-------------------------------------------------------------------------------

# 在支持 ${ cmd;} 的 shell 上用当前进程捕获 stdout，避免命令替换的 fork；
# 否则回退到 $(...)。命令和参数分开放，eval 只承载语法，不拼接数据。
_xj_capture_stdout ()
{
    local _xj_fn=$1
    shift

    # 5.3 的 ${ cmd;} 旧版解析器不认识；放进 eval 字符串延迟解析，
    # 这样 4.4/5.2 读文件时不会语法报错，只有 5.3 才真正执行。
    if ((BASH_GRAMMAR[current_shell_process_replace])) ; then
        eval 'REPLY=${ "$_xj_fn" "$@";}'
    else
        # $(...) 是通用语法，直接写即可，不需要 eval。
        REPLY=$("$_xj_fn" "$@")
    fi
}

_xj_gobolt_escape_key ()
{
    printf '%s' "$1" | gobolt json -m e -k stdin
}

_xj_gobolt_write_slow ()
{
    local jstr=$1 param=$2 temp=$3
    shift 3
    printf '%s' "$jstr" | gobolt json -m w -k stdin "$param" "$temp" \
        -P -- "$@"
}

_xj_gobolt_read_trie ()
{
    local jstr=$1
    shift
    printf '%s' "$jstr" | gobolt json -m r -t txt -k stdin -F trie \
        -x "$X" -P -- "$@"
}

_xj_gobolt_write_fast ()
{
    printf '' | gobolt json -m w -k stdin -s '' -M -- "$@"
}

# $1: The value of the string that needs to be converted
# $2: Variable name saved after conversion
#
# JSON 路径键转义：转义 [ ] . * ? | @ # { } ! 为带反斜杠的形态。
# @in  $1=原始字符串  $2=输出变量名（nameref）
# @ret 0（始终成功）
x_bjson_key_escape ()
{
    local -n bjsonKeyEscapeR_ekey="$2"

    bjsonKeyEscapeR_ekey="$1"

    if ((${#bjsonKeyEscapeR_ekey}>6666)) ; then
        _xj_capture_stdout _xj_gobolt_escape_key "$bjsonKeyEscapeR_ekey" || return $?
        bjsonKeyEscapeR_ekey=$REPLY REPLY=
        bjsonKeyEscapeR_ekey=${bjsonKeyEscapeR_ekey%?}
    else
        if ((BASH_GRAMMAR[patsub_replacement])) ; then
            local bjsonKeyEscapeR_is_patsub_replacement_on=0
            shopt -q patsub_replacement || {
                shopt -s patsub_replacement
                bjsonKeyEscapeR_is_patsub_replacement_on=1
            }

            # 5.2 patsub_replacement
            bjsonKeyEscapeR_ekey=${bjsonKeyEscapeR_ekey//[$'][\\.*?|@#{}!']/\\&}
            ((bjsonKeyEscapeR_is_patsub_replacement_on)) && shopt -u patsub_replacement
        else
            # Backslashes must be handle first
            bjsonKeyEscapeR_ekey=${bjsonKeyEscapeR_ekey//'\'/'\\'}
            bjsonKeyEscapeR_ekey=${bjsonKeyEscapeR_ekey//']'/'\]'}
            bjsonKeyEscapeR_ekey=${bjsonKeyEscapeR_ekey//'['/'\['}
            bjsonKeyEscapeR_ekey=${bjsonKeyEscapeR_ekey//'.'/'\.'}
            bjsonKeyEscapeR_ekey=${bjsonKeyEscapeR_ekey//'*'/'\*'}
            bjsonKeyEscapeR_ekey=${bjsonKeyEscapeR_ekey//'?'/'\?'}
            bjsonKeyEscapeR_ekey=${bjsonKeyEscapeR_ekey//'|'/'\|'}
            bjsonKeyEscapeR_ekey=${bjsonKeyEscapeR_ekey//'@'/'\@'}
            bjsonKeyEscapeR_ekey=${bjsonKeyEscapeR_ekey//'#'/'\#'}
            bjsonKeyEscapeR_ekey=${bjsonKeyEscapeR_ekey//'{'/'\{'}
            bjsonKeyEscapeR_ekey=${bjsonKeyEscapeR_ekey//'}'/'\}'}
            bjsonKeyEscapeR_ekey=${bjsonKeyEscapeR_ekey//'!'/'\!'}
        fi
    fi
}

#-------------------------------------------------------------------------------

# This function is very slow and is only used for verification.
#
# 慢速 JSON 序列化（每条边 fork 一次 gobolt，仅作验证用）。
# @in  $1=树名  $2=物理全 key（空=整棵树）
# @out REPLY=JSON 字符串
# @ret 0=OK  10=X_RET_ENUM_KEY_OTHER_TOOL_NOT_INSTALLED
#      52=X_RET_ENUM_TREE_NOT_HAVE_ROOT
x_to_json_slow ()
{
    REPLY=
    # local - ; set +x
    local tr_name=$1
    local -n tr_t=$1
    local tr_full_key=$2
    local tr_jstr
    local tr_temp_file=$(mktemp)

    command -v gobolt &>/dev/null || {
        die ERR "gobolt tool is not installed."
        rm -f -- "$tr_temp_file"
        return $X_RET_ENUM_KEY_OTHER_TOOL_NOT_INSTALLED
    }

    [[ -z "${tr_t[$X_ROOT_ID.s]}" ]] && {
        rm -f -- "$tr_temp_file"
        case "${tr_t[$X_ROOT_ID.t]}" in
        $X_TYPE_OBJ)   REPLY='{}' ; return $X_RET_ENUM_OK ;;
        $X_TYPE_ARR)   REPLY='[]' ; return $X_RET_ENUM_OK ;;
        *)  return $X_RET_ENUM_TREE_NOT_HAVE_ROOT  ;;
        esac
    }

    x_to_json_slow_cb ()
    {
        local node_kind=$1
        local index_full_key=$3 value=$4
        local -a w_x_to_json_slow_cb__tokens=()
        _split_tokens w_x_to_json_slow_cb__tokens "$index_full_key" || return $?
        local -a bjson_params=()
        local token
        local write_jstr_param='-f'

        case "$node_kind" in
        $X_NODE_KIND_LEAF)
            case "$value" in
            $X_VALUE_TRUE) value='true'   ;;
            $X_VALUE_FALSE) value='false' ;;
            # 默认是正常浮点，不拦截；去掉尾部 $X 后直接写入
            *"$X")  value=${value%"$X"}    ;;
            *) write_jstr_param='-o'       ;;
            esac
            ;;
        $X_NODE_KIND_LEAF_NULL) value='null' ;;
        $X_NODE_KIND_ARR_EMPTY) value='[]'   ;;
        $X_NODE_KIND_OBJ_EMPTY) value='{}'   ;;
        *)  return $X_RET_ENUM_OK            ;;
        esac

        for token in "${w_x_to_json_slow_cb__tokens[@]}" ; do
            case "$token" in
            '{'*'}') bjson_params+=(":${token:1:-1}")   ;;
            '['*']') bjson_params+=("${token:1:-1}")    ;;
            esac
        done

        printf '%s' "$value" >"$tr_temp_file"

        _xj_capture_stdout _xj_gobolt_write_slow \
            "$tr_jstr" "$write_jstr_param" "$tr_temp_file" \
            "${bjson_params[@]}" || return $?
        tr_jstr=$REPLY REPLY=

        return $X_RET_ENUM_OK
    }

    x_walk "$tr_name" "$tr_full_key" x_to_json_slow_cb ; local tr_rc=$?
    rm -f -- "$tr_temp_file"
    (( tr_rc )) && return $tr_rc
    REPLY=$tr_jstr
}

#-------------------------------------------------------------------------------

# 快速 JSON 序列化（一次性 fork gobolt，超长参数自动降级到 slow）。
# @in  $1=树名  $2=物理全 key（空=整棵树）
# @out REPLY=JSON 字符串
# @ret 0=OK  10=OTHER_TOOL_NOT_INSTALLED
#      14=PARAMETER_LENGTH_EXCEEDS_LIMIT  52=TREE_NOT_HAVE_ROOT
x_to_json ()
{
    REPLY=
    # local - ; set +x
    local tr_name=$1
    local -n tr_t=$1
    local tr_full_key=$2
    local -a tr_gobolt_params=()

    command -v gobolt &>/dev/null || {
        die ERR "gobolt tool is not installed."
        return $X_RET_ENUM_KEY_OTHER_TOOL_NOT_INSTALLED
    }

    [[ -z "${tr_t[$X_ROOT_ID.s]}" ]] && {
        case "${tr_t[$X_ROOT_ID.t]}" in
        $X_TYPE_OBJ)   REPLY='{}' ; return $X_RET_ENUM_OK ;;
        $X_TYPE_ARR)   REPLY='[]' ; return $X_RET_ENUM_OK ;;
        *)  return $X_RET_ENUM_TREE_NOT_HAVE_ROOT  ;;
        esac
    }

    x_to_json_cb ()
    {
        local node_kind=$1
        local index_full_key=$3 value=$4
        local w_x_to_json_cb__tokens=()
        _split_tokens w_x_to_json_cb__tokens "$index_full_key" || return $?
        local -a bjson_params=()
        local token

        case "$node_kind" in
        $X_NODE_KIND_LEAF)
            case "$value" in
            $X_VALUE_TRUE)     value='j:true'        ;;
            $X_VALUE_FALSE)    value='j:false'       ;;
            *"$X")              value=j:${value%"$X"} ;;
            *)                  value=s:${value}      ;;
            esac
            ;;
        $X_NODE_KIND_LEAF_NULL) value='j:null' ;;
        $X_NODE_KIND_ARR_EMPTY) value='j:[]'   ;;
        $X_NODE_KIND_OBJ_EMPTY) value='j:{}'   ;;
        *)  return $X_RET_ENUM_OK            ;;
        esac

        for token in "${w_x_to_json_cb__tokens[@]}" ; do
            case "$token" in
            '{'*'}')
                x_bjson_key_escape "${token:1:-1}" token
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

        return $X_RET_ENUM_OK
    }

    x_walk "$tr_name" "$tr_full_key" x_to_json_cb || return $?

    # printf '%s\n' "${tr_gobolt_params[@]}"

    local tr_i
    local -A w_x_to_json__system_limits=()
    x_get_arg_limits w_x_to_json__system_limits "${#tr_gobolt_params[@]}"

    # Check if each parameter exceeds
    # If it is found to be exceeded, the report will fail.

    for((tr_i=0;tr_i<${#tr_gobolt_params[@]};tr_i+=2)) ; do
        str_bytes "${tr_gobolt_params[tr_i]}"
        local -i tr_key_len=$REPLY ; REPLY=

        ((  tr_key_len>=${w_x_to_json__system_limits[MAX_ARG_STRLEN]} )) && {
            die ERR "Command line parameters exceed limit"
            return $X_RET_ENUM_KEY_PARAMETER_LENGTH_EXCEEDS_LIMIT
        }
    done

    str_bytes "${tr_gobolt_params[*]}"
    local -i tr_all_param_byte_len=$REPLY ; REPLY=

    if ((tr_all_param_byte_len>=${w_x_to_json__system_limits[AVAILABLE]})) ; then
        x_to_json_slow "$tr_name" "$tr_full_key" ; return $?
    else
        _xj_capture_stdout _xj_gobolt_write_fast \
            "${tr_gobolt_params[@]}" || return $?
    fi
}

#-------------------------------------------------------------------------------

# JSON 反序列化为树，结果直接写入调用方关联数组。
# @in  $1=输出关联数组名（调用方先声明 local -A）
#      $2=JSON 字符串  $3..=go 侧需要的 bjson 路径（可选）
# @out $1=新树（关联数组 KV 格式）
# @ret 0=OK  10=OTHER_TOOL_NOT_INSTALLED  11=BJSON_TYPE_INVALID
x_from_json ()
{
    REPLY=
    # local - ; set +x
    local -n w_tree=$1 ; w_tree=()
    local tr_json_str=$2
    local tr_bjson_keys="${@:3}"

    command -v gobolt &>/dev/null || {
        die ERR "gobolt tool is not installed."
        return $X_RET_ENUM_KEY_OTHER_TOOL_NOT_INSTALLED
    }

    local tr_assoc
    local -i tr_json_ret
    _xj_capture_stdout _xj_gobolt_read_trie \
        "$tr_json_str" "${tr_bjson_keys[@]}"
    tr_json_ret=$?
    tr_assoc=$REPLY REPLY=
    case "$tr_json_ret" in
    $X_GOBOLT_JSONTYPEARRAY|$X_GOBOLT_JSONTYPEOBJECT)
        local -A "tr_assoc=($tr_assoc)" ;;&
    $X_GOBOLT_JSONTYPEARRAY)
        x_init "$1" "$X_TYPE_ARR" ;;
    $X_GOBOLT_JSONTYPEOBJECT)
        x_init "$1" "$X_TYPE_OBJ" ;;
    *)
        die ERR "bjson key:${tr_bjson_keys[*]} type is known."
        return $X_RET_ENUM_KEY_BJSON_TYPE_INVALID
        ;;
    esac

    local tr_key
    for tr_key in "${!tr_assoc[@]}" ; do
        x_insert "$1" "$tr_key" "${tr_assoc[$tr_key]}"
    done
    
    # x_dump "$1"
}

#-------------------------------------------------------------------------------

# 探测系统命令行参数限制，用于 x_to_json 决定是否降级。
# @in  $1=输出关联数组名（调用方先声明 local -A）  $2=参数数量（默认 0）
# @out $1=关联数组 KV：MAX_ARG_STRLEN AVAILABLE
# @ret 0
x_get_arg_limits ()
{
    REPLY=
    # Linux: getconf ARG_MAX
    # Windows/MSYS2: fallback to 8191
    local -n w_args=$1 ; w_args=()
    local -i argc_cnt=${2:-0}
    local argmax=$( getconf ARG_MAX 2>/dev/null )

    if [[ -z "$argmax" || "$argmax" == "undefined" ]] ; then
        # Windows hard limits
        # str_repeat 'a' 32708 ; x=REPLY REPLY=
        # printf '' | gobolt json -m w -k stdin -s "$x" -P -- :key1
        local -i safety=1024
        # 32KB
        w_args[MAX_ARG_STRLEN]=$((32768-safety))
        local -i msys_overhead=$(( argc_cnt * 2 ))
        # 预扣空格和引号的开销（每个参数至少 1~2 个字符）
        w_args[AVAILABLE]=$((32768-safety-msys_overhead))
    else
        # Linux Kernel constants MAX_ARG_STRLEN = 131072(128KB)
        local -i safety=4096
        local -i env_bytes
        _xj_capture_stdout export -p || return $?
        str_bytes "$REPLY"
        env_bytes=$REPLY REPLY=
        # 扣除指针数组开销, 64位系统每个指针 8 字节
        local -i ptr_overhead=$((argc_cnt * 8))
        # 128k MAX_ARG_STRLEN 内核头文件中
        w_args[MAX_ARG_STRLEN]=$((131072-safety))
        w_args[AVAILABLE]=$((argmax-env_bytes-safety-ptr_overhead))
    fi
}

return 0

