#!/usr/bin/perl

use strict;
use warnings FATAL => 'all';

our $VERSION = '1.1';

use Carp;
use FindBin qw/$Bin/;
use JSON;
use Config::General;
use Readonly;
use autodie qw/:io/;
use File::Slurp;

Readonly my $PRSD_DIR   => "$Bin/../parsed/";
Readonly my $EMPTY      => q{};
Readonly my $LAST_OT_ID => 51;
Readonly my $SPAN       => {
    bold   => quotemeta '<span style="font-weight:bold;">',
    italic => quotemeta '<span style="font-style:italic;">',
    color  => quotemeta '<span style="font-weight:bold; color:rgb(128, 0, 0); font-size:18pt;">'
};
Readonly my $RE_VERSE => qr{
        $SPAN->{bold}
            <sup>(\d+)\s</sup>
        </span>}smx;
Readonly my $RE_ITALIC => qr{
        $SPAN->{italic}
            (.+?)
        </span>}smx;
Readonly my $RE_CHAP => qr{
        $SPAN->{color}
            (\d+)\s
        </span>}smx;
my $data = decode_json( read_file "$Bin/syn.json" );

my $deut = { Config::General->new("$Bin/deuterocanonical.conf")->getall };

my $id = 0;
my @description;
foreach my $book ( @{ $data->{books} } ) {
    ( my $fn = $book->{passage} ) =~ s/ /-/g;
    $fn = sprintf '%s/../source/%s.html', $Bin, $fn;
    my $text = read_file $fn;
    my ( $eng, $rus, $chap, $vers ) = ( $EMPTY, $EMPTY, 0, 0 );
    my @list;
    my %chaps;

    while ( $text =~ m{<([a-z]+)([^>]*)>(.*?)</\1>}gcsm ) {
        my ( $tag, $args, $subtext ) = ( $1, $2, $3 );

        # In This text always start tag is <p...>
        if ( $tag ne 'p' ) {
            croak "wrong open tag `$tag' in $fn";
        }
        unless ($eng) {    # 1st p. with title  in en
            ($eng) = $subtext =~ m{<span[^>]*>(.+)</span>};
        }
        elsif ( !$rus ) {
            $rus = $subtext;
            foreach ($rus) {    # 2nd p. with title in ru
                s/^\s+//s;
                s/\s+$//s;
            }
        }
        else {                  # bible text
            foreach ($subtext) {
                s/^\s//gsm;
                s/\s$//gsm;
                s{$RE_VERSE}{<split><verse>$1</verse>}gsm;
                s{$RE_ITALIC}{<i>$1</i>}gsm;
                s{$RE_CHAP}{<chap>$1</chap>}gsm;
            }
            my @sp = split /<split>/, $subtext;
            my @tmp;
            foreach (@sp) {
                s/^\s//gsm;
                s/\s$//gsm;
                if (m{<chap>(\d+)</chap>}) {
                    $chap = $1;
                    $vers = 0;
                    s{<chap>\d+</chap>}{};
                }
                if (m{^<verse>(\d+)</verse>}) {
                    $vers = $1;
                    s{^<verse>(\d+)</verse>}{};
                }
                $chaps{$chap} = $vers;
                if ($_) {
                    push @tmp, sprintf '#%d:%d#%s', $chap, $vers, $_;
                }
            }
            push @list, [@tmp];
        }
    }

    # store description
    my $outfile = sprintf '%02d-%s.dat', ++$id, lc $eng;
    $outfile =~ s/\s//g;
    my $additional = $EMPTY;
    if ( exists $chaps{0} ) {
        $additional = sprintf "% 10s    %s\n", qw/Prolouge Yes/;
    }
    my @elems     = qw/id File Eng Rus Testament Chapters/;
    my $desc_mask = sprintf "<book-%%d>\n%s\n%%s</book-%%d>\n", join "\n", map { sprintf '% 10s    %%s', $_ } @elems;
    push @description, sprintf $desc_mask, $id, $id, $outfile, $eng, $rus,
        exists $deut->{Books}->{$id} ? 'DE' : $id > $LAST_OT_ID ? 'NT' : 'OT',
        scalar @{ $book->{chapters} } - ( exists $chaps{0} ? 1 : 0 ),
        $additional, $id;
    open my $fh, q{>}, "$PRSD_DIR/$outfile";
    printf {$fh} "%s\n", join "\n#p#\n", map { join "\n", @{$_} } @list;
    close $fh;
}
open my $desc_fh, q{>}, "$PRSD_DIR/description.conf";
print {$desc_fh} join $EMPTY, @description;
close $desc_fh;

1;
