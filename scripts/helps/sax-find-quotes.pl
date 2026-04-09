#!/usr/bin/perl
# Check matching of paired characters (quotes, brackets) in parsed Bible files

use strict;
use warnings;
use v5.10;
use utf8;
use autodie qw(:io);
use English qw(-no_match_vars);
use Readonly;
use FindBin     qw($Bin);
use File::Slurp qw(read_file);

binmode STDOUT, ':encoding(UTF-8)';

Readonly my $MAX_MODE => 3;

my $modes = {
    1         => { o => q{«}, c => q{»}, qr => qr/[«»]/ },
    2         => { o => q{(}, c => q{)}, qr => qr/[()]/ },
    $MAX_MODE => { o => q{[}, c => q{]}, qr => qr/[[\]]/ },
};

my $mode = $ARGV[0] || 1;
if ( $mode !~ /^[1-$MAX_MODE]$/ ) {
    say 'run as:';
    say "perl $PROGRAM_NAME [1-$MAX_MODE]";
    exit;
}

my $opener = $modes->{$mode}->{o};
my $closer = $modes->{$mode}->{c};
my $qr     = $modes->{$mode}->{qr};

my $dir = "$Bin/../../parsed";

my $dh;
opendir $dh, $dir;
my @files = grep {/dat$/} readdir $dh;
closedir $dh;

foreach my $file (@files) {
    my $state = { cnt_open => 0, cnt_close => 0, vers => q{}, chap => q{} };
    my $path  = join q{/}, $dir, $file;

    foreach my $line ( read_file( $path, binmode => ':encoding(UTF-8)' ) ) {
        while ( $line =~ /($qr|[#](\d+:\d+)[#])/gc ) {
            _process_match( $1, $file, $state );
        }
    }
    if ( $state->{cnt_open} != $state->{cnt_close} ) {
        print "Book $file ended, but not equal: $state->{cnt_open} <=> $state->{cnt_close}\n";
    }
}

sub _process_match {
    my ( $val, $file, $state ) = @_;

    if ( $val =~ /\d/ ) {
        $state->{vers} = $val;
        my ($ch) = $state->{vers} =~ /(\d+)/;
        if ( $ch eq $state->{chap} ) {
            return;
        }
        if ( $state->{cnt_open} != $state->{cnt_close} ) {
            print "WARN Start new chap [$file: $ch], but not equal: $state->{cnt_open} <=> $state->{cnt_close}\n";
        }
        $state->{chap} = $ch;
        return;
    }

    if   ( $val eq $opener ) { $state->{cnt_open}++ }
    else                     { $state->{cnt_close}++ }

    if ( $state->{cnt_open} < $state->{cnt_close} ) {
        printf "Wrong %s since %s [%d:%d]\n", $file, $state->{vers}, $state->{cnt_open}, $state->{cnt_close};
        print "Rights more than left\n";
        $state->{cnt_close} = $state->{cnt_open};
    }
    return;
}
