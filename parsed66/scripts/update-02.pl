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

my $punct     = qr/\s*[,\.:;!?]?\s*/;                                                                                  ## no critic (ProhibitEscapedMetacharacters)
my $REMOVE_RE = qr/^REMOVE-(BEGIN|LEFT|LAST|RIGHT|END)-(ONEWORD|WORD|PUNCTUATION)(?:[:](\d+))?$/;                      ## no critic (ProhibitComplexRegexes)
my $ADD_RE    = qr/^ADD-(BEGIN|LEFT|LAST|RIGHT|END)-(TEXT|COLON|EXCLAMATION|SEMICOLON|DASH|DOT|COMMA)(?:[:](\d+))?$/;  ## no critic (ProhibitComplexRegexes)
my %tdata     = (
    COLON       => q{:},
    EXCLAMATION => q{!},
    SEMICOLON   => q{;},
    DASH        => q{&mdash;},
    DOT         => q{.},
    COMMA       => q{,},
);

my %SIMPLE_ACTIONS = (
    SKIP => sub {
        my ( $act, $i, $tt ) = @_;
        $tt->[$i] =~ s/\[/{/;
        $tt->[$i] =~ s/\]/}/;
    },
    GONEXT => sub { },
    DEL    => sub {
        my ( $act, $i, $tt ) = @_;
        $tt->[$i] = q{};
    },
    REPLACE => sub {
        my ( $act, $i, $tt ) = @_;
        $tt->[0] =~ s{$act->{data}->[0]}{$act->{data}->[1]};
    },
    'REP-STR' => sub {
        my ( $act, $i, $tt, $location ) = @_;
        if ( scalar @{ $act->{data} } != 2 ) {
            die "NOT TWO DAT $location";
        }
        foreach ( @{$tt} ) {
            if ( index( $_, $act->{data}->[0] ) >= 0 ) {
                s/ $act->{data}->[0] / $act->{data}->[1] /x;
                last;
            }
        }
    },
    'MOVE-RIGHTWORD-LEFT' => sub {
        my ( $act, $i, $tt ) = @_;
        $tt->[ $i + 1 ] =~ /(\S+)/;
        $tt->[ $i - 1 ] .= " $1";
        $tt->[ $i + 1 ] =~ s/^\s*\S+//;
    },
);

run();

# --- Entry point ---

sub run {
    my $data = load_rules("$Bin/../conf/02-square77to66.conf");

    open my $log_fh, '>', "$Bin/../conf/02-square77to66.txt";

    for my $file ( sort keys %{$data} ) {
        process_file( $file, $data->{$file}, $log_fh );
    }

    close $log_fh;

    return;
}

# --- Config loading ---

sub load_rules {
    my ($path) = @_;

    my $data = {};
    my $prev = {};

    my @lines = read_lines($path);
    for (@lines) {
        next if !/\S/;
        if (/^(\S+[.]dat)\t(\S+)\t+(\S+)(.*)/) {
            my ( $file, $place, $action, $subdata ) = ( $1, $2, $3, $4 );

            my %tmp = ( action => [ split m{/}, $action ], str => $_ );

            if ( $subdata =~ /#\s*(\S+.*\S)/ ) {
                $tmp{warn} = $1;
            }
            foreach ($subdata) {
                s/\s*\#.*//;
                s/^\s+//;
                s/\s+$//;
            }
            if ($subdata) {
                $tmp{data} = [ split /\t/, $subdata ];
                foreach ( @{ $tmp{data} } ) {
                    s/^"//g;
                    s/"$//g;

                }
            }

            my ( $par, $num );
            ( $place, $par, $num ) = parse_place($place);
            if ($num) {
                $data->{$file}->{$place}->{$par}->{totsq} = $num;
            }
            $data->{$file}->{$place}->{$par}->{act} ||= [];
            push @{ $data->{$file}->{$place}->{$par}->{act} }, { num => $num, par => $par, %tmp };
            $prev = { file => $file, place => $place, par => $par };
        }
        elsif (/^\#(.+)/) {
            my $text = $1;
            if ( $text !~ /WARN/ ) {
                $data->{ $prev->{file} }->{ $prev->{place} }->{ $prev->{par} }->{text} = $text;
            }

        }
        else {
            warn "UNKNOWN $_\n";
        }
    }

    return $data;
}

