#!/usr/bin/bash

COLOR_RED="\033[31m"
COLOR_GREEN="\033[32m"
COLOR_YELLOW="\033[33m"
COLOR_BLUE="\033[34m"
COLOR_RESET="\033[0m"

RESULT_FILE="MANIFEST_check_report.txt"

#-----------------------------------------------------------------------------

get_project_file_list ()
{
local is_globstar_set=0 is_nullglob_set=0 is_dotglob_unset=0

shopt -q globstar || { shopt -s globstar ; is_globstar_set=1 ; }
shopt -q nullglob || { shopt -s nullglob ; is_nullglob_set=1 ; }
shopt -q dotglob  && { shopt -u dotglob  ; is_dotglob_unset=1 ; }

local all_files=()
local file_name ; for file_name in ** ; do
	[[ -f "$file_name" ]] || continue
    all_files+=("$file_name")
done

# files=(a.txt b.txt c.txt d.txt)
# ignored='b.txt
# c.txt'
# printf '%s\n' "${files[@]}" | grep -F -x -v -f <(echo "$ignored")
# a.txt
# d.txt
local git_ignored
git_ignored=$(printf "%s\n" "${all_files[@]}" | git check-ignore --stdin)
printf '%s\n' "${all_files[@]}" | grep -F -x -v -f <(echo "$git_ignored")

((is_globstar_set)) && shopt -u globstar
((is_nullglob_set)) && shopt -u nullglob
((is_dotglob_unset)) && shopt -s dotglob
}

#-----------------------------------------------------------------------------
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

#-----------------------------------------------------------------------------

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

#-----------------------------------------------------------------------------

manifest_file_list=$(<MANIFEST)
manifest_file_list=$(printf "%s" "$manifest_file_list" |
	grep -v '^[[:space:]]*#' |
	grep -v '^[[:space:]]*$' |
	sort)
project_file_list=$(get_project_file_list | sort)

if diff_two_str_side_by_side "$manifest_file_list" "$project_file_list" "$RESULT_FILE" "MANIFEST file list" "project file list" ; then
	echo -e "${COLOR_GREEN}Congratulations, the content is consistent.${COLOR_RESET}"
	exit 0
else
	echo -e "${COLOR_RED}The content is inconsistent, Please check ${RESULT_FILE}!${COLOR_RESET}"
	exit 1
fi

