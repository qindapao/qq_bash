#!/usr/bin/env bash

# color definition
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

print_help() {
    echo "Usage: $0 [options] <directory1> [directory2 ...]"
    echo
    echo "options:"
    echo "  -h, --help        display help information"
    echo "  -o, --only-dirty  only displays problematic repositories, not clean repositories"
    echo
    echo "Example:"
    echo "  $0 ~/projects"
    echo "  $0 --only-dirty /d/code ~/work"
    echo "  $0 -o . ~/repos"
    echo "  $0 -o ~/repos ."
}

# Parameter analysis
ONLY_DIRTY=0
ROOT_DIRS=()

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
            ROOT_DIRS+=("$arg")
            ;;
    esac
done

# If no directory is passed, print help and exit
if [ ${#ROOT_DIRS[@]} -eq 0 ]; then
    print_help
    exit 1
fi

for ROOT_DIR in "${ROOT_DIRS[@]}"; do
    for dir in "$ROOT_DIR"/*; do
        if [ -d "$dir/.git" ]; then
            cd "$dir" || continue

            git fetch >/dev/null 2>&1

            repo_dirty=0

            # Check for untracked files
            if [ -n "$(git ls-files --others --exclude-standard)" ]; then
                echo -e "${RED}$dir [Untracked files present]${NC}"
                repo_dirty=1
            fi

            # Check for unstaged changes
            if ! git diff --quiet; then
                echo -e "${RED}$dir [Unstaged changes]${NC}"
                repo_dirty=1
            fi

            # Check for changes that have been staged but not committed
            if ! git diff --cached --quiet; then
                echo -e "${RED}$dir [Staged but uncommitted changes]${NC}"
                repo_dirty=1
            fi

            # Check the remote synchronization status of each branch again
            for branch in $(git for-each-ref --format='%(refname:short)' refs/heads/); do
                status_msg=""
                color="$NC"

                LOCAL=$(git rev-parse "$branch" 2>/dev/null)
                REMOTE=$(git rev-parse "$branch@{u}" 2>/dev/null)

                if [ -z "$REMOTE" ]; then
                    status_msg="[No upstream tracking branch]"
                    color="$RED"
                elif [ "$LOCAL" != "$REMOTE" ]; then
                    BASE=$(git merge-base "$branch" "$branch@{u}" 2>/dev/null)
                    if [ "$LOCAL" = "$BASE" ]; then
                        status_msg="[Remote ahead, needs pull]"
                        color="$BLUE"
                    elif [ "$REMOTE" = "$BASE" ]; then
                        status_msg="[Local ahead, needs push]"
                        color="$GREEN"
                    else
                        status_msg="[Diverged, manual resolution needed]"
                        color="$BLUE"
                    fi
                fi

                if [ -n "$status_msg" ]; then
                    repo_dirty=1
                    echo -e "${color}$dir ${status_msg} ($branch)${NC}"
                else
                    [ "$ONLY_DIRTY" -eq 0 ] && echo "[clean] $dir ($branch)"
                fi
            done

            # If all branches in the warehouse are clean and only dirty is displayed, 
            # there will be no output.
            if [ $repo_dirty -eq 0 ] && [ "$ONLY_DIRTY" -eq 1 ]; then
                :
            fi

            cd - >/dev/null
        fi
    done
done

