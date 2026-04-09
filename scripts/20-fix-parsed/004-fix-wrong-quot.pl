#!/usr/bin/perl
# description: 004-wrong-quot-tag.md

use strict;
use warnings;
use v5.10;
use autodie     qw(:io);
use English     qw(-no_match_vars);
use FindBin     qw($Bin);
use File::Slurp qw(read_file write_file);

my $dir = "$Bin/../../parsed";

my %rules = (
    '01-genesis.dat-24-7'      => q{«},
    '01-genesis.dat-24-47'     => q{»},
    '01-genesis.dat-32-18'     => q{»},
    '01-genesis.dat-46-33'     => q{»},
    '02-exodus.dat-7-9'        => q{»},
    '05-deuteronomy.dat-25-9'  => q{»},
    '05-deuteronomy.dat-26-10' => q{»},
    '06-joshua.dat-22-28'      => q{»},
    '07-judges.dat-7-18'       => q{«},
    '09-1samuel.dat-25-6'      => q{«},
    '10-2samuel.dat-4-10'      => q{»},
    '11-1kings.dat-21-6'       => q{»},
    '17-nehemiah.dat-1-8'      => q{«},
    '28-sirach.dat-13-29'      => q{-},
    '34-ezekiel.dat-27-3'      => q{»},
    '48-1maccabees.dat-10-73'  => q{»},
    '77-hebrews.dat-12-20'     => q{»},
);

foreach my $rule ( sort keys %rules ) {
    my ( $file, $chap, $vers ) = $rule =~ /^(\S+[.]dat)-(\d+)-(\d+)/;
    my $repl = $rules{$rule};
    my $path = join q{/}, $dir, $file;
    my $data = read_file( $path, binmode => ':raw' );

    if ( $repl eq q{-} ) {
        $repl = q{};
    }
    my $qr = sprintf '(#%d:%d#[^#]+)&quot;', $chap, $vers;

    if ( $repl eq q{»} ) {
        $qr = sprintf '(#%d:%d#[^#]+\S)\s*&quot;', $chap, $vers;
    }
    $qr = qr/$qr/;
    $data =~ s{$qr}{$1$repl};
    write_file( $path, { binmode => ':raw' }, $data );
}
