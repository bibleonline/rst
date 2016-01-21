#!/usr/bin/perl

use strict;
use Encode;
use FindBin qw/$Bin/;
my $c;
my $dir = "$Bin/../parsed";

opendir D, $dir or die "$dir $!";
my @files = grep {/dat$/} readdir D;
closedir D;

foreach my $file (@files) {
	my ($l, $r, $vers) = (0,0, '');

	my $chap = '';
	my $f = join "/", $dir, $file;
	open F, $f or die "$file: $!";
	while ( <F>) {
		my $st = $_;
		Encode::_utf8_on($_);

		while (m/([«»]|#(\d+:\d+)#)/gc) {
			my $val = $1;
			Encode::_utf8_off($val);
			if ($val =~ /\d/) {
				$vers = $val;
				my ($ch) = $vers =~ /(\d+)/;
				if ($ch ne $chap) { 
						print "Start new chap [$file: $ch], but not equal: $l <=> $r\n" if $l != $r;
						$chap = $ch; $l = $r = 0 ; }
			} else {

				if ($val eq '«') { $l++ } else { $r++ }
				if ($l != $r && $l < $r ) {
					printf "Wrong %s since %s [%d:%d]\n", $file, $vers, $l, $r;
					if ($r > $l) { print "Rights more than left\n"; $r = $l;} else {
						printf "Left more than right on %d\n", $l-$r; $r=$l;
					}
				} 
			}
		}
	}
	print "Book $file ended, but not equal: $l <=> $r\n" if $l != $r;
	close F;
}
