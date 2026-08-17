#!/bin/bash
DIR="$(dirname "$0")/../../parsed78"
perl -p -i -e 's/\s+\|+\s+/ /g;s/\s+\|+/ /g;s/\|+\s+/ /g' "$DIR"/*dat
