#!/usr/bin/env bash

: '
My shared .bash aliases
This file should be sourced by .bashrc
'


#export DISPLAY
#export BROWSER

# Get this current file's directory so we can source files from each of the folders
_THIS_DIR="$(dirname "${0:a}")"

# Source ica functions
# shellcheck source=ica/*.sh
for s_file in "${_THIS_DIR}"/ica/*.sh; do
  source "${s_file}"
done

# Source aws functions
# shellcheck source=aws/*.sh
for s_file in "${_THIS_DIR}"/aws/*.sh; do
  source "${s_file}"
done

# Source path shortcuts
# shellcheck source=path_shortcuts/*.sh
for s_file in "${_THIS_DIR}"/path_shortcuts/*.sh; do
  source "${s_file}"
done

# Source path autocompletions
# shellcheck source=path_shortcuts/auto_completions/*.sh
#for s_file in "${_THIS_DIR}"/path_shortcuts/auto_completions/*."$(basename "${SHELL}")"; do
#  source "${s_file}"
#done

# Set file paths
# Set here as this is very much wsl2 specific
export GITHUB_PATH="/c/Users/awluc/OneDrive/GitHub/"

unset _THIS_DIR
