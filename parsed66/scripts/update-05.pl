#!/usr/bin/perl

use strict;
use warnings FATAL => 'all';
use autodie qw(:io);
use utf8;
use v5.10;
use FindBin qw/$Bin/;
use open ':std', ':encoding(UTF-8)';

run();

# --- Entry point ---

sub run {
    my $data = load_rules();

    for my $file ( sort keys %{$data} ) {
        process_file( $file, $data->{$file} );
    }

    return;
}

# --- Config loading ---

sub load_rules {
    my $data      = {};
    my @conffiles = glob "$Bin/../conf/05-*.conf";

    for my $conffile (@conffiles) {
        my @lines = read_lines($conffile);
        for (@lines) {
            next if /^\#/;
            my ( $file, $place, $text ) = /(\S+[.]dat)\s+(\S+)\s+(.+)/;
            next if !defined $file;

            my $place_n = 0;
            if ( $place =~ m{(.*)/(\d+)} ) {
                ( $place, $place_n ) = ( $1, $2 );
            }

            $text =~ s/\s+\#.*//;
            $text =~ s/\s+$//;

            my ( $from, $to ) = split /\s+=>\s+/, $text;

            my $rule = { from => $from, to => $to };
            if ( $from =~ /(.+)\[(\S+)\]/ ) {
                $rule->{from} = $1;
                $rule->{num}  = $2;
            }
            if ($place_n) {
                $rule->{place} = $place_n;
            }

            $data->{$file}->{$place} ||= [];
            push @{ $data->{$file}->{$place} }, $rule;
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
    my $last_place = q{};
    my $last_n     = 0;

    for (@lines) {
        if (/^#($re)#(.+)/) {
            my ( $place, $text ) = ( $1, $2 );
            $last_n     = $last_place eq $place ? $last_n + 1 : 1;
            $last_place = $place;

            $text = apply_rules( $file, $place, $last_n, $text, $file_rules->{$place} );
            push @output, sprintf '#%s#%s', $place, $text;
        }
        else {
            push @output, $_;
        }
    }

    write_file( "$Bin/../$file", join "\n", @output );

    return;
}

sub apply_rules {
    my ( $file, $place, $occurrence, $text, $rules ) = @_;

    for my $repl ( @{$rules} ) {
        next if exists $repl->{place} && $occurrence != $repl->{place};

        if ( exists $repl->{num} && $repl->{num} =~ /^\d+$/ ) {
            $text = replace_nth( $text, $repl );
        }
        else {
            $text = replace_all_checked( $file, $place, $occurrence, $text, $repl );
        }
    }

    return $text;
}

# --- Replacement strategies ---

# Замена N-го вхождения слова
sub replace_nth {
    my ( $text, $repl ) = @_;

    my $from = $repl->{from};
    my $to   = $repl->{to};
    my $re   = qr/\b$from\b(?!&#769;)/;

    # первое вхождение
    if ( $repl->{num} eq '1' ) {
        $text =~ s/$re/$to/;
        return $text;
    }

    # N-е вхождение: поиск по словам
    my @words = split / /, $text;
    my $count = 0;
    for (@words) {
        if (/$re/gc) {
            $count++;
        }
        if ( $count == $repl->{num} ) {
            s/$re/$to/;
        }
    }
    $text = join q{ }, @words;
    $text =~ s{\s(</)}{$1}g;

    return $text;
}

# Замена с проверкой количества
sub replace_all_checked {
    my ( $file, $place, $occurrence, $text, $repl ) = @_;

    my $from = $repl->{from};
    my $to   = $repl->{to};
    my $re   = qr/\b$from\b(?!&#769;)/;

    my $max = 1;
    if ( defined $repl->{num} && $repl->{num} =~ /^[*](\d+)$/ ) {
        $max = $1;
    }

    my $count = 0;
    while ( $text =~ /$re/gc && $count < 10 ) {    ## no critic (ProhibitMagicNumbers)
        $count++;
        $text =~ s/$re/$to/;
    }

    if ( $count != $max ) {
        die "\n[$file] MUST BE ONLY $max but $count $from for $file $place/$occurrence\n$text\n\n";
    }

    return $text;
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
