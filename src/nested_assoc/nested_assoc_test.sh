#!/usr/bin/env bash

. nested_assoc.sh


test_na_tree_iter ()
{
    local IFS=$'\n'
    
    local lev1 lev2 lev3 lev4
    local my_type my_key

    for lev1 in ${| na_tree_iter "${plus_tree[*]@K}" ;} ; do
        IFS=' ' ; set -- $lev1 ; eval -- my_key=$2 ; my_type=$1
        IFS=$'\n'
        declare -p my_key my_type
    done
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
sub_tree["su
b2 b3${SEP}112${SEP}"]='gge
gege

geg

'

declare -A plus_tree=()
eval -- plus_tree=(${|na_tree_add_sub "${nested_assoc_tmp[*]@K}" "key1${SEP}key2${SEP}" "${sub_tree[*]@K}";})

na_tree_print "nested_assoc_tmp" "${nested_assoc_tmp[*]@K}"
na_tree_print "nested_assoc_tmp" "${nested_assoc_tmp[*]@K}" "key1${SEP}"
na_tree_print "plus_tree" "${plus_tree[*]@K}"

declare -A get_sub_tree=()
eval -- get_sub_tree=(${|na_tree_get "${plus_tree[*]@K}" "key1${SEP}key2${SEP}";})

na_tree_print "get_sub_tree" "${get_sub_tree[*]@K}"

test_na_tree_iter
na_tree_walk "${plus_tree[*]@K}"

test_xx ()
{
    local mx='"xz kk" "12 45"'
    local IFS=' '
    eval -- set -- $mx
    echo $1
    echo $2
    echo $3
    echo $4
    
}

na_tree_node_type "${get_sub_tree[*]@K}" "sub1${SEP}"
echo $?

declare -A tree=()
eval -- tree=(${|na_tree_add_leaf "${tree[*]@K}" "key1${SEP}" "var1";})
eval -- tree=(${|na_tree_add_leaf "${tree[*]@K}" "key2${SEP}" "var2";})
eval -- tree=(${|na_tree_add_leaf "${tree[*]@K}" "key2${SEP}key-3${SEP}" "var2";})
eval -- tree=(${|na_tree_add_leaf "${tree[*]@K}" "key3${SEP}key-3${SEP}key4${SEP}" "var234";})
na_tree_print "tree" "${tree[*]@K}"

declare -A sub_tree2=()
eval -- sub_tree2=(${|na_tree_add_leaf "${sub_tree2[*]@K}" "key1${SEP}" "var1";})
eval -- sub_tree2=(${|na_tree_add_leaf "${sub_tree2[*]@K}" "key2${SEP}" "var2";})
eval -- sub_tree2=(${|na_tree_add_leaf "${sub_tree2[*]@K}" "key2${SEP}key-3${SEP}" "var2";})
eval -- sub_tree2=(${|na_tree_add_leaf "${sub_tree2[*]@K}" "key3${SEP}key-3${SEP}key4${SEP}" "var234";})
eval -- tree=(${|na_tree_add_sub "${tree[*]@K}" "key1${SEP}" "${sub_tree2[*]@K}";})
eval -- tree=(${|na_tree_add_sub "${tree[*]@K}" "key4${SEP}key-3${SEP}" "${sub_tree2[*]@K}";})
na_tree_print "sub_tree" "${sub_tree2[*]@K}"
na_tree_print "tree" "${tree[*]@K}"

declare -A my_get_sub_tree=()
eval -- my_get_sub_tree=(${|na_tree_get "${tree[*]@K}" "key4${SEP}key-3${SEP}";})
na_tree_print "my_get_sub_tree" "${my_get_sub_tree[*]@K}"