# Разбирает place вида "1:2/3.4", "1:2.4", "1:2/3" или "1:2"
# Возвращает (place, параграф, номер скобки)
sub parse_place {
    my ($place) = @_;

    my ( $par, $num ) = ( 1, 0 );
    if ( $place =~ m{^(\S+)/(\d+)[.](\d+)$} ) {    # place/par.num
        ( $place, $par, $num ) = ( $1, $2, $3 );
    }
    elsif ( $place =~ m{^(\S+)[.](\d+)$} ) {       # place.num
        ( $place, $num ) = ( $1, $2 );
    }
    elsif ( $place =~ m{^(\S+)/(\d+)$} ) {         # place/par
        ( $place, $par ) = ( $1, $2 );
    }

    return ( $place, $par, $num );
}

# --- File processing ---

sub process_file {
    my ( $file, $file_rules, $log_fh ) = @_;

    my @filedata;
    my @lines      = read_lines("$Bin/../$file");
    my $last_place = q{};
    my $par        = 0;
    for (@lines) {
        my ($place) = /^#(\S+)#.+/;
        if ( !defined $place ) {
            push @filedata, $_;
            next;
        }
        if ( $place ne $last_place ) {
            $last_place = $place;
            $par        = 0;
        }
        $par++;

        if ( exists $file_rules->{$place} && exists $file_rules->{$place}->{$par} ) {
            my $result = apply_file_rule( $file, $place, $_, $file_rules->{$place}->{$par}, $log_fh );
            push @filedata, $result;
        }
        else {
            push @filedata, $_;
        }
    }
    write_file( "$Bin/../$file", join "\n", @filedata );

    return;
}

# --- Rule application ---

