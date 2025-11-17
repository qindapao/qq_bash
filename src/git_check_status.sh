#!/usr/bin/env bash

# color definition
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

print_help() {
    echo "Usage: $0 [options] <directory>"
    echo
    echo "options:"
    echo "  -h, --help display help information"
    echo "  -o, --only-dirty only displays problematic repositories, not clean repositories"
    echo
    echo "Example:"
    echo "  $0 ~/projects"
    echo "  $0 --only-dirty /d/code"
    echo "  $0 -o /d/code"
    echo "  $0 -o ."
}

# Parameter analysis
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

# If no directory is passed, print help and exit
if [ -z "$ROOT_DIR" ]; then
    print_help
    exit 1
fi

for dir in "$ROOT_DIR"/*; do
    if [ -d "$dir/.git" ]; then
        cd "$dir" || continue

        status_msg=""
        color="$NC"

        # Check for uncommitted changes
        if ! git diff --quiet || ! git diff --cached --quiet; then
            status_msg="[Changes not committed]"
            color="$RED"
        else
            git fetch >/dev/null 2>&1
            LOCAL=$(git rev-parse HEAD 2>/dev/null)
            REMOTE=$(git rev-parse @{u} 2>/dev/null)

            if [ -n "$REMOTE" ] && [ "$LOCAL" != "$REMOTE" ]; then
                BASE=$(git merge-base HEAD @{u} 2>/dev/null)
                if [ "$LOCAL" = "$BASE" ]; then
                    status_msg="[Remote lead, needs to be pulled]"
                    color="$BLUE"
                elif [ "$REMOTE" = "$BASE" ]; then
                    status_msg="[Local lead, needs to be pushed]"
                    color="$GREEN"
                else
                    status_msg="[Commit history divergence, force push or manual resolution needed]"
                    color="$BLUE"
                fi
            fi
        fi

        if [ -n "$status_msg" ]; then
            echo -e "${color}${status_msg} $dir${NC}"
        else
            [ "$ONLY_DIRTY" -eq 0 ] && echo "[clean] $dir"
        fi

        cd - >/dev/null
    fi
done

