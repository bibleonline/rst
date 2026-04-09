#!/usr/bin/perl
# description: 002-uppercase-first-word.md

use strict;
use warnings;
use v5.10;
use autodie     qw(:io);
use English     qw(-no_match_vars);
use FindBin     qw($Bin);
use File::Slurp qw(read_file write_file);

my $dir  = "$Bin/../../parsed";
my $file = "$Bin/../../issues/002-uppercase-first-word.md";

my %replace;
foreach my $line ( read_file( $file, binmode => ':encoding(UTF-8)' ) ) {
    if ( $line =~ /(\d+\S+)[.](dat|new)[:](.*)/ ) {
        $replace{$1}->{$2} = $3;
    }
}

foreach my $pfx ( sort keys %replace ) {
    my $path = "$dir/$pfx.dat";
    my @data;
    my $fxd = 0;
    foreach my $line ( read_file( $path, binmode => ':encoding(UTF-8)' ) ) {
        chomp $line;
        if ( $line eq $replace{$pfx}->{dat} ) {
            $fxd++;
            push @data, $replace{$pfx}->{new};
        }
        else {
            push @data, $line;
        }
    }
    write_file( $path, { binmode => ':encoding(UTF-8)' }, join( "\n", @data ) . "\n" );
    printf "%s [%s]\n", $pfx, $fxd ? 'OK' : 'SKIP';
}
