#!/usr/bin/perl

use strict;
use warnings FATAL => 'all';
use v5.10;

use FindBin qw!$Bin!;
use JSON;
use Data::Dumper;

open F, 'syn.json' or die $!;
my $data = decode_json(join '', <F>);
close F;

my $parsed = "$Bin/../parsed/";

open D, ">$parsed/description.conf" or die "description.conf: $!";
my $id = 0;
foreach my $book (@{ $data->{books}}  ) {
	(my $fn = $book->{passage}) =~ s! !-!g;
	$fn = sprintf('%s/../source/%s.html', $Bin, $fn);
#	next if $fn !~ /Est|Jude/;
	open F, $fn or die "$fn: $!";
	my $text = join '', <F>; 
	close F;
	my ($eng, $rus, $chap, $vers) = ('', '', 0, 0);
	my @list;
	my %chaps;
	while ($text =~ m!<([a-z]+)([^>]*)>(.*?)</\1>!gcsm) {
		my ($tag, $args, $subtext) = ($1, $2, $3);
		# In This text always start tag is <p...>
		if ($tag ne 'p') {
			die "wrong open tag `$tag' in $fn";
		}
		unless ($eng) { # 1st p. with title  in en
			($eng) = $subtext =~ m!<span[^>]*>(.+)</span>!;
		} elsif (!$rus) {
			$rus = $subtext;
			foreach ($rus) { # 2nd p. with title in ru
				s/^\s+//s; s/\s+$//s;
			}
		} else { # bible text
			foreach ($subtext) {
				s!^\s!!gsm;
				s!\s$!!gsm;
				s!<span style="font-weight:bold;"><sup>(\d+) </sup></span>!<split><verse>$1</verse>!g;
				s!<span style="font-style:italic;">(.+?)</span>!<i>$1</i>!g;
				s!<span style="font-weight:bold; color:rgb\(128, 0, 0\); font-size:18pt;">(\d+) </span>!<chap>$1</chap>!g;
			}
			my @sp = split '<split>', $subtext;
			my @tmp;
			foreach (@sp) {
				s!^\s!!gsm;s!\s$!!gsm;
				if (m!<chap>(\d+)</chap>!) {
					$chap = $1;
					$vers = 0;
					s!<chap>\d+</chap>!!;
				}
				if (m!^<verse>(\d+)</verse>!) {
					$vers = $1;
					s!^<verse>(\d+)</verse>!!;
				}
				$chaps{$chap} = $vers;
				push @tmp, sprintf "#%d:%d#%s", $chap, $vers,  $_  if $_;
			}
			push @list, [@tmp];
		}
	}
# store description
	my $outfile = sprintf("%02d-%s.dat", ++$id, lc $eng);
	$outfile =~ s/\s//g;
	my $additional='';
	$additional .= "Prolouge\tYes\n" if exists $chaps{0};
	printf D '<book-%s>
id		%s
File		%s
Eng		%s
Rus		%s
Chapters	%s
%s</book-%d>
', $id, $outfile, $id, $eng, $rus, scalar @{ $book->{chapters} },$additional,$id;
	open P, ">$parsed/$outfile";
	print P join "\n#p#\n", map { join "\n", @$_ } @list;
	close P;
}
close D;

1;
