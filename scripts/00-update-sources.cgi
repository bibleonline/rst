#!/usr/bin/perl

use strict;
use warnings FATAL => 'all';

our $VERSION = '1.1';

use FindBin qw!$Bin!;
use JSON;
use File::Slurp;
use autodie qw/:io/;
use Readonly;

Readonly my $EMPTY => q{};

my $data = decode_json( read_file $Bin . '/syn.json' );

foreach my $book ( @{ $data->{books} } ) {
    ( my $fn = $book->{passage} ) =~ s/ /-/gsm;
    $fn = sprintf '%s/../source/%s.html', $Bin, $fn;
    open my $fh, q{<}, $fn;
    my $source = join $EMPTY, grep {/\S/xsm} <$fh>;    # remove empty lines
    close $fh;
    open my $wh, q{>}, $fn;
    print {$wh} $source;
    close $wh;
}

1;
