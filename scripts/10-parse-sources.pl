#!/usr/bin/perl

use strict;
use warnings FATAL => 'all';

use Carp;
use FindBin qw($Bin);
use JSON;
use YAML::PP;
use Encode qw(encode_utf8);
use Readonly;
use autodie qw(:io);
use File::Slurp;

Readonly my $PRSD_DIR   => "$Bin/../parsed78/";
Readonly my $EMPTY      => q{};
Readonly my $LAST_OT_ID => 51;
Readonly my $SPAN => {
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
my $data = decode_json( read_file "$Bin/../source/syn.json" );

my $deut     = YAML::PP->new->load_file("$Bin/../conf/deuterocanonical.yaml");
my $codes    = YAML::PP->new->load_file("$Bin/../conf/usfm-codes.yaml")->{codes};
my $name_fix = YAML::PP->new->load_file("$Bin/../conf/book-names-fix.yaml")->{names};
$name_fix = { map { $_ => encode_utf8( $name_fix->{$_} ) } keys %{$name_fix} };

my $id = 0;
my @description;
foreach my $book ( @{ $data->{books} } ) {
    ( my $fn = $book->{passage} ) =~ s/ /-/gsm;
    $fn = sprintf '%s/../source/%s.html', $Bin, $fn;
    my $text = read_file $fn;
    my ( $eng, $rus, $chap, $vers ) = ( $EMPTY, $EMPTY, 0, 0 );
    my @list;
    my %chaps;

    while (
        $text =~ m{
            <([[:lower:]]+)([^>]*)>
                (.*?)
            </\1>}gxcsm
        )
    {
        my ( $tag, $args, $subtext ) = ( $1, $2, $3 );

        # In This text always start tag is <p...>
        if ( $tag ne 'p' ) {
            croak "wrong open tag `$tag' in $fn";
        }
        if ( !$eng ) {    # 1st p. with title  in en
            ($eng) = $subtext =~ m{<span[^>]*>(.+)</span>}xsm;
        }
        elsif ( !$rus ) {
            $rus = $subtext;
            foreach ($rus) {    # 2nd p. with title in ru
                s/^\s+//sxm;
                s/\s+$//sxm;
            }
        }
        else {                  # bible text
            foreach ($subtext) {
                s/^\s//gsmx;
                s/\s$//gsmx;
                s{$RE_VERSE}{<split><verse>$1</verse>}gsmx;
                s{$RE_ITALIC}{<i>$1</i>}gsmx;
                s{$RE_CHAP}{<chap>$1</chap>}gsmx;
            }
            my @sp = split /<split>/xsm, $subtext;
            my @tmp;
            foreach (@sp) {
                s/^\s//gsmx;
                s/\s$//gsmx;
                if (m{<chap>(\d+)</chap>}xsm) {
                    $chap = $1;
                    $vers = 0;
                    s{<chap>\d+</chap>}{}xsm;
                }
                if (m{^<verse>(\d+)</verse>}xsm) {
                    $vers = $1;
                    s{^<verse>(\d+)</verse>}{}xsm;
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
    $outfile                =~ s/\s//gxsm;
    ( my $slug = $outfile ) =~ s/\A\d+-//sm;
    $slug                   =~ s/[.]dat\z//sm;
    my $usfm = $codes->{$slug}
        or croak "no USFM code for book slug '$slug' in usfm-codes.yaml";
    push @description,
        {
        id        => $id,
        file      => $outfile,
        usfm      => $usfm,
        eng       => $eng,
        rus       => $name_fix->{$slug} // $rus,
        testament => exists $deut->{books}->{$id} ? 'DE' : $id > $LAST_OT_ID ? 'NT' : 'OT',
        chapters  => scalar @{ $book->{chapters} } - ( exists $chaps{0} ? 1 : 0 ),
        exists $chaps{0} ? ( prologue => 1 ) : (),
        };
    open my $fh, q{>}, "$PRSD_DIR/$outfile";
    printf {$fh} "%s\n", join "\n#p#\n", map { join "\n", @{$_} } @list;
    close $fh;
}
write_description( "$PRSD_DIR/description.yaml", \@description );

# Записать описание книг в YAML. Порядок полей фиксирован (не алфавитный):
# так диффы описаний разных составов сравнимы глазами.
sub write_description {
    my ( $path, $books ) = @_;

    my @out = ( '# Сгенерировано scripts/10-parse-sources.pl — не редактировать руками.', 'books:', );
    foreach my $b ( @{$books} ) {
        push @out, sprintf '  - id: %d',        $b->{id};
        push @out, sprintf '    file: %s',      $b->{file};
        push @out, sprintf '    usfm: %s',      $b->{usfm};
        push @out, sprintf '    eng: %s',       $b->{eng};
        push @out, sprintf '    rus: %s',       $b->{rus};
        push @out, sprintf '    testament: %s', $b->{testament};
        push @out, sprintf '    chapters: %d',  $b->{chapters};
        if ( $b->{prologue} ) {
            push @out, '    prologue: true';
        }
    }

    open my $fh, q{>}, $path;
    printf {$fh} "%s\n", join "\n", @out;
    close $fh;

    return;
}

1;
