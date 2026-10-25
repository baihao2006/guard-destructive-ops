#!/usr/bin/env bash
# 破坏性操作前的只读路径校验器，不执行删除或移动。
# --workspace 仅设置校验边界；相对目标路径按当前工作目录解析。
# 返回成功只表示路径检查通过，不保证目标存在或操作已获授权。
set -euo pipefail

die() { printf 'REFUSE: %s\n' "$*" >&2; exit 1; }
warn() { printf 'WARN: %s\n' "$*" >&2; }

usage() {
    cat <<'EOF'
Usage: check_target.sh [--workspace DIR] [--allow-outside] -- TARGET...

Read-only validation for delete/move targets.

Default: TARGET must be inside the workspace.
--allow-outside: allow an explicitly user-named target outside the workspace.
                 Drive roots, home, system directories, workspace ancestors,
                 .git, and credential directories are still refused.

Exit 0 = allowed (warnings require self-audit); exit 1 = refused.
EOF
}

workspace=""
allow_outside=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --workspace)
            [ "$#" -ge 2 ] || die "--workspace requires a value"
            workspace="$2"
            shift 2
            ;;
        --allow-outside)
            allow_outside=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            break
            ;;
        -*)
            die "unknown option: $1"
            ;;
        *)
            break
            ;;
    esac
done

[ "$#" -gt 0 ] || die "no target provided"
[ -n "$workspace" ] || workspace="$PWD"
command -v realpath >/dev/null 2>&1 || die "realpath not found; use Git Bash"
[ -d "$workspace" ] || die "workspace is not a directory: $workspace"
workspace="$(realpath -e -- "$workspace" 2>/dev/null)" || die "cannot resolve workspace: $workspace"
ws_lc="${workspace,,}"

printf 'WORKSPACE: %s\n' "$workspace"

for raw in "$@"; do
    [ -n "$raw" ] || die "empty target"

    case "$raw" in
        "~"|"~/"*)
            die "home-relative target is not allowed: $raw"
            ;;
        [A-Za-z]:*)
            die "drive-letter path is not allowed; use a Git Bash path such as /d/CODE/...: $raw"
            ;;
        *\\*)
            die "backslash path is not allowed; use a Git Bash path such as /d/CODE/...: $raw"
            ;;
        //*)
            die "UNC/share path is not allowed: $raw"
            ;;
    esac

    if [ "$raw" = "/" ] ||
        [[ "$raw" =~ ^/[A-Za-z]/?$ ]] ||
        [[ "$raw" =~ ^[A-Za-z]:[\\/]?$ ]]; then
        die "refusing filesystem root: $raw"
    fi

    case "/$raw/" in
        *"/../"*|*"/./"*)
            die "target must not contain '.' or '..' segments: $raw"
            ;;
    esac
    case "$raw" in
        */)
            die "target must not end with a slash: $raw"
            ;;
        *'*'*|*'?'*|*'['*|*']'*)
            die "wildcard target is not allowed: $raw"
            ;;
        *$'\n'*)
            die "newline in target is not allowed"
            ;;
    esac

    canon="$(realpath -m -- "$raw" 2>/dev/null)" || die "cannot resolve target: $raw"
    [ -n "$canon" ] || die "cannot resolve target: $raw"
    canon_lc="${canon,,}"

    if [ "$canon" = "/" ] ||
        [[ "$canon" =~ ^/[A-Za-z]/?$ ]] ||
        [[ "$canon" =~ ^[A-Za-z]:[\\/]?$ ]] ||
        [[ "$canon" =~ ^//[^/]+/[^/]+/?$ ]]; then
        die "refusing filesystem root or share root: $canon"
    fi

    home="${HOME:-}"
    if [ -n "$home" ]; then
        home_canon="$(realpath -m -- "$home" 2>/dev/null || true)"
        if [ -n "$home_canon" ]; then
            home_lc="${home_canon,,}"
            [ "$canon_lc" != "$home_lc" ] || die "refusing user home directory: $canon"
            for name in Desktop Documents Downloads Pictures Music Videos OneDrive AppData .ssh .gnupg .aws .azure .kube .config .docker; do
                protected="${home_lc}/${name,,}"
                if [ "$canon_lc" = "$protected" ] || [[ "$canon_lc" == "$protected/"* ]]; then
                    die "refusing protected user directory: $canon"
                fi
            done
        fi
    fi

    if [[ "$canon_lc" =~ ^/[a-z]/(windows|programdata|users|system\ volume\ information|\$recycle\.bin)(/|$) ]]; then
        die "refusing Windows system/user directory: $canon"
    fi
    if [[ "$canon_lc" =~ ^/[a-z]/program\ files( \(x86\))?(/|$) ]]; then
        die "refusing Program Files: $canon"
    fi

    case "/$canon_lc/" in
        */.git/*)
            die "refusing .git path: $canon"
            ;;
        */.qoder/*)
            die "refusing .qoder path: $canon"
            ;;
        */.ssh/*|*/.gnupg/*|*/.aws/*|*/.azure/*|*/.kube/*|*/.docker/*)
            die "refusing credential/config directory: $canon"
            ;;
    esac

    if [ "$canon_lc" = "$ws_lc" ]; then
        die "refusing the workspace root itself: $canon"
    fi
    if [[ "$ws_lc" == "$canon_lc/"* ]]; then
        die "refusing a workspace ancestor: $canon"
    fi

    if [[ "$canon_lc" == "$ws_lc/"* ]]; then
        rel_lc="${canon_lc#"$ws_lc"/}"

        if [[ "$rel_lc" != */* ]]; then
            warn "top-level workspace item; verify it is the intended project directory and not user data: $canon"
        fi
        if [ -d "$canon" ]; then
            warn "directory target; enumerate contents; recursive deletion is allowed only inside the workspace and only for the exact generated directory: $canon"
        fi
        printf 'SCOPE: workspace\n'
    else
        if [ "$allow_outside" -ne 1 ]; then
            die "target is outside the workspace; pass --allow-outside only when the user explicitly named this path: $canon"
        fi

        warn "outside workspace; verify the user explicitly named this path; no recursive deletion; back up user data or confirm it is regenerable: $canon"
        if [ -d "$canon" ]; then
            warn "outside directory; recursive deletion is forbidden; only an empty directory or explicit files may be removed: $canon"
        fi
        printf 'SCOPE: outside\n'
    fi

    if [ -L "$raw" ] && [ ! -L "$canon" ]; then
        warn "target is a symlink; only the link itself may be removed, never its destination: $canon"
    fi

    base="$(basename -- "$canon")"
    case "$base" in
        .env|.env.*|*.pem|*.key|*.p12|*.pfx|id_rsa|id_ed25519|credentials|credentials.json|.npmrc|.pypirc|.netrc)
            warn "sensitive file; verify it is not needed, back it up, and never print its contents: $canon"
            ;;
    esac

    if [ -e "$canon" ]; then
        ls -ld -- "$canon" >&2 || true
    else
        warn "target does not exist (path-only validation): $canon"
    fi

    printf 'TARGET: %s\n' "$canon"
    if [[ "$canon_lc" == "$ws_lc/"* ]]; then
        printf 'OK: %s\n' "$canon"
    else
        printf 'OK-OUTSIDE: %s\n' "$canon"
    fi
done
