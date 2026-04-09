#!/usr/bin/perl
# generate word list of bible

use strict;
use warnings;
use v5.10;
use utf8;
use autodie     qw(:io);
use FindBin     qw($Bin);
use File::Slurp qw(read_file);

binmode STDOUT, ':encoding(UTF-8)';

my $dir = "$Bin/../../parsed";

my $dh;
opendir $dh, $dir;
my @files = grep {/dat$/} readdir $dh;
closedir $dh;

my %list;
foreach my $file (@files) {
    my $path = join q{/}, $dir, $file;
    foreach my $line ( read_file( $path, binmode => ':encoding(UTF-8)' ) ) {
        chomp $line;
        if ( $line =~ /^#[^#]+#(.*\S)/ ) {
            my $text = $1;
            $text =~ s/[^а-яА-ЯёЁ]/ /g;
            foreach my $word ( grep {length} split / +/, $text ) {
                $list{$word}++;
            }
        }
    }
}

foreach my $word ( reverse sort { $list{$a} <=> $list{$b} } keys %list ) {
    say "$word\t$list{$word}";
}
