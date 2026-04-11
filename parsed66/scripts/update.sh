#!/bin/bash
set -e
cd "$(dirname "$0")"

echo "[1/5] Filter books and verses from parsed/ to parsed66/"
perl update-01.pl

echo "[2/5] Process square brackets (77-book to 66-book rules)"
perl update-02.pl

echo "[3/5] Apply text corrections"
perl update-03.pl

echo "[4/5] Remove footnote markers from Genesis"
perl -p -i -e 's/\s\[[0-9]+\]\s/ /' ../01-genesis.dat

echo "[5/5] Apply word replacements (accentuation, corrections)"
perl update-05.pl

echo "[done] Merge adjacent italic tags"
perl -p -i -e 's{</i> <i>}{ }g' ../05-deuteronomy.dat ../06-joshua.dat ../09-1samuel.dat
