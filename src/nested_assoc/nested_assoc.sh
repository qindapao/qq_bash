#!/usr/bin/env bash

((_NESTED_ASSOC_IMPORTED++)) && return 0

# nested assoc sub sep
# SEP needs to wrap the tail of the key to eliminate ambiguity
SEP=$'\034'

# declare -A nested_assoc_tmp=()
# - add leaf key(Check for empty keys. Empty keys are not allowed to be inserted.)
# nested_assoc_tmp["key1${SEP}key2${SEP}key3${SEP}"]="something"
# - delete leaf key
# unset -v nested_assoc_tmp["key1${SEP}key2${SEP}key3${SEP}"]

na_tree_delete ()
{
    eval -- local -A base_tree=($1)
    local base_key=$2 key
    for key in "${!base_tree[@]}" ; do
        [[ "$key" != "${base_key}"* ]] && {
            REPLY+=" ${key@Q}"
            REPLY+=" ${base_tree[$key]@Q}"
        }
    done
}

na_tree_get ()
{
    eval -- local -A base_tree=($1)
    local base_key=$2
    local key sub_key
    for key in "${!base_tree[@]}" ; do
        [[ "$key" == "${base_key}"* ]] && {
            sub_key=${key#"$base_key"}
            [[ -n "$sub_key" ]] && {
                REPLY+=" ${sub_key@Q}"
                REPLY+=" ${base_tree[$key]@Q}"
            }
        }
    done
}

na_tree_merge () { _na_tree_add "$@" 'merge' ; }
na_tree_replace () { _na_tree_add "$@" 'replace' ; }

na_tree_get_len ()
{
    :
}

na_tree_walk ()
{
    :
}


# Key iterator, returns a Q string list of keys
# The reason why Q string protection is used is to prevent newline characters
# from appearing in the key.
# The caller needs to first set IFS=$'\n' Then do Q string eval reduction when using it
na_tree_iter ()
{
    eval -- local -A base_tree=($1)
    local base_key=$2
    local key sub_key

    REPLY=""
    for key in "${!base_tree[@]}"; do
        if [[ -z "$base_key" ]]; then
            sub_key=${key%%"$SEP"*}
        else
            [[ "$key" != "$base_key"* ]] && continue
            sub_key=${key#"$base_key"}
            # Remove the SEP at the beginning
            [[ "$sub_key" == "$SEP"* ]] && sub_key=${sub_key#"$SEP"}
            # Just take down one level
            sub_key=${sub_key%%"$SEP"*}
        fi
        [[ -n "$sub_key" ]] && REPLY+="${REPLY:+$'\n'}${sub_key}"
    done
}

na_tree_print ()
{
    local print_name="$1"
    eval -- local -A print_tree=($2)
    local prefix="${3%$SEP}" indent="$4" key
    local -A strip_tree=()

    # Remove the last SEP from all keys. If empty keys are found, delete them.
    for key in "${!print_tree[@]}" ; do
        [[ -n "${key%$SEP}" ]] && strip_tree[${key%$SEP}]=${print_tree[$key]}
    done

    echo "${print_name} =>"
    local -a sorted_keys=("${!strip_tree[@]}")
    eval -- sorted_keys=($(printf "%s\n" "${sorted_keys[@]@Q}" | sort))

    _na_tree_print "${strip_tree[*]@K}" "${sorted_keys[*]@Q}" "$prefix" "$indent"
}

_na_tree_add ()
{
    eval -- local -A base_tree=($1)
    eval -- local -A sub_tree=($2)
    local base_key=$3
    # You can also choose merge
    local mode=${4:-replace}

    case "$mode" in
    merge)      REPLY=${base_tree[*]@K} ;;
    replace)    REPLY=${| na_tree_delete "${base_tree[*]@K}" "$base_key" ;}
    esac

    local sub_key ; for sub_key in "${!sub_tree[@]}" ; do
        : "${base_key}${sub_key}" ; REPLY+=" ${_@Q}"
        REPLY+=" ${sub_tree[$sub_key]@Q}"
    done
}

_na_tree_print ()
{
    eval -- local -A print_tree=($1)
    eval -- local -a sorted_keys=($2)
    local prefix="$3" indent="$4"
    local -A subkeys=()
    local -a subkeys_order=()
    local fullkey rest subkey
    local -A rest_tree=()
    local -a rest_sorted_keys=()

    # Collect the leaves and values of the current layer,
    # and the subkey set of the next layer
    local index
    for index in "${!sorted_keys[@]}"; do
        fullkey=${sorted_keys[$index]}
        if [[ -z "$prefix" || "$fullkey" == "$prefix"* ]]; then
            rest="${fullkey#$prefix}"
            # If there is a level prefix, the remaining part will start with SEP,
            # remove it
            [[ "$rest" == "$SEP"* ]] && rest="${rest#$SEP}"

            if [[ "$rest" == *"$SEP"* ]]; then
                subkey="${rest%%"$SEP"*}"
                [[ -z "${subkeys[$subkey]}" ]] && {
                    subkeys["$subkey"]=1
                    subkeys_order+=("$subkey")
                }
                rest_tree["$fullkey"]=${print_tree[$fullkey]}
                rest_sorted_keys+=("$fullkey")
            elif [[ -n "$rest" ]]; then
                echo "${indent}${rest} => ${print_tree[$fullkey]}"
            fi
        else
            rest_tree["$fullkey"]=${print_tree[$fullkey]}
            rest_sorted_keys+=("$fullkey")
        fi
    done

    if ((${#subkeys_order[@]})); then
        local next_prefix
        for subkey in "${subkeys_order[@]}" ; do
            echo "${indent}${subkey} =>"
            if [[ -z "$prefix" ]]; then
                next_prefix="$subkey"
            else
                next_prefix="${prefix}${SEP}${subkey}"
            fi
            _na_tree_print "${rest_tree[*]@K}" "${rest_sorted_keys[*]@Q}" "$next_prefix" "    ${indent}"
        done
    fi
}



declare -A nested_assoc_tmp=()
nested_assoc_tmp["key1${SEP}key2${SEP}key3${SEP}"]="something1"
nested_assoc_tmp["key1${SEP}key2${SEP}key4${SEP}"]="something2"
nested_assoc_tmp["key1${SEP}keyx${SEP}"]="something3"
nested_assoc_tmp["key1${SEP}keyy${SEP}xx${SEP}"]="something4"
nested_assoc_tmp["keym${SEP}"]="something5"

declare -A sub_tree=()
sub_tree["sub1${SEP}xx${SEP}"]=1
sub_tree["sub2${SEP}yy${SEP}"]=2
sub_tree["su b2${SEP}kk${SEP}"]=3
sub_tree["su b2${SEP}0${SEP}"]=3
sub_tree["su b2${SEP}1${SEP}"]=3
sub_tree["su b2${SEP}2${SEP}"]=3
sub_tree["su b2${SEP}3${SEP}"]=3
sub_tree["su b2${SEP}4${SEP}"]=3
sub_tree["su b2${SEP}5${SEP}"]=3
sub_tree["su b2${SEP}6${SEP}"]=3
sub_tree["su b2${SEP}7${SEP}"]=3
sub_tree["su b2${SEP}8${SEP}"]=3
sub_tree["su b2${SEP}9${SEP}"]=3
sub_tree["su b2${SEP}10${SEP}"]=3
sub_tree["su b2${SEP}11${SEP}"]=3

declare -A plus_tree=()
eval -- plus_tree=(${| na_tree_replace "${nested_assoc_tmp[*]@K}" "${sub_tree[*]@K}" "key1${SEP}key2${SEP}" ;})

na_tree_print "plus_tree" "${plus_tree[*]@K}" "" "    "

declare -A get_sub_tree=()
eval -- get_sub_tree=(${| na_tree_get "${plus_tree[*]@K}" "key1${SEP}key2${SEP}" ;})

na_tree_print "get_sub_tree" "${get_sub_tree[*]@K}" "" "    "


