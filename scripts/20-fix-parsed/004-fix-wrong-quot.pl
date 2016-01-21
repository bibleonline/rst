#!/usr/bin/perl
# description: 003-fix-i-tag.md

$/=undef;
use strict;
use FindBin qw/$Bin/;

my $dir = "$Bin/../../parsed";

my %rules = qw!
01-genesis.dat-24-7 «
01-genesis.dat-24-47 »
01-genesis.dat-32-18 »
01-genesis.dat-46-33 »
02-exodus.dat-7-9 »
05-deuteronomy.dat-25-9 »
05-deuteronomy.dat-26-10 »
06-joshua.dat-22-28 »
07-judges.dat-7-18 «
09-1samuel.dat-25-6 «
10-2samuel.dat-4-10 »
11-1kings.dat-21-6 »
17-nehemiah.dat-1-8 «
28-sirach.dat-13-29 -
34-ezekiel.dat-27-3 »
48-1maccabees.dat-10-73 »
77-hebrews.dat-12-20 »
!;

foreach my $rule (sort keys %rules) {
	my ($file, $chap, $vers) =  $rule =~ m/^(\S+\.dat)-(\d+)-(\d+)/;
	my $repl = $rules{$rule};
	my $f = join '/', $dir, $file;
	open F, $f or die "$file: $!";
	my $data = join '', <F>;
	close F;
	$repl = '' if $repl eq '-';
	my $qr = sprintf('(#%d:%d#[^#]+)\&quot;', $chap, $vers);
	if ($repl eq '»') {
		$qr = sprintf('(#%d:%d#[^#]+\\S)\\s*&quot;', $chap, $vers);
	}
	$qr = qr/$qr/;
	$data =~ s!$qr!$1$repl!;
	open F, ">$f" or die "$file: $!";
	print F $data;
	close F;
}
