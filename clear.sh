#!/usr/bin/env bash
# clear.sh — 清理构建产物 + 本地临时数据（不动源码、不动 .git、不动 .bench）
#
# 清理范围：
#   * build.sh 生成的所有 .sh（等价于 ./build.sh -d）
#   * 游戏存档 .strafe_save（测试/试玩产生）
#   * ./test.sh 的报告 test_report_*.txt
#   * 运行错误日志（默认 /tmp/strafe_bash.err，可用 $STRAFE_ERRLOG 覆盖）
#   * 编辑器临时文件 *.swp / *.temp
set -u

cd "$(dirname "$0")" || exit 1

echo '== 构建产物 =='
./build.sh -d || exit 1

echo '== 运行/测试临时数据 =='
shopt -s nullglob

_save_files=(./.strafe_save)
for _f in "${_save_files[@]}" ; do
    [[ -e "$_f" ]] && { rm -f "$_f" ; echo "removed: $_f" ; }
done

_report_files=(./test_report_*.txt)
if (( ${#_report_files[@]} )) ; then
    rm -f "${_report_files[@]}"
    printf 'removed: %s\n' "${_report_files[@]}"
fi

_tmp_files=(./*.swp ./*.temp)
if (( ${#_tmp_files[@]} )) ; then
    rm -f "${_tmp_files[@]}"
    printf 'removed: %s\n' "${_tmp_files[@]}"
fi

_errlog=${STRAFE_ERRLOG:-/tmp/strafe_bash.err}
if [[ -e "$_errlog" ]] ; then
    rm -f "$_errlog"
    echo "removed: $_errlog"
fi

echo 'done'
