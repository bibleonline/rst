#!/usr/bin/perl

use strict;
use FindBin qw/$Bin/;
use Encode;

my $fn = join "/", $Bin, $ARGV[0];
die "File not found $fn" if !-f $fn || !-r $fn;
open F, "$fn" or die "$! $fn";

my $data = {};
while (<F>) {
    next if /^\s*#/;
    if (/(\S+\.dat)\s+(\S+)\s+(.+)/) {
        my ($file, $place, $text) = ($1, $2, $3);
        my $placeN = 0;
        if ($place =~ m!(.*)/(\d+)!) {
            ( $place, $placeN ) = ($1, $2);
        }
        for ($text) {
            s!\s+\#.*!!;
            s!^\s*!!;
            s!\s*$!!;
            
        }
        
        my ($from, $to) = split /\s+\=\>\s+/, $text;
        $data->{$file}->{$place} ||= [];
        my $dat = { from => $from, to => $to };
        if ($from =~ /(.+)\[(\S+)\]/) {
            $dat->{from} = $1;
            $dat->{num} = $2;
        }
        $dat->{place} = $placeN if $placeN;
        foreach (qw/from to/) {
            Encode::_utf8_on( $dat->{$_} );
        }

		push @{ $data->{$file}->{$place} }, $dat;
    }

}
close F;

foreach my $file (sort keys %$data) {
    my $out ='';
    my @map = keys %{ $data->{$file} };
    my $re = sprintf("(?:%s)", join "|", @map);
    $re = qr/$re/;
    my $f = "$Bin/../../parsed/$file";
    open F, $f or die "$! $file";
    my $lastn = 0;
	my $last = '';
	while (<F>) {
        if (/^#($re)#(.+)/) {
            my ($place, $text) = ($1, $2);
            $lastn = $last eq $place ? $lastn + 1 : 1;
            $last = $place;
            foreach my $repl (@{ $data->{$file}->{$place} }) {
                next if exists $repl->{place} && $lastn != $repl->{place};
                Encode::_utf8_on($text);
                if (exists $repl->{num} && $repl->{num} =~ /^\d+$/) {
                    my $i = 0;
					if ($repl->{num} eq '1') {
						$text =~ s/\b$repl->{from}\b(?!\&\#769;)/$repl->{to}/;
					} else {
						my @words = split / /, $text;
						my $i = 0;
						foreach (@words) {
							if (m/\b$repl->{from}\b(?!\&\#769;)/gc) {
								$i++;
							}
							if ($i == $repl->{num}) {
								s/\b$repl->{from}\b(?!\&\#769;)/$repl->{to}/;
							}

						}
						$text = join " ", @words;
					}
                } else {
                    my $i = 0;
					my $max = $repl->{num} =~ /^\*(\d+)$/ ? $1 : 1;

					while ($text =~ m/\b$repl->{from}\b(?!\&\#769;)/gc && $i<10) {
						$i++;
						$text =~ s/\b$repl->{from}\b(?!\&\#769;)/$repl->{to}/;
					}
					die "\nMUST BE ONLY $max but $i " . $repl->{from} . " for $file $place/$lastn\n$text\n\n" if $i != $max;
                }
                Encode::_utf8_off($text);
            }
            $out .= sprintf("#%s#%s\n", $place, $text);
        } else {
            $out .= $_;
        }
    }
    close F;
	open F, ">$f" or die "$! $f";
	print F $out;
	close F;
}