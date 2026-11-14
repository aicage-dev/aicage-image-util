#!/usr/bin/env bash
set -euo pipefail

find_shebang_scripts() {
  local shells="$1"
  local first_line script
  local pattern="^#!.*[/[:space:]](${shells})([[:space:]]|$)"
  while IFS= read -r -d '' script; do
    IFS= read -r first_line <"$script" || true
    if [[ "$first_line" =~ $pattern ]]; then
      printf '%s\n' "$script"
    fi
  done < <(find . -type f -not -path './.git/*' -not -path './.venv*/*' -print0)
}

mapfile -t shellcheck_scripts < <(
  {
    find . -type f \( -name '*.sh' -o -name '*.bash' \) -not -path './.venv*/*'
    find_shebang_scripts 'sh|bash|dash|ksh|zsh'
  } | sort -u
)
mapfile -t bats_scripts < <(find . -type f -name '*.bats' -not -path './.venv*/*' | sort)
mapfile -t bash_scripts < <(
  {
    find . -type f \( -name '*.sh' -o -name '*.bash' \) -not -path './.venv*/*'
    find_shebang_scripts 'sh|bash'
  } | sort -u
)

echo "Validate YAML"
yamllint --config-file .github/linters/.yamllint .

echo "Validate Markdown"
pymarkdown \
  --config .github/linters/.pymarkdown.json scan \
  --recurse \
  --exclude '**/.venv*/**' \
  .

if [[ ${#bash_scripts[@]} -gt 0 ]]; then
  echo "Validate shell scripts with bash -n"
  for script in "${bash_scripts[@]}"; do
    bash -n "${script}"
  done
fi

if [[ ${#shellcheck_scripts[@]} -gt 0 ]]; then
  echo "Run shellcheck"
  shellcheck -x "${shellcheck_scripts[@]}"
fi

if [[ ${#bats_scripts[@]} -gt 0 ]]; then
  echo "Run shellcheck on Bats tests"
  shellcheck -x -e SC2154,SC2218 "${bats_scripts[@]}"
fi
