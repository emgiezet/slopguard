#!/usr/bin/env bash
# lib/diff.sh — changed-lines filter (§2 Z2).
#
# Z2:  Findings of category maintainability and performance are filtered to
#      lines that appear in `git diff -U0`.  Untracked files are judged whole.
#      Security findings in a changed file but outside changed lines are
#      reported once per session as pre-existing (info) and do not block.

# diff_is_untracked <file> [<root>]
# Exit 0 if the file is not tracked by git (untracked / newly added-not-yet-committed).
# Exit 1 if the file is already tracked.
diff_is_untracked() {
    local file="$1"
    local root="${2:-.}"
    local status
    # git status --short: '?? path' for untracked, 'A  path' for staged-new.
    status="$(cd "$root" 2>/dev/null && git status --short -- "$file" 2>/dev/null | head -1)" || return 1
    case "$status" in
        '?? '* | 'A  '* | 'A '*) return 0 ;;
        *) return 1 ;;
    esac
}

# diff_changed_ranges <file> [<root>]
# Print space-separated "START,END" pairs of line ranges added or modified in
# the working tree relative to HEAD (git diff -U0).
# Each hunk "@@ -old +new[,len] @@" contributes one START,END pair:
#   start = new (1-based), end = new + len - 1.  Deletion hunks (len 0) skip.
# Prints nothing if the file has no changes.
diff_changed_ranges() {
    local file="$1"
    local root="${2:-.}"
    (cd "$root" 2>/dev/null && git diff -U0 HEAD -- "$file" 2>/dev/null) \
    | awk '
        /^@@/ {
            # Locate the "+new[,len]" token — always after the first "+" in @@.
            s = $0
            if (match(s, /\+[0-9]+(,[0-9]+)?/)) {
                range = substr(s, RSTART + 1, RLENGTH - 1)   # skip leading "+"
                n = split(range, parts, ",")
                start = parts[1] + 0
                len   = (n > 1) ? parts[2] + 0 : 1
                if (len == 0) next                             # pure deletion
                printf "%d,%d ", start, start + len - 1
            }
        }'
}

# diff_line_in_ranges <line_number> <ranges_string>
# Exit 0 if <line_number> falls within any "START,END" pair in <ranges_string>.
# <ranges_string> is a space-separated list produced by diff_changed_ranges.
diff_line_in_ranges() {
    local line="$1" ranges="$2"
    local pair start end
    for pair in $ranges; do
        start="${pair%%,*}"
        end="${pair##*,}"
        if [ "$line" -ge "$start" ] && [ "$line" -le "$end" ]; then
            return 0
        fi
    done
    return 1
}
