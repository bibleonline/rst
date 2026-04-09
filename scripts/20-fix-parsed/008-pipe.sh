#!/bin/bash
DIR="$(dirname "$0")/../../parsed"
perl -p -i -e 's/\s+\|+\s+/ /g;s/\s+\|+/ /g;s/\|+\s+/ /g' "$DIR"/*dat
