#!/usr/bin/env bash
#
# Run stylish-haskell on a file, using the stylish-haskell.yaml file that is
# closest to the file in the directory hierarchy.

file="$1"

directory="$(dirname "$file")"

while [[ "$directory" != "/" && "$directory" != "." ]]; do
  config_file="$directory/.stylish-haskell.yaml"
  if [[ -f "$config_file" ]]; then
    stylish_haskell_config_file="$config_file"
    break
  fi
  directory="$(dirname "$directory")"
done

if [[ -f "$stylish_haskell_config_file" ]]; then
  stylish-haskell -c "$stylish_haskell_config_file" -i "${file}"
else
  stylish-haskell -i "${file}"
fi
