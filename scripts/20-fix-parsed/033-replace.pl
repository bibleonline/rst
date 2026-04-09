#!/usr/bin/perl
# description: 033-replace.md

use strict;
use warnings;
use v5.10;
use utf8;
use autodie     qw(:io);
use English     qw(-no_match_vars);
use FindBin     qw($Bin);
use File::Slurp qw(read_file write_file);
use Readonly;

Readonly my $MAX_ITERATIONS => 10;
Readonly my $ACCENT_RE      => q{(?![&][#]769[;])};

my $fn = join q{/}, $Bin, $ARGV[0];
if ( !-f $fn || !-r $fn ) {
    die "File not found $fn\n";
}

my $data = _parse_rules($fn);

foreach my $file ( sort keys %{$data} ) {
    _process_file( $file, $data->{$file} );
}

sub _parse_rules {
    my ($path) = @_;
    my %rules;

    foreach my $line ( read_file( $path, binmode => ':encoding(UTF-8)' ) ) {
        next if $line =~ /^\s*[#]/;
        if ( $line =~ /(\S+[.]dat)\s+(\S+)\s+(.+)/ ) {
            _add_rule( \%rules, $1, $2, $3 );
        }
    }

    return \%rules;
}

sub _add_rule {
    my ( $rules, $file, $place, $text ) = @_;

    my $place_n = 0;
    if ( $place =~ m{(.*)/(\d+)} ) {
        ( $place, $place_n ) = ( $1, $2 );
    }
    $text =~ s/\s+[#].*//;
    $text =~ s/^\s+//;
    $text =~ s/\s+$//;

    my ( $from, $to ) = split /\s+=>\s+/, $text;
    my $dat = { from => $from, to => $to };
    if ( $from =~ /(.+)\[(\S+)\]/ ) {
        $dat->{from} = $1;
        $dat->{num}  = $2;
    }
    if ($place_n) {
        $dat->{place} = $place_n;
    }
    $rules->{$file}{$place} ||= [];
    push @{ $rules->{$file}{$place} }, $dat;
    return;
}

sub _process_file {
    my ( $file, $places ) = @_;

    my @keys = keys %{$places};
    my $re   = sprintf q{(?:%s)}, join q{|}, @keys;
    $re = qr/$re/;
    my $path = "$Bin/../../parsed/$file";

    my $out      = q{};
    my $last_n   = 0;
    my $last_key = q{};

    foreach my $line ( read_file( $path, binmode => ':encoding(UTF-8)' ) ) {
        chomp $line;
        if ( $line =~ /^[#]($re)[#](.+)/ ) {
            my ( $place, $text ) = ( $1, $2 );
            $last_n   = $last_key eq $place ? $last_n + 1 : 1;
            $last_key = $place;
            my $ctx = "$file $place/$last_n";
            foreach my $repl ( @{ $places->{$place} } ) {
                if ( exists $repl->{place} && $last_n != $repl->{place} ) {
                    next;
                }
                $text = _apply_replacement( $text, $repl, $ctx );
            }
            $out .= sprintf "#%s#%s\n", $place, $text;
        }
        else {
            $out .= "$line\n";
        }
    }

    write_file( $path, { binmode => ':encoding(UTF-8)' }, $out );
    return;
}

sub _apply_replacement {
    my ( $text, $repl, $ctx ) = @_;

    my $from = $repl->{from};
    my $to   = $repl->{to};

    if ( exists $repl->{num} && $repl->{num} =~ /^\d+$/ ) {
        $text = _replace_nth( $text, $from, $to, $repl->{num} );
    }
    else {
        my $max = 1;
        if ( exists $repl->{num} && $repl->{num} =~ /^[*](\d+)$/ ) {
            $max = $1;
        }
        $text = _replace_all( $text, $from, $to, $max, $ctx );
    }

    return $text;
}

sub _replace_nth {
    my ( $text, $from, $to, $num ) = @_;

    if ( $num eq '1' ) {
        $text =~ s/\b$from\b$ACCENT_RE/$to/;
    }
    else {
        my @words = split / /, $text;
        my $i     = 0;
        foreach my $word (@words) {
            if ( $word =~ m/\b$from\b$ACCENT_RE/ ) {
                $i++;
            }
            if ( $i == $num ) {
                $word =~ s/\b$from\b$ACCENT_RE/$to/;
                last;
            }
        }
        $text = join q{ }, @words;
    }

    return $text;
}

sub _replace_all {
    my ( $text, $from, $to, $max, $ctx ) = @_;

    my $i = 0;
    while ( $text =~ s/\b$from\b$ACCENT_RE/$to/ && $i < $MAX_ITERATIONS ) {
        $i++;
    }
    if ( $i != $max ) {
        die "\nMUST BE ONLY $max but $i $from for $ctx\n$text\n\n";
    }

    return $text;
}
