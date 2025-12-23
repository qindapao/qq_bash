#!/usr/bin/env bash

. trie.sh

diff_two_str_side_by_side ()
{
local str1="$1" str2="$2" result_file="$3"
local title1="$4" title2="$5"
local ret_code=0
local max1=$(printf "%s" "$str1" | display_max)
local max2=$(printf "%s" "$str2" | display_max)
local max=$(( max1 > max2 ? max1 : max2 ))
local width=$(( max * 2 + 4 ))

{
printf '%.0s-' $(seq 1 "$width") ; echo ""
printf "%-*s    %-*s\n" "$max" "$title1" "$max" "$title2"
printf '%.0s-' $(seq 1 "$width") ; echo ""
diff --minimal --side-by-side --expand-tabs --tabsize=4 --color --width=${width} -y <(printf "%s" "$str1") <(printf "%s" "$str2")
} | tee "$result_file"

ret_code=${PIPESTATUS[0]}
echo ""
return $ret_code
}

display_max()
{
awk '
	BEGIN {
		max = 0
	}
	{
		line = $0
		width = length(line)
		max = (width > max ? width : max)
	}
	END {
		print max
	}'
}



eval -- declare -A t=(${|trie_init;})

trie_insert "t" "lev1-1${S}lev2-1${S}lev3-1${S}" "value1"
trie_insert "t" "lev1-1${S}lev2-2${S}11${S}" "value11"
trie_insert "t" "lev1-1${S}lev2-2${S}0${S}" "value0"
trie_insert "t" "lev1-1${S}lev2-2${S}1${S}" "value0"
trie_insert "t" "lev1-1${S}lev2-2${S}2${S}" "value0"
trie_insert "t" "lev1-1${S}lev2-2${S}3${S}" "value0"
trie_insert "t" "lev1-1${S}lev2-2${S}4${S}" "value0"
trie_insert "t" "lev1-1${S}lev2-3${S}lev3-1${S}lev4-1${S}" "value10"
trie_insert "t" "lev1-1${S}lev2-3${S}lev3-1${S}lev4-2${S}" "value10"
trie_insert "t" "lev1-1${S}lev2-3${S}lev3-1${S}lev4-2${S}" "value10new"
trie_insert "t" "lev1-1${S}lev2-3${S}lev3-1${S}lev4-x
gegeg
gggxxxxxxxx${S}" "value1
gge
geggg0new
"

get_str1=$(printf "%s => %s\n" "${t[@]@k}" | sort)
trie_dump "t"
printf "%s => %s\n" "${t[@]@k}" | sort
exit 0


trie_delete "t" "lev1-1${S}lev2-3${S}lev3-1${S}"

get_str2=$(printf "%s => %s\n" "${t[@]@k}" | sort)
trie_dump "t"
diff_two_str_side_by_side "$get_str1" "$get_str2" "trie_test.txt"

trie_delete "t" "lev1-1${S}lev2-2${S}11${S}"
trie_delete "t" "lev1-1${S}lev2-2${S}0${S}"
trie_delete "t" "lev1-1${S}lev2-1${S}"

trie_dump "t"
get_str3=$(printf "%s => %s\n" "${t[@]@k}" | sort)
diff_two_str_side_by_side "$get_str2" "$get_str3" "trie_test.txt"

