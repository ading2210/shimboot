#!/bin/bash

set -e
if [ "$DEBUG" ]; then
  set -x
  export DEBUG=1
fi

ANSI_CLEAR='\033[0m'
ANSI_BOLD='\033[1m'
ANSI_RED='\033[1;31m'
ANSI_GREEN='\033[1;32m'
ANSI_BLUE='\033[1;34m'

check_deps() {
  local needed_commands="$1"
  for command in $needed_commands; do
    if ! command -v $command &> /dev/null; then
      echo " - $command"
    fi
  done
}

assert_deps() {
  local needed_commands="$1"
  local missing_commands=$(check_deps "$needed_commands")
  if [ "${missing_commands}" ]; then
    print_error "You are missing dependencies needed for this script."
    print_error "Commands needed:"
    print_error "${missing_commands}"
    exit 1
  fi
}

parse_args() {
  declare -g -A args
  for argument in "$@"; do
    if [ "$argument" = "-h" ] || [ "$argument" = "--help" ]; then
      print_help
      exit 0
    fi

    local key=$(echo $argument | cut -f1 -d=)
    local key_length=${#key}
    local value="${argument:$key_length+1}"
    args["$key"]="$value"
  done
}

assert_root() {
  if [ "$EUID" -ne 0 ]; then
    print_error "This script needs to be run as root."
    exit 1
  fi
}

assert_args() {
  if [ -z "$1" ]; then
    print_help
    exit 1
  fi
}

print_title() {
  printf ">> ${ANSI_GREEN}${1}${ANSI_CLEAR}\n"
}

print_info() {
  printf "${ANSI_BOLD}${1}${ANSI_CLEAR}\n"
}

print_error() {
  printf "${ANSI_RED}${1}${ANSI_CLEAR}\n"
}