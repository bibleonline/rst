#!/usr/bin/perl
# description: 003-fix-i-tag.md

use strict;
use warnings;
use v5.10;
use autodie     qw(:io);
use English     qw(-no_match_vars);
use FindBin     qw($Bin);
use File::Slurp qw(read_file write_file);

my $dir = "$Bin/../../parsed";

my $dh;
opendir $dh, $dir;
my @files = sort grep {/dat/} readdir $dh;
closedir $dh;

foreach my $file (@files) {
    my $path = join q{/}, $dir, $file;
    my $data = read_file( $path, binmode => ':raw' );
    my $orig = $data;

    # fix 1. remove </i> <i>
    $data =~ s{</i>(\s*)<i>}{$1}g;

    # fix 2.1. fix first word.
    $data =~ s{([#]<i>)\s+}{$1}g;
    $data =~ s{(\S+)(<i>)(\s+)(\S+)}{$1$3$2$4}g;

    if ( $orig ne $data ) {
        write_file( $path, { binmode => ':raw' }, $data );
    }
}
