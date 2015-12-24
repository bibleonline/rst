#!/usr/bin/perl
# description: 002-uppercase-first-word.md

use strict;
use FindBin qw/$Bin/;

my $dir = "$Bin/../../parsed";
my $file= "$Bin/../../issues/002-uppercase-first-word.md";

my %replace;
open F, $file or die "$file: $!";
while (<F>) {
	if (/(\d+\S+)\.(dat|new)\:(.*)/) {
		$replace{$1}->{$2} = $3;
	}
}
close F;

foreach my $pfx (sort keys %replace) {
	my $f = "$dir/$pfx.dat";
	my @data;
	my $fxd = 0;
	open F, $f or print STDERR "$f: $!";
	while (<F>) {
		s/[\r\n]//g;
		if ($_ eq $replace{$pfx}->{dat}) {
			$fxd++;
			push @data, $replace{$pfx}->{new};
		} else {
			push @data, $_;
		}
	}
	close F;
	open F, ">$f" or print STDERR "$f: $!";
	print F join "\n", @data;
	close F;
	printf "%s [%s]\n", $pfx, $fxd? 'OK' : 'SKIP';
}
