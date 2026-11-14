#!/usr/bin/env bash
# STRAFE_BASH — 入口（只负责 source game 层入口 + 调 main）
#
# 路径定位说明：
#   - 基于 BASH_SOURCE[0] 自定位，不依赖调用时的 cwd。
#   - 使用 cd -P + pwd -P，会解析“目录部分”的符号链接。
#   - 假设：脚本文件本身不是符号链接。
#     若通过符号链接调用本脚本，STRAFE_PROJ_DIR 将是链接所在目录，
#     而非真实脚本目录；如需支持该场景，需额外用 readlink 解析。
#   - 不使用 readlink/realpath：二者非 POSIX 标准，在部分 Unix 上缺失或选项不兼容；
#       dirname + cd -P + pwd -P 均为 POSIX 标准工具，可用性更广。
STRAFE_PROJ_DIR=$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)
STRAFE_LIB_HOME="$(cd -P -- "$STRAFE_PROJ_DIR/.." >/dev/null 2>&1 && pwd -P)/bashlib"
export STRAFE_PROJ_DIR STRAFE_LIB_HOME
. "$STRAFE_PROJ_DIR/game/main.sh"
main

