((_MY_CLASS_IMPORTED++)) && return 0

# :TODO: The biggest problem with the current architecture is that the variable
# name is bound to the tree. If the object contains other objects, or the local
# variable is destroyed, it will be destroyed. Only one or more global trees
# should be initialized, and then all objects can only get IDs. These global
# trees can be understood as memory pools or namespaces.
#
# So now the object initialization function can only return the ID in a certain
# namespace (equivalent to the memory address). After the initialization object
# is attached to the global tree, the ID may change. The global variable name
# may still need to be passed in, but then it is not called a global variable.
# That is a namespace. We can also design more than one namespace.
#
# The current design is sufficient in most scenarios. If there are more complex
# requirements in the future, system needs to be redesigned. The current
# feature is that it is simple and fast. The structure is also clear.
#
# A simple fix currently implemented is that when the binding name of the
# object changes, we use the rebind_self atomic function to change the binding
# name, and then the object can be operated. After the operation is completed,
# the object can be stuffed back into the large object.

# demo_tree
#     {print_self}(12) => print_self_base_class demo_tree
#     {haha}(10) => haha_mid_class demo_tree
#     {cut_plus}(7) => cut_plus_my_class demo_tree
#     {SUPER}(8)
#         {print_self_base_class}(13) => :
#         {haha_mid_class}(15) => haha_base_class demo_tree
#         {haha_base_class}(11) => :
#         {cut_plus_my_class}(16) => cut_plus_mid_class demo_tree
#         {cut_plus_mid_class}(14) => cut_plus_base_class demo_tree
#         {cut_plus_base_class}(9) => :
#     {SELF}(2) => demo_tree
#     {P2}(4) => 5
#     {P1}(3) => yy
#     {CNT}(5) => 10
#     {CLASS}(6) => my_class -> mid_class -> base_class
#     max_index => 17

. "${BASH_SOURCE[0]%/*}/trie.sh"
. "${BASH_SOURCE[0]%/*}/meta.sh"
. "${BASH_SOURCE[0]%/*}/mid_class.sh"

#-------------------------------------------------------------------------------

setup_my_class ()
{
    local tr_na=$1
    local tr_np=$2
    local tr_value1=$3
    local tr_value2=$4
    local tr_cnt_demo=$5

    trie_insert "$tr_na" "$tr_np{SELF}$X" "$tr_na"
    trie_insert "$tr_na" "$tr_np{P1}$X" "$tr_value1"
    trie_insert "$tr_na" "$tr_np{P2}$X" "$tr_value2"
    trie_insert "$tr_na" "$tr_np{CNT}$X" "$tr_cnt_demo"

    # Place other objects
    trie_insert "$tr_na" "$tr_np{ELEMENTS}$X" "$TR_VALUE_NULL_ARR"
}

#-------------------------------------------------------------------------------

# ns: name space
new_my_class ()
{
    local tr_na=$1
    local tr_ni=$2
    local tr_np=$3
    local tr_value1=$4
    local tr_value2=$5
    local tr_cnt_demo=$6
    
    NS_MAP["$tr_na.$tr_ni"]=$tr_np
    setup_my_class  "$tr_na" "$tr_np" \
                    "$tr_value1" "$tr_value2" "$tr_cnt_demo" 

    bless_my_class "$tr_na" "$tr_ni" "$tr_np"

    return 0
}

#-------------------------------------------------------------------------------

bless_my_class ()
{
    # Bless the parent first and then bless self
    bless_mid_class "$@"
    bless my_class "$@"
}

#-------------------------------------------------------------------------------

cut_plus_my_class ()
{
    local -n tr_ns=$1
    local tr_na=$1
    local tr_ni=$2
    local tr_key=${NS_MAP[$tr_na.$tr_ni]}

    ${tr_ns[$tr_key{SUPER}$X{${FUNCNAME[0]}}$X]}
    
    local tr_cnt=${|trie_get_leaf "$tr_na" "$tr_key{CNT}$X";}
    ((tr_cnt++))
    tr_ns[$tr_key{CNT}$X]=$tr_cnt
}

#-------------------------------------------------------------------------------

special_my_my_class ()
{
    :
}

#-------------------------------------------------------------------------------

return 0

