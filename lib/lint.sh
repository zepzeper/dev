#!/usr/bin/env bash
# `dev-env lint`. Sourced by dev-env.

# Every tracked file with a shell shebang. Selecting by shebang rather than by
# extension matters here: the scripts have no .sh suffix, while
# .local/scripts/misc/resources/ holds plain data files that shellcheck exits
# non-zero on if handed to it.
shell_files() {
    local f
    while IFS= read -r f; do
        head -1 "$f" 2>/dev/null | grep -qE '^#!.*((ba)?sh)$|^#!.*env +(ba)?sh' &&
            printf '%s\n' "$f"
    done < <(git -C "$DEV_ENV_HOME" ls-files -z |
        tr '\0' '\n' |
        sed "s|^|$DEV_ENV_HOME/|" |
        sort)
}

do_lint() {
    need shellcheck dev

    local -a files=()
    local f
    while IFS= read -r f; do files+=("$f"); done < <(shell_files)

    ((${#files[@]})) || die "no shell scripts found"

    info "shellcheck: ${#files[@]} scripts"
    local rc=0
    shellcheck --severity="${LINT_SEVERITY:-warning}" "${files[@]}" || rc=1

    if command -v shfmt >/dev/null; then
        info "shfmt: formatting"
        # -i 4 -ci matches how these are already written.
        shfmt -d -i 4 -ci "${files[@]}" || rc=1
    else
        warn "shfmt not installed; skipping the formatting check"
    fi

    ((rc)) && die "lint failed"
    info "lint clean"
}
