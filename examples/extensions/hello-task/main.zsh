#!/bin/zsh -f
set -eu
if (( $# != 1 )) || [[ -z "$1" ]]; then
    print -u2 -- 'Provide one nonempty name.'
    exit 2
fi
print -r -- "Hello, $1"
