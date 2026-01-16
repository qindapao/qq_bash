((_META_IMPORTED++)) && return 0

. "${BASH_SOURCE[0]%/*}/trie.sh"


# Maintain a global resource pool and save the mapping relationship of
# namespace:id => physical full_key
# The meaning of the namespace is a user-defined global variable that is valid
# throughout the life cycle.
#
# In this way, users can define multiple objects without repeatedly binding
# variable names.

# [OBJ1.45]="{key1}$X{key2}$X<123>$X"
# [OBJ1.46]="{key1}$X{key2}$X<124>$X"
# NAME SPACE MAP
declare -gA NS_MAP=()

#-------------------------------------------------------------------------------

# Hooking method and SUPER.
#
# Although aliases can be used to define methods in a more object-oriented style
# xx.func_name "$1" "$2"
# However, aliases have many pitfalls, and sometimes the expansion is unstable,
# so it is best to give up.
# alias ${obj_name}.cut_plus="cut_plus_my_class ${obj_name}"
# Unalias management of aliases is also very troublesome.
# Use case to distinguish methods and properties
# All caps: can only be attributes
# All lowercase: can only be methods
bless ()
{
    local tr_class=$1
    local tr_na=$2
    local tr_ni=$3
    local tr_np=$4

    # CLASS Add the hook class name to the attribute
    local tr_class_chain
    tr_class_chain=${|trie_get_leaf "$tr_na" "${tr_np}{CLASS}$X" 2>/dev/null;}
    tr_class_chain="${tr_class}${tr_class_chain:+ -> }${tr_class_chain}"

    trie_insert "$tr_na" "$tr_np{CLASS}$X" "$tr_class_chain" "$tr_ni" "$tr_np"

    local tr_fn_name ; for tr_fn_name in ${ compgen -A function;} ; do
        case "$tr_fn_name" in
        new_${tr_class}|bless_${tr_class}|setup_${tr_class}) : ;;
        # FN: Last level method
        #SUPER: The parent tr_class method corresponding to each subclass method
        *_${tr_class})
            local tr_key=${tr_fn_name%"_$tr_class"}
            local tr_super=${|trie_get_leaf "$tr_na" "$tr_np{$tr_key}$X" 2>/dev/null;}

            trie_insert "$tr_na" "$tr_np{$tr_key}$X" "$tr_fn_name $tr_na $tr_ni" "$tr_ni" "$tr_np"
            trie_insert "$tr_na" "$tr_np{SUPER}$X{$tr_fn_name}$X" "${tr_super:-:}" "$tr_ni" "$tr_np"
            ;;
        esac
    done
}

#-------------------------------------------------------------------------------

die ()
{
    echo "[ERROR] $*" >&2
    echo "Call stack:" >&2
    local i
    for ((i=1; i<${#FUNCNAME[@]}; i++)); do
        echo "  $i: ${FUNCNAME[$i]}() at ${BASH_SOURCE[$i]}:${BASH_LINENO[$((i-1))]}" >&2
    done
}

#-------------------------------------------------------------------------------

return 0

