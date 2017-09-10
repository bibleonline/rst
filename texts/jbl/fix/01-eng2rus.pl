#!/usr/bin/perl

use strict;
use v5.10;
use Encode;
use FindBin qw/$Bin/;

my %repl = (qw/a а o о e е x х c с/);
foreach (keys %repl) {
	Encode::_utf8_off($repl{$_});
}
opendir D, "$Bin/..";
my @files = grep { /dat/ } readdir D;
closedir D;

foreach my $f (@files) {
	my @data = ();
	my $upd = 0;
	open F, "$Bin/../$f" or die $!;
	while(<F>) {
		if ( m!(#.*#)(.+)!) {
			my ($pfx, $text) = ($1, $2);
			my $tx = $text;

			for (1..3) { for ($text) {

				s!</([ib])>(["\.\,\!\?\s]*)<\1>!$2!g;
				s!<([ib])>(["\.\,\!\?\s]*)</\1>!$2!g; # remove space
				s!(<[ib]>)(\s+)((<[ib]>))!$2$1$3!;

				s!\s*<sup.*!!;
				s!^\s!!g;
				s!\s+$!!g;
			}}

			for ($text) {
				s!(</?)i>!${1}1>!g;
				s!(</?)b>!${1}2>!g;

			}
			if ($text =~ /[a-z]/) {
				Encode::_utf8_off($_);
				$text =~ s/(.)/exists $repl{$1}? $repl{$1} : $1/eg;
				Encode::_utf8_on($_);
				say $text if $text =~ /[a-z]/;
			}
			for ($text) {
				s!(</?)1>!${1}i>!g;
				s!(</?)2>!${1}b>!g;
			}

			say "OLD: [$tx]\nNEW: [$text]\n" if $tx ne $text;

			$upd++ if $tx ne $text;
			push @data, sprintf('%s%s', $pfx, $text);
		}
	}
	close F;
	if ($upd) {
		open F, ">$Bin/../$f" or die $!;
		print F join "\n", @data;
		close F;
	}
}