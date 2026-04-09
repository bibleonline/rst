#!/bin/bash
DIR="$(dirname "$0")/../../parsed"
perl -p -i -e 's/# /#/' "$DIR"/*dat
