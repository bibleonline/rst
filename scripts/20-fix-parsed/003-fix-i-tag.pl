#!/usr/bin/perl
# description: 003-fix-i-tag.md

$/=undef;
use strict;
use FindBin qw/$Bin/;

my $dir = "$Bin/../../parsed";

opendir D, $dir;
my @files = sort grep {/dat/} readdir D;
closedir D;

foreach my $file (@files) {
	my $f = join '/', $dir, $file;
	open F, $f or die "$file: $!";
	my $data = join '', <F>;
	my $orig = $data;
	close F;


	# fix 1. remove </i> <i>	
	$data =~ s!</i>(\s*)<i>!$1!g;
	# fix 2.1. fix first word.
	$data =~ s!(#<i>)\s+!$1!g;
	$data =~ s!(\S+)(<i>)(\s+)(\S+)!$1$3$2$4!g;
	
	if ($orig ne $data) {
		open F, ">$f" or die "$file: $!";
		print F $data;
		close F;
	}
}
