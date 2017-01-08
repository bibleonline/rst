#!/bin/bash
patch  < ../scripts/20-fix-parsed/001-fix-jude.patch
perl ../scripts/20-fix-parsed/002-fix-first-word.pl
perl ../scripts/20-fix-parsed/003-fix-i-tag.pl
perl ../scripts/20-fix-parsed/004-fix-wrong-quot.pl
patch  < ../scripts/20-fix-parsed/005-fix-text-for-quot.patch
patch  < ../scripts/20-fix-parsed/006-wrong-chars.patch
patch  < ../scripts/20-fix-parsed/007-short-vers.patch
# 008-pipe.sh
perl -p -i -e 's/\s+\|+\s+/ /g;s/\s+\|+/ /g;s/\|+\s+/ /g' *dat
# /008
patch  < ../scripts/20-fix-parsed/009-wrong-text-ps73-2.patch
patch  < ../scripts/20-fix-parsed/010-wrong-space.patch
patch  < ../scripts/20-fix-parsed/011-wrong-text-ge-jacob.patch
patch  < ../scripts/20-fix-parsed/011.2-wrong-text-ge-jacob.patch
patch  < ../scripts/20-fix-parsed/012-wrong-punctuation.patch
