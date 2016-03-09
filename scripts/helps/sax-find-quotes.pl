#!/usr/bin/perl

use strict;
use Encode;
use v5.10;
use FindBin qw/$Bin/;
my $c;
my $dir = "$Bin/../../parsed";


my $modes = {
	1 => { o => '«', c => '»', qr => qr/[«»]/ },
	2 => { o => '(', c => ')', qr => qr/[\(\)]/ },
	3 => { o => '[', c => ']', qr => qr/[\[\]]/ },	
};

my $mode = $ARGV[0] || 1;
if ($mode !~ /^[1-3]$/) {
	say 'run as:';
	say "perl $0 [1-3]";
	exit;
}

my $o = $modes->{$mode}->{o};
my $c = $modes->{$mode}->{c};
my $qr = $modes->{$mode}->{qr};

#say $qr;exit;
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

		while (m/($qr|#(\d+:\d+)#)/gc) {
			my $val = $1;
			Encode::_utf8_off($val);
			if ($val =~ /\d/) {
				$vers = $val;
				my ($ch) = $vers =~ /(\d+)/;
				if ($ch ne $chap) { 
						print "WARN Start new chap [$file: $ch], but not equal: $l <=> $r\n" if $l != $r;
						$chap = $ch; 
#						$l = $r = 0 ;
				 }
			} else {
				if ($val eq $o) { $l++ } else { $r++ }
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