sub apply_file_rule {
    my ( $file, $place, $line, $dat, $log_fh ) = @_;

    my ($tx) = $line =~ m{#\S+#(.+)};

    if ( $tx ne $dat->{text} ) {
        warn "NOT SAME TEXT at $place\nORG $tx\nBUT  $dat->{text}\n$line";
        return $line;
    }

    if ( $dat->{totsq} ) {
        my $sq = () = $tx =~ /(\[)/g;
        if ( $dat->{totsq} != $sq ) {
            warn "NOT SAME SQ, WAIT $dat->{totsq} BUT IN TEXT $sq\n$place $tx\n";
            exit;
        }
    }

    for my $act ( @{ $dat->{act} } ) {
        for my $action ( @{ $act->{action} } ) {
            my @tt = split /(\[.*?\])/, $tx;
            if ( $tt[0] =~ /\[/ ) {
                unshift @tt, q{};
            }
            if ( !( @tt % 2 ) ) {
                push @tt, q{};
            }

            for ( my $i = 1; !$act->{num} && $i < @tt || $i == 1; $i += 2 ) {    ## no critic (ProhibitCStyleForLoops)
                apply_action( $action, $act, $i, \@tt, "$file $place" );
            }
            $tx = join q{ }, @tt;
        }

        printf {$log_fh} "%s\n", $act->{str};

    }

    $tx = fixstr($tx);
    printf {$log_fh} "#OLD: %s\n#NEW: %s\n\n", $dat->{text}, $tx;

    return sprintf '#%s#%s', $place, $tx;
}

# --- Action dispatch ---

sub apply_action {    ## no critic (ProhibitExcessComplexity, ProhibitCascadingIfElse)
    my ( $action, $act, $i, $tt, $location ) = @_;

    if ( my $handler = $SIMPLE_ACTIONS{$action} ) {
        $handler->( $act, $i, $tt, $location );
        return;
    }

    if ( $action =~ /^REP(-IT|-NOIT|-ROUND)$/ ) {    ## no critic (ProhibitCascadingIfElse)
                                                     # убрать скобки, обернуть форматом
        my $variant = $1;
        my $fmt     = '%s';
        if ( $variant eq '-IT' ) {
            $fmt = '<i>%s</i>';
        }
        elsif ( $variant eq '-ROUND' ) {
            $fmt = '(%s)';
        }
        $tt->[$i] =~ s/[\[\]]//g;
        $tt->[$i] = sprintf $fmt, $tt->[$i];
    }
    elsif ( $action =~ $REMOVE_RE ) {

        # удалить слово/пунктуацию
        apply_remove_action( $1, $2, $3 || 1, $i, $tt );
    }
    elsif ( $action =~ /^REP([+]IT)?$/ ) {

        # заменить на текст из data
        my $it = $1 && $1 eq '+IT' ? 1 : 0;
        if ( scalar @{ $act->{data} } != 1 ) {
            die "NOT ONE DAT $location";
        }
        $tt->[$i] = sprintf $it ? '<i>%s</i>' : '%s', $act->{data}->[0];
    }
    elsif ( $action =~ $ADD_RE ) {

        # вставить текст/пунктуацию
        apply_add_action( $1, $2, $3 || 0, $act, $i, $tt, $location );
    }
    elsif ( $action =~ /^NEXT-(UP|DOWN)$/ ) {

        # регистр следующего слова
        if ( $1 eq 'UP' ) {
            $tt->[ $i + 1 ] =~ s/(\s*)(\S)/$1\u$2/;
        }
        else {
            $tt->[ $i + 1 ] =~ s/(\s*)(\S)/$1\l$2/;
        }
    }
    elsif ( $action =~ /MOVE-LEFTWORD-START:(\d+)/ ) {

        # перенести слова внутрь скобки
        my $count = $1;
        for ( 1 .. $count ) {
            my ($word) = $tt->[ $i - 1 ] =~ /(\S+)\s*$/;
            $tt->[$i] =~ s/^\[/[$word /;
            $tt->[ $i - 1 ] =~ s/(\S+)\s*$//;
        }
    }
    else {
        warn 'NOACTION[' . ( $act->{num} ? 'MULTY' : 'ONE' ) . ":$i]: [$action]";
    }

    return;
}

sub apply_remove_action {
    my ( $where, $what, $count, $i, $tt ) = @_;

    # одно слово с конца строки
    if ( $what eq 'ONEWORD' ) {
        if ( $where eq 'END' ) {

            my @words = reverse split / /, $tt->[-1];
            splice @words, $count - 1, 1;
            $tt->[-1] = join q{ }, reverse @words;
        }
        return;
    }

    for ( 1 .. $count ) {
        if ( $where eq 'LEFT' ) {

            # слева от скобки
            if ( $what eq 'PUNCTUATION' ) {
                $tt->[ $i - 1 ] =~ s/${punct}$//;
            }
            else {
                $tt->[ $i - 1 ] =~ s/\S+\s*$//;
            }
        }
        elsif ( $where eq 'RIGHT' ) {

            # справа от скобки
            if ( $what eq 'PUNCTUATION' ) {
                $tt->[ $i + 1 ] =~ s/^${punct}//;
            }
            else {
                $tt->[ $i + 1 ] =~ s/^\s*\S+//;
            }
        }
        elsif ( $where eq 'BEGIN' ) {

            # с начала строки
            if ( $what eq 'PUNCTUATION' ) {
                $tt->[0] =~ s/^${punct}//;
            }
            else {
                $tt->[0] =~ s/^\s*\S+//;
            }
        }
        else {
            # внутри скобки (LAST)
            if ( $what eq 'PUNCTUATION' ) {
                $tt->[$i] =~ s/${punct}\s*\]/]/;
            }
            else {
                $tt->[$i] =~ s/\s*\S+\s*\]/]/;
            }
        }
    }

    return;
}

sub apply_add_action {    ## no critic (ProhibitManyArgs)
    my ( $where, $what, $count, $act, $i, $tt, $location ) = @_;

    my $text = q{};
    if ( $what eq 'TEXT' ) {
        if ( scalar @{ $act->{data} } != 1 ) {
            die "NOT ONE DAT $location";
        }
        $text = $act->{data}->[0];
    }
    else {
        $text = $tdata{$what};
    }

    if ( $where eq 'LEFT' ) {    ## no critic (ProhibitCascadingIfElse)
        $tt->[ $i - 1 ] .= " $text";
    }
    elsif ( $where eq 'RIGHT' ) {
        $tt->[ $i + 1 ] = join q{ }, $text, $tt->[ $i + 1 ];
    }
    elsif ( $where eq 'END' ) {
        $tt->[-1] .= " $text";
    }
    elsif ( $where eq 'BEGIN' ) {
        if ($count) {
            my @words = split / /, $tt->[0];
            $words[ $count - 1 ] =~ s/(\S+\b)/$1 $text/;
            $tt->[0] = join q{ }, @words;
        }
        else {
            $tt->[0] =~ s/^/$text /;
        }
    }
    else {    # LAST
        $tt->[$i] =~ s/\]/ $text]/;
    }

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

# --- Text cleanup ---

sub fixstr {
    my $str = shift;

    foreach ($str) {
        s{\s+»}{»}g;
        s{«\s+}{«}g;
        s/^\s+//;
        s/\s+$//;
        s/\s+([,.!?:;])/$1/g;
        s/\s+/ /g;
        s/{/[/g;
        s/}/]/g;
    }

    return $str;
}
