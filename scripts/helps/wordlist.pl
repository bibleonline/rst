#!/usr/bin/perl
# generate char list of bible

use strict;
use v5.10;
use FindBin '$Bin';
use Encode;
use Data::Dumper;
my $dir = "$Bin/../../parsed";

opendir D, $dir;
my %list;
my @files = grep {/dat$/} readdir D;
closedir D;
foreach my $file (@files) {
	my $f = join "/", $dir, $file;
	open F, $f or die "$file: $!";
	while (<F>) {
		my $orig  = $_;
		Encode::_utf8_on($_);
		my $cv;
		s/[\r\n]//g;
		if (/^#([^#]+)#(.*\S)/) {
			$cv = $1;
			$_=$2;
			Encode::_utf8_off($_);
			s/[^а-яА-Я]/ /g;
			my @words = split/ /;
			$list{$_}++ for @words;
			Encode::_utf8_off($_);
		}
	}
	close F;
}

# foreach my $char (sort keys %list) {
 foreach my $char (sort { $list{$b} <=> $list{$a} } keys %list) {
	my $c = $char;
	Encode::_utf8_off($char);
	say "$char\t$list{$c}";
}