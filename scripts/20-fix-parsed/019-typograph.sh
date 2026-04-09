#!/bin/bash
DIR="$(dirname "$0")/../../parsed"
perl -p -i -e 's/\&ndash;/\&mdash;/g;s/-/‐/g;' "$DIR"/*dat
