#!/usr/bin/perl

use strict;
use warnings FATAL => 'all';
use autodie qw(:io);
use utf8;
use v5.10;
use English qw(-no_match_vars);
use FindBin qw/$Bin/;
use open ':std', ':encoding(UTF-8)';
local $OUTPUT_AUTOFLUSH = 1;

run();

# --- Entry point ---

sub run {
    my $data = load_rules("$Bin/../conf/03-fix-text.conf");

    for my $file ( sort keys %{$data} ) {
        process_file( $file, $data->{$file} );
    }

    return;
}

# --- Config loading ---

sub load_rules {
    my ($path) = @_;

    my $data  = {};
    my @lines = read_lines($path);
    for (@lines) {
        if (/(\S+[.]dat)#(\S+)#(.+)/) {
            $data->{$1}->{$2} = $3;
        }
    }

    return $data;
}

# --- File processing ---

sub process_file {
    my ( $file, $file_rules ) = @_;

    my @places = keys %{$file_rules};
    my $re     = sprintf '(?:%s)', join q{|}, @places;
    $re = qr/$re/;

    my @lines = read_lines("$Bin/../$file");
    my @output;
    for (@lines) {
        if (/^#($re)#/) {
            push @output, sprintf '#%s#%s', $1, $file_rules->{$1};
        }
        else {
            push @output, $_;
        }
    }

    write_file( "$Bin/../$file", join "\n", @output );

    return;
}

# --- I/O ---

sub read_lines {
    my ($path) = @_;

    open my $fh, '<', $path;
    my @lines = <$fh>;
    close $fh;

    for my $line (@lines) {
        $line =~ s/\R\z//;
    }

    return @lines;
}

sub write_file {
    my ( $path, $content ) = @_;

    open my $fh, '>', $path;
    print {$fh} $content;
    close $fh;

    return;
}
