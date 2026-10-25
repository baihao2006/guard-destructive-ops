#!/usr/bin/env bash
# 将精确目标移入 <workspace>/.qoder/trash/<UTC>/，不执行删除。
# 依赖同目录的 check_target.sh；--dry-run 不创建目录或移动文件。
# 全部目标通过校验后才开始移动；执行中失败不会自动回滚已移动的目标。
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
checker="$script_dir/check_target.sh"

die() { printf 'ABORT: %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<'EOF'
Usage: quarantine.sh [--workspace DIR] [--dry-run] -- TARGET...

Optional workspace-only tool for uncertain content. Moves exact targets into
<workspace>/.qoder/trash/<UTC timestamp>/ instead of deleting them. Direct
deletion of known generated artifacts inside the workspace is also allowed.
Every target is validated first; outside targets are refused, and if any target
is rejected nothing is moved. Use --dry-run to preview without creating the
trash directory.
EOF
}

workspace=""
dry_run=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --workspace)
            [ "$#" -ge 2 ] || die "--workspace requires a value"
            workspace="$2"
            shift 2
            ;;
        --dry-run)
            dry_run=1
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
[ -d "$workspace" ] || die "workspace is not a directory: $workspace"
workspace="$(realpath -e -- "$workspace" 2>/dev/null)" || die "cannot resolve workspace: $workspace"
[ -f "$checker" ] || die "checker not found: $checker"

qoder_dir="$workspace/.qoder"
trash_root="$qoder_dir/trash"
[ ! -L "$qoder_dir" ] || die ".qoder must not be a symlink: $qoder_dir"
[ ! -e "$qoder_dir" ] || [ -d "$qoder_dir" ] || die ".qoder is not a directory: $qoder_dir"
[ ! -L "$trash_root" ] || die ".qoder/trash must not be a symlink: $trash_root"
[ ! -e "$trash_root" ] || [ -d "$trash_root" ] || die ".qoder/trash is not a directory: $trash_root"

validated=()
for raw in "$@"; do
    [ -n "$raw" ] || die "empty target"

    if ! bash "$checker" --workspace "$workspace" -- "$raw"; then
        die "target rejected by checker: $raw"
    fi

    # Resolve the parent, not the final component, so a symlink itself is moved.
    parent="$(realpath -e -- "$(dirname -- "$raw")" 2>/dev/null)" || die "target parent does not exist: $raw"
    abs="$parent/$(basename -- "$raw")"
    [ -e "$abs" ] || [ -L "$abs" ] || die "target does not exist: $raw"

    for existing in "${validated[@]}"; do
        [ "${existing,,}" != "${abs,,}" ] || die "duplicate target: $abs"
    done
    validated+=("$abs")
done

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
dest="$trash_root/$stamp"
n=1
while [ -e "$dest" ] || [ -L "$dest" ]; do
    dest="$trash_root/$stamp-$n"
    n=$((n + 1))
done

declare -A planned=()
dests=()
for abs in "${validated[@]}"; do
    name="$(basename -- "$abs")"
    candidate="$dest/$name"
    n=1
    while [ -e "$candidate" ] || [ -L "$candidate" ] || [ -n "${planned[$candidate]:-}" ]; do
        candidate="$dest/$name.$n"
        n=$((n + 1))
    done
    planned["$candidate"]=1
    dests+=("$candidate")
done

if [ "$dry_run" -eq 1 ]; then
    printf 'DRY-RUN: would quarantine %d target(s) into %s\n' "${#validated[@]}" "$dest"
    for i in "${!validated[@]}"; do
        printf 'DRY-RUN: mv -- %q %q\n' "${validated[$i]}" "${dests[$i]}"
    done
    exit 0
fi

mkdir -p -- "$dest"
{
    printf '# quarantine time: %s\n' "$stamp"
    printf '# workspace: %q\n' "$workspace"
    printf '# destination <TAB> origin (restore with: mv -- <destination> <origin>)\n'
} >"$dest/manifest.txt"

for i in "${!validated[@]}"; do
    if ! mv -- "${validated[$i]}" "${dests[$i]}"; then
        die "move failed: ${validated[$i]}; previously moved targets are in $dest"
    fi
    printf '%q\t%q\n' "${dests[$i]}" "${validated[$i]}" >>"$dest/manifest.txt"
    printf 'MOVED: %s -> %s\n' "${validated[$i]}" "${dests[$i]}"
done

printf 'QUARANTINE: %s\n' "$dest"
printf 'RESTORE (paste into Git Bash):\n'
for i in "${!validated[@]}"; do
    printf 'mv -- %q %q\n' "${dests[$i]}" "${validated[$i]}"
done
