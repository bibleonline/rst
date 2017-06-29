#!/bin/bash
perl -p -i -e 's/\&ndash;/\&mdash;/g;s/-/‐/g;' ../../parsed/*dat
