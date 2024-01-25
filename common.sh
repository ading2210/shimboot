#!/bin/bash

check_deps() {
  local needed_commands="$1"
  for command in $needed_commands; do
    if ! command -v $command &> /dev/null; then
      echo $command
    fi
  done
}

assert_deps() {
  local needed_commands="$1"
  local missing_commands=$(check_deps "$needed_commands")
  if [ "${missing_commands}" ]; then
    echo "You are missing dependencies needed for this script."
    echo "Commands needed:"
    echo "${missing_commands}"
    exit 1
  fi
}

parse_args() {
  declare -g -A args
  for argument in "$@"; do
    local key=$(echo $argument | cut -f1 -d=)
    local key_length=${#key}
    local value="${argument:$key_length+1}"
    args["$key"]="$value"
  done
}