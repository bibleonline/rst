#!/bin/bash
DIR="$(dirname "$0")/../../parsed78"
perl -p -i -e 's/\&ndash;/\&mdash;/g;s/-/‐/g;' "$DIR"/*dat
