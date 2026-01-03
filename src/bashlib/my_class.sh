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
#     {BASE}(3) => mid_class
#     {CLASS}(2) => my_class
#     {FN}(8)
#         {cut_plus}(9) => cut_plus_my_class demo_tree
#         {haha}(15) => haha_mid_class demo_tree
#         {print_self}(12) => print_self_base_class demo_tree
#     {PROP}(4)
#         {CNT}(7) => 10
#         {P1}(5) => yy
#         {P2}(6) => 5
#     {SUPER}(10)
#         {cut_plus_base_class}(11) => :
#         {cut_plus_mid_class}(14) => cut_plus_base_class demo_tree
#         {cut_plus_my_class}(17) => cut_plus_mid_class demo_tree
#         {haha_mid_class}(16) => :
#         {print_self_base_class}(13) => :
#     max_index => 18


. "${BASH_SOURCE[0]%/*}/trie.sh"
. "${BASH_SOURCE[0]%/*}/meta.sh"
. "${BASH_SOURCE[0]%/*}/mid_class.sh"

setup_my_class ()
{
    local tr_self=$1
    local tr_my_obj_name=$2
    local tr_value1=$3
    local tr_value2=$4
    local tr_cnt_demo=$5

    trie_insert "$tr_self" "{SELF}$S" "$tr_my_obj_name"
    trie_insert "$tr_self" "{PROP}$S{P1}$S" "$tr_value1"
    trie_insert "$tr_self" "{PROP}$S{P2}$S" "$tr_value2"
    trie_insert "$tr_self" "{PROP}$S{CNT}$S" "$tr_cnt_demo"
}

new_my_class ()
{
    local tr_my_obj_name=$1
    local tr_value1=$2
    local tr_value2=$3
    local tr_cnt_demo=$4

    local -A "tr_my_obj=(${|trie_init "${TR_TYPE_OBJ}";})"
    
    setup_my_class "tr_my_obj" "$tr_my_obj_name" "$tr_value1" "$tr_value2" "$tr_cnt_demo" 
    bless_my_class "tr_my_obj" "$tr_my_obj_name"

    REPLY=${tr_my_obj[*]@K}
    return 0
}

bless_my_class ()
{
    # Bless the parent first and then bless self
    bless_mid_class "$1" "$2"
    bless my_class "$1" "$2"
}


cut_plus_my_class ()
{
    local -n tr_self=$1

    ${tr_self[{SUPER}$S{${FUNCNAME[0]}}$S]}
    
    local tr_cnt=${|trie_get_leaf "$1" "{PROP}$S{CNT}$S";}
    ((tr_cnt++))
    tr_self[{PROP}$S{CNT}$S]=$tr_cnt
}

return 0

