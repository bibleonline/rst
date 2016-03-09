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
			my @ent = m/(\&[a-z]+;)/g;
			$list{$_}++ for @ent;
			s/(\&[a-z]+;)//g;
			my @tags  = m!(<[^>]+>)!g;
			$list{$_}++ for @tags;
			my @pipe = m!(\|+)!g;
			s/\|//g;
			$list{$_}++ for @pipe;
			s/<[^>]+>//g;
			my @chars = split //;
			$list{$_}++ for @chars;
			Encode::_utf8_off($_);
			die $orig unless /\S/;
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