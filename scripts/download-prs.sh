#!/bin/bash

set -eu

(yq --version | grep https://github.com/mikefarah/yq/ > /dev/null) || {
  echo "Please install yq from https://github.com/mikefarah/yq/" > /dev/stderr
  exit 1
}

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 repository" >&2
  echo "Example: $0 input-output-hk/cardano-node" >&2
  exit 1
fi

repository="$1"

root_dir="$HOME/.cache/cardano-updates"
out_dir="$root_dir/$repository"

mkdir -p "$out_dir"

temp_json_file="$(mktemp).json"

# Get the highest PR number to estimate total count
max_pr_number="$(gh pr list --repo "$repository" --state all --limit 1 --json number | jq '.[0].number // 1000')"

echo "Downloading up to $max_pr_number PRs"

batch_size=100
owner="${repository%%/*}"
name="${repository##*/}"

query='
query($owner: String!, $name: String!, $batch: Int!, $cursor: String) {
  repository(owner: $owner, name: $name) {
    pullRequests(first: $batch, after: $cursor, orderBy: {field: CREATED_AT, direction: DESC}) {
      pageInfo { hasNextPage endCursor }
      nodes {
        number
        title
        author { login }
        createdAt
        closedAt
        mergedAt
        baseRefName
        url
        body
        files(first: 100) { nodes { path } }
      }
    }
  }
}
'

echo "[]" > "$temp_json_file"
cursor=""
fetched=0

while true; do
  page=$((fetched / batch_size + 1))
  echo "Fetching batch $page (PRs $((fetched + 1))-$((fetched + batch_size)) of $max_pr_number)..."

  batch_file="$(mktemp).json"
  cursor_args=()
  if [ -n "$cursor" ]; then
    cursor_args=(-f cursor="$cursor")
  else
    cursor_args=(-F cursor=null)
  fi

  # Retry up to 3 times on transient failures (502s return HTML)
  success=false
  for attempt in 1 2 3; do
    if gh api graphql \
      -f query="$query" \
      -f owner="$owner" \
      -f name="$name" \
      -F batch="$batch_size" \
      "${cursor_args[@]}" \
      --jq '.data.repository.pullRequests' \
      > "$batch_file" 2>/dev/null && jq -e '.nodes' "$batch_file" > /dev/null 2>&1; then
      success=true
      break
    fi
    echo "  Attempt $attempt failed, retrying in ${attempt}s..." >&2
    sleep "$attempt"
  done

  if [ "$success" != true ]; then
    echo "Failed to fetch batch $page after 3 attempts. Check authentication and rate limits." >&2
    exit 1
  fi

  # Check if we actually got cursor back as literal string (means no cursor needed)
  has_next=$(jq -r '.pageInfo.hasNextPage' "$batch_file")
  cursor=$(jq -r '.pageInfo.endCursor' "$batch_file")

  # Transform GraphQL response to match gh pr list JSON format
  jq '[.nodes[] | {
    number,
    title,
    author: .author.login,
    createdAt,
    closedAt,
    mergedAt,
    baseRefName,
    url,
    body,
    files: [.files.nodes[].path]
  }]' "$batch_file" > "${batch_file}.transformed"

  # Merge batch into accumulated results
  jq -s '.[0] + .[1]' "$temp_json_file" "${batch_file}.transformed" > "${temp_json_file}.tmp"
  mv "${temp_json_file}.tmp" "$temp_json_file"
  rm -f "$batch_file" "${batch_file}.transformed"

  fetched=$((fetched + batch_size))

  if [ "$has_next" != "true" ] || [ "$fetched" -ge "$max_pr_number" ]; then
    break
  fi

  # Brief pause between batches to avoid rate limits
  sleep 1
done

echo "Downloaded $(jq length "$temp_json_file") PRs"

yq -P < "$temp_json_file" > "$out_dir/download.yaml"
