#!/usr/bin/env bash
# Switches all submodules to the branch configured in .gitmodules.
# The script should be called without arguments.

self_script=$(readlink -f "$0")

if [ "$#" -eq 0 ]; then
  toplevel="$(git rev-parse --show-toplevel)"

  # This script calls itself for each submodule with two arguments,
  # the submodule name and toplevel directory.  The invocation of the
  # script for each submodule will perform the switch for that submodule.
  #
  # The toplevel directory is needed because the script is called from
  # the submodule directory, but the .gitmodules file is in the toplevel.
  git submodule foreach -q --recursive "\"$self_script\" \$name $toplevel"
else
  name="$1"
  toplevel="$2"

  branch="$(git config -f "$toplevel/.gitmodules" submodule.$name.branch)"

  if [ "$branch" = "" ]; then
    echo -e "\e[33mWARNING: No branch is configured for submodule $name\e[0m"
  else
    echo -e "\e[32mSwitching submodule $name to use branch $branch\e[0m"
    git switch -q $branch
  fi
fi
