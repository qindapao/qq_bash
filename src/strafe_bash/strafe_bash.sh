#!/usr/bin/env bash
# STRAFE_BASH — 入口（只负责 source game 层入口 + 调 main）
: "${STRAFE_LIB_HOME:=../bashlib}"
. "$(dirname "${BASH_SOURCE[0]}")/game/main.sh"
main
