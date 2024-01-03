#!/usr/bin/env bash

set -euo pipefail

repository="$1"
commit_range="$2"

required_cfg_version=2

git_root="$(git rev-parse --show-toplevel)"
cfg_file="$git_root/.cardano-dev.yaml"
root_dir="$HOME/.cache/cardano-updates"
work_dir="$root_dir/$repository"
download_file="$work_dir/download.yaml"

[[ -e "$download_file" ]] || { echo "$download_file doesn't exist. Did you forget to run download-prs.sh?"; exit 1; }

cfg_version="$(cat "$cfg_file" | yq -o json | jq -r '.version')"
notable_types_json="$(cat "$cfg_file" | yq -o json | jq -r '.changelog.options.type | to_entries | map(select(.value == "add") | .key) | @json')"

if [ "$cfg_version" -lt "$required_cfg_version" ]; then
  echo "Unsupported config version: $cfg_version. Required config version at least: $required_cfg_version" >&2
  exit 1
fi

trim() {
  local trimmed=$1
  awk '{$1=$1}1' <<< "$trimmed"
}

extract_changelog() {
  local in_changelog=false

  # Read from stdin
  while IFS= read -r line; do
    trimmed_line=$(trim "$line")

    echo ">>>> $line ]"

    if [[ $trimmed_line == "# Changelog" ]]; then
      in_changelog=true
    elif [[ $trimmed_line == "# "* ]]; then
      in_changelog=false
    fi

    if [ "$in_changelog" = true ]; then
      echo "$line"
    fi
  done
}

select_notable() {
  yq -o json \
    | jq -r "
          $notable_types_json as \$notable_types
        | if length == 0 then
            true
          elif .[0] | [.type] | flatten | any([.] | inside(\$notable_types)) then
            true
          else
            halt_error(1)
          end
      " \
    > /dev/null 2> /dev/null
}

temp_changelog_yaml="$(mktemp)"

for pr_number in $(
      git log --merges --oneline "$commit_range" \
    | sed 's|^[0-9a-z]\+ Merge pull request #\([0-9]\+\) .*$|\1|g'
    ); do
  cat "$download_file" | yq -o json | jq -r "$(
    cat <<-JQ
      .[] | select(.number == $pr_number) | .body
JQ
    )" \
      | awk '/# Changelog/ {found=1} found {print}' \
      | awk '/^```yaml/{flag=1;next}/^```/{flag=0}flag' \
      > "$temp_changelog_yaml"

  if cat "$temp_changelog_yaml" | select_notable; then
    if [ -s "$temp_changelog_yaml" ]; then
      cat "$temp_changelog_yaml" \
          | yq -o json \
          | jq -r "$(
              cat <<-JQ
                  .[]
                | ([.type] | flatten | join(", ")) as \$type_string
                | ([.compatibility] | flatten | join(", ")) as \$compatibility
                | ([\$type_string, \$compatibility] | map(select(. != null and . != "")) | join ("; ")) as \$type_comp
                | "- \(.description | gsub("^[[:space:]]+|[[:space:]]+$"; "") | gsub("\n"; "\n  "))\n  (\(\$type_comp))"
JQ
          )"
    else
      echo "- <missing changelog>"
    fi

    cat "$download_file" | yq -o json | jq -r "$(
      cat <<-JQ
        .[] | select(.number == $pr_number) | "  [PR \(.number)](\(.url))"
JQ
    )"

    echo
  fi
done
