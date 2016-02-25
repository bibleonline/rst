#!/bin/bash
patch  < ../scripts/20-fix-parsed/001-fix-jude.patch
perl ../scripts/20-fix-parsed/002-fix-first-word.pl
perl ../scripts/20-fix-parsed/003-fix-i-tag.pl
perl ../scripts/20-fix-parsed/004-fix-wrong-quot.pl
patch  < ../scripts/20-fix-parsed/005-fix-text-for-quot.patch

