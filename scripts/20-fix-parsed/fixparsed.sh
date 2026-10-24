#!/bin/bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
    printf 'Использование: %s issues/043-divine-pronouns.md\n' "$0" >&2
    exit 1
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(git -C "$script_dir" rev-parse --show-toplevel)"
issue_file="${1##*/}"
issue_file="${issue_file%.md}"

if [[ -z "$issue_file" || "$issue_file" == . || "$issue_file" == .. ]]; then
    printf 'Укажите имя issue или путь к нему.\n' >&2
    exit 1
fi

patch_text="$(git -C "$repo_root" diff -- 'parsed78/*.dat')"
if [[ -z "$patch_text" ]]; then
    printf 'В parsed78/*.dat нет изменений вне индекса Git.\n'
    exit 0
fi

patch_file="$repo_root/scripts/20-fix-parsed/${issue_file}.patch"
printf '%s\n' "$patch_text" >"$patch_file"

patch_command="patch  < ../scripts/20-fix-parsed/${issue_file}.patch"
if ! grep -Fqx -- "$patch_command" "$repo_root/parsed78/patch.sh"; then
    printf '%s\n' "$patch_command" >>"$repo_root/parsed78/patch.sh"
fi

printf 'Создан патч: %s\n' "$patch_file"
