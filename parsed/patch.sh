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
patch  < ../scripts/20-fix-parsed/013-wrong-text-numbers7-2.patch
patch  < ../scripts/20-fix-parsed/014-kathisma.patch
patch  < ../scripts/20-fix-parsed/015-wrong-sq-sirach.patch
patch  < ../scripts/20-fix-parsed/016-fix-prayerofmanasseh.patch
patch  < ../scripts/20-fix-parsed/017-psalm-wrong-1st-verse.patch
patch  < ../scripts/20-fix-parsed/018-wrong-text-prov25-5.patch
# 019-typograph.sh
perl -p -i -e 's/\&ndash;/\&mdash;/g;s/-/‐/g;' *dat
patch  < ../scripts/20-fix-parsed/020-wront-text.patch
patch  < ../scripts/20-fix-parsed/021-start-with-lowcase.patch
patch  < ../scripts/20-fix-parsed/022-wrong-text-job36-24.patch
patch  < ../scripts/20-fix-parsed/023-wrong-punctuation-1mac5-34.patch
patch  < ../scripts/20-fix-parsed/024-wrong-paragraph-james1-16.patch
patch  < ../scripts/20-fix-parsed/025-numbers.patch
patch  < ../scripts/20-fix-parsed/026-wrong-text-1pe1-12.patch
patch  < ../scripts/20-fix-parsed/027-wrong-text-luke-8-10.patch
