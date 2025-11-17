#!/usr/bin/env bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

print_help() {
    echo "用法: $0 [选项] <目录>"
    echo
    echo "选项:"
    echo "  -h, --help        显示帮助信息"
    echo "  -o, --only-dirty  只显示有问题的仓库，不显示干净仓库"
    echo
    echo "示例:"
    echo "  $0 ~/projects"
    echo "  $0 --only-dirty /d/code"
    echo "  $0 -o /d/code"
}

# 参数解析
ONLY_DIRTY=0
ROOT_DIR=""

for arg in "$@"; do
  case "$arg" in
    -h|--help)
      print_help
      exit 0
      ;;
    -o|--only-dirty)
      ONLY_DIRTY=1
      ;;
    *)
      ROOT_DIR="$arg"
      ;;
  esac
done

# 如果没有传目录，打印帮助并退出
if [ -z "$ROOT_DIR" ]; then
    print_help
    exit 1
fi

for dir in "$ROOT_DIR"/*; do
    if [ -d "$dir/.git" ]; then
        cd "$dir" || continue

        status_msg=""
        color="$NC"

        # 检查未提交改动
        if ! git diff --quiet || ! git diff --cached --quiet; then
            status_msg="[未提交改动]"
            color="$RED"
        else
            git fetch >/dev/null 2>&1
            LOCAL=$(git rev-parse HEAD 2>/dev/null)
            REMOTE=$(git rev-parse @{u} 2>/dev/null)

            if [ -n "$REMOTE" ] && [ "$LOCAL" != "$REMOTE" ]; then
                BASE=$(git merge-base HEAD @{u} 2>/dev/null)
                if [ "$LOCAL" = "$BASE" ]; then
                    status_msg="[远端领先，需要拉取]"
                    color="$BLUE"
                elif [ "$REMOTE" = "$BASE" ]; then
                    status_msg="[本地领先，需要推送]"
                    color="$GREEN"
                else
                    status_msg="[分叉，需要强制推送或手动处理]"
                    color="$BLUE"
                fi
            fi
        fi

        if [ -n "$status_msg" ]; then
            echo -e "${color}${status_msg} $dir${NC}"
        else
            [ "$ONLY_DIRTY" -eq 0 ] && echo "[干净] $dir"
        fi

        cd - >/dev/null
    fi
done

