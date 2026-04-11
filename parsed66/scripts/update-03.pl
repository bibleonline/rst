#!/usr/bin/perl

use strict;
use warnings FATAL => 'all';
use autodie qw(:io);
use utf8;
use v5.10;
use English qw(-no_match_vars);
use FindBin qw/$Bin/;
use open ':std', ':encoding(UTF-8)';
use YAML::PP;
local $OUTPUT_AUTOFLUSH = 1;

run();

# --- Entry point ---

sub run {
    my $data = load_rules("$Bin/../conf/03-fix-text.yaml");

    validate_rule_files($data);

    for my $file ( sort keys %{$data} ) {
        process_file( $file, $data->{$file} );
    }

    return;
}

sub validate_rule_files {
    my ($data) = @_;

    my @missing;
    for my $file ( sort keys %{$data} ) {
        my $path = "$Bin/../$file";
        if ( !-f $path ) {
            push @missing, $file;
        }
    }

    if (@missing) {
        die "Unknown files in rules:\n"
            . join( "\n", map {"  $_"} @missing ) . "\n";
    }

    return;
}

# --- Config loading ---

sub load_rules {
    my ($path) = @_;

    my $yp   = YAML::PP->new;
    my $raw  = $yp->load_file($path);
    my $data = {};

    for my $file ( keys %{$raw} ) {
        for my $entry ( @{ $raw->{$file} } ) {
            $data->{$file}->{ $entry->{place} } = $entry->{text};
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
