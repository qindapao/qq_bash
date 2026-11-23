declare -gA _BASHLIB_IMPORTED
((_BASHLIB_IMPORTED[float]++)) && return 0

#-------------------------------------------------------------------------------

# Return value
# 0: $1>$2
# 1: $1=$2
# 2: $1<$2
# BEGIN here is required, it is executed before any input line, otherwise it will wait for input
# The exit code of the awk command here is the exit code of the function
float_compare () { awk -v a="$1" -v b="$2" 'BEGIN {exit (a>b?0:(a==b?1:2))}' ; }

#-------------------------------------------------------------------------------


return 0

