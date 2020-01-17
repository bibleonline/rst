#!/usr/bin/perl

use strict;
use warnings FATAL => 'all';
use v5.10;

use FindBin qw!$Bin!;
use JSON;
use Data::Dumper;

open F, $Bin . '/syn.json' or die $!;
my $data = decode_json( join '', <F> );
close F;

foreach my $book ( @{ $data->{books} } ) {
    ( my $fn = $book->{passage} ) =~ s! !-!g;
    $fn = sprintf( '%s/../source/%s.html', $Bin, $fn );
    open F, $fn or die "$fn: $!";
    my $source = join "", grep {/\S/} <F>;    # remove empty lines
    close F;
    open F, ">$fn";
    print F $source;
    close F;
}

1;
