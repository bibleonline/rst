#!/bin/bash
DIR="$(dirname "$0")/../../parsed78"
perl -p -i -e 's/# /#/' "$DIR"/*dat
