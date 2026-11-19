# config/version.sh — 版本号唯一来源
#
# 为什么单独一个文件：cli.sh 在 main.sh 之前加载（--theme 要先于 color.sh），
# 那时 const.sh 还没被 source；帮助信息又必须显示版本号。
declare -gA _STRAFE_LOADED
(( _STRAFE_LOADED[version]++ )) && return 0

STRAFE_VERSION='v1.0.1'
