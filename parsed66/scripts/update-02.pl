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

my $punct = qr/\s*[,.:;!?]?\s*/;

my %SIMPLE_HANDLERS = (
    delete => sub {
        my ( $i, $tt ) = @_;
        $tt->[$i] = q{};
    },
    italic => sub {
        my ( $i, $tt ) = @_;
        $tt->[$i] =~ s/[\[\]]//g;
        $tt->[$i] = sprintf '<i>%s</i>', $tt->[$i];
    },
    unwrap => sub {
        my ( $i, $tt ) = @_;
        $tt->[$i] =~ s/[\[\]]//g;
    },
    round => sub {
        my ( $i, $tt ) = @_;
        $tt->[$i] =~ s/[\[\]]//g;
        $tt->[$i] = sprintf '(%s)', $tt->[$i];
    },
    keep => sub {
        my ( $i, $tt ) = @_;
        $tt->[$i] =~ s/\[/{/;
        $tt->[$i] =~ s/\]/}/;
    },
    capitalize => sub {
        my ( $i, $tt ) = @_;
        $tt->[ $i + 1 ] =~ s/(\s*)(\S)/$1\u$2/;
    },
    lowercase => sub {
        my ( $i, $tt ) = @_;
        $tt->[ $i + 1 ] =~ s/(\s*)(\S)/$1\l$2/;
    },
    'shift-left' => sub {
        my ( $i, $tt ) = @_;
        $tt->[ $i + 1 ] =~ /(\S+)/;
        $tt->[ $i - 1 ] .= " $1";
        $tt->[ $i + 1 ] =~ s/^\s*\S+//;
    },
);

my %COMPLEX_HANDLERS = (
    strip      => \&apply_strip,
    insert     => \&apply_insert,
    replace    => \&apply_replace,
    regex      => \&apply_regex,
    substitute => \&apply_substitute,
    'pull-in'  => \&apply_pull_in,
);

my %STRIP_RE = (
    left  => { punct => qr/${punct}$/,    word => qr/\S+\s*$/ },
    right => { punct => qr/^${punct}/,    word => qr/^\s*\S+/ },
    begin => { punct => qr/^${punct}/,    word => qr/^\s*\S+/ },
    inner => { punct => qr/${punct}\s*]/, word => qr/\s*\S+\s*]/ },
);

my %STRIP_REPL = ( inner => q{]} );

my %INSERT_HANDLERS = (
    left  => sub { my ( $tt, $i, $text ) = @_; $tt->[ $i - 1 ] .= " $text" },
    right => sub { my ( $tt, $i, $text ) = @_; $tt->[ $i + 1 ] = join q{ }, $text, $tt->[ $i + 1 ] },
    end   => sub { my ( $tt, $i, $text ) = @_; $tt->[-1] .= " $text" },
    inner => sub { my ( $tt, $i, $text ) = @_; $tt->[$i] =~ s/]/ $text]/ },
    begin => sub {
        my ( $tt, $i, $text, $at ) = @_;
        if ($at) {
            my @words = split / /, $tt->[0];
            $words[ $at - 1 ] =~ s/(\S+\b)/$1 $text/;
            $tt->[0] = join q{ }, @words;
        }
        else {
            $tt->[0] =~ s/^/$text /;
        }
    },
);

run();

# --- Entry point ---

sub run {
    my $data = load_rules("$Bin/../conf/02-square.yaml");

    open my $log_fh, '>', "$Bin/../conf/02-square.txt";

    validate_rule_files($data);

    for my $file ( sort keys %{$data} ) {
        process_file( $file, $data->{$file}, $log_fh );
    }

    close $log_fh;

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
        die "Unknown files in rules:\n" . join( "\n", map {"  $_"} @missing ) . "\n";
    }

    return;
}

# --- Config loading ---

sub load_rules {
    my ($path) = @_;

    my $ypp  = YAML::PP->new;
    my $yaml = $ypp->load_file($path);
    my $data = {};

    for my $file ( keys %{$yaml} ) {
        for my $entry ( @{ $yaml->{$file} } ) {
            my $place   = $entry->{place};
            my $par     = $entry->{occurrence} // 1;
            my $bracket = $entry->{bracket}    // 0;

            my $do      = $entry->{do};
            my @actions = ref $do eq 'ARRAY' ? @{$do} : ($do);

            if ($bracket) {
                my $cur = $data->{$file}->{$place}->{$par}->{totsq} // 0;
                if ( $bracket > $cur ) {
                    $data->{$file}->{$place}->{$par}->{totsq} = $bracket;
                }
            }

            $data->{$file}->{$place}->{$par}->{act} ||= [];
            push @{ $data->{$file}->{$place}->{$par}->{act} },
                {
                num     => $bracket,
                actions => \@actions,
                str     => fmt_log( $file, $place, $par, $bracket, \@actions ),
                };
        }
    }

    return $data;
}

sub fmt_log {
    my ( $file, $place, $par, $bracket, $actions ) = @_;

    my $loc = $place;
    if ( $par > 1 ) {
        $loc .= "/$par";
    }
    if ($bracket) {
        $loc .= ".$bracket";
    }

    my @parts;
    for my $a ( @{$actions} ) {
        if ( !ref $a ) {
            push @parts, $a;
        }
        else {
            my ($key) = keys %{$a};
            my $val   = $a->{$key};
            push @parts, $key . q{: } . fmt_val($val);
        }
    }

    return "$file\t$loc\t" . join q{ / }, @parts;
}

sub fmt_val {
    my ($v) = @_;
    if ( ref $v eq 'HASH' ) {
        my @kv;
        for my $k ( sort keys %{$v} ) {
            push @kv, "$k=" . fmt_val( $v->{$k} );
        }
        return '{' . join( ', ', @kv ) . '}';
    }
    return $v;
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

    my ($tx)     = $line =~ m{#\S+#(.+)};
    my $old_tx = $tx;

    if ( $dat->{totsq} ) {
        my $sq = () = $tx =~ /(\[)/g;
        if ( $dat->{totsq} != $sq ) {
            warn "NOT SAME SQ, WAIT $dat->{totsq} BUT IN TEXT $sq\n$place $tx\n";
            exit;
        }
    }

    for my $act ( @{ $dat->{act} } ) {
        for my $action_def ( @{ $act->{actions} } ) {
            my @tt = split /(\[.*?\])/, $tx;
            if ( $tt[0] =~ /\[/ ) {
                unshift @tt, q{};
            }
            if ( !( @tt % 2 ) ) {
                push @tt, q{};
            }

            apply_action( $action_def, 1, \@tt, "$file $place" );

            if ( !$act->{num} ) {
                my $i = 3;
                while ( $i < @tt ) {
                    apply_action( $action_def, $i, \@tt, "$file $place" );
                    $i += 2;
                }
            }
            $tx = join q{ }, @tt;
        }

        printf {$log_fh} "%s\n", $act->{str};
    }

    $tx = fixstr($tx);
    printf {$log_fh} "#OLD: %s\n#NEW: %s\n\n", $old_tx, $tx;

    return sprintf '#%s#%s', $place, $tx;
}

# --- Action dispatch ---

sub apply_action {
    my ( $action_def, $i, $tt, $location ) = @_;

    if ( !ref $action_def ) {
        apply_simple( $action_def, $i, $tt, $location );
    }
    else {
        my ($type) = keys %{$action_def};
        my $params = $action_def->{$type};
        apply_complex( $type, $params, $i, $tt, $location );
    }

    return;
}

sub apply_simple {
    my ( $action, $i, $tt, $location ) = @_;

    my $handler = $SIMPLE_HANDLERS{$action} // die "Unknown simple action: $action at $location\n";
    $handler->( $i, $tt );

    return;
}

sub apply_complex {
    my ( $type, $params, $i, $tt, $location ) = @_;

    my $handler = $COMPLEX_HANDLERS{$type} // die "Unknown complex action: $type at $location\n";
    $handler->( $params, $i, $tt, $location );

    return;
}

# --- Strip (remove words/punctuation) ---

sub apply_strip {
    my ( $params, $i, $tt ) = @_;

    my ( $side, $what ) = extract_side($params);
    my $count = $params->{count} // 1;
    my $at    = $params->{at};

    # word-at: remove word at specific position (ONEWORD)
    if ($at) {
        if ( $side eq 'end' ) {
            my @words = reverse split / /, $tt->[-1];
            splice @words, $at - 1, 1;
            $tt->[-1] = join q{ }, reverse @words;
        }
        return;
    }

    my %idx  = ( left => $i - 1, right => $i + 1, begin => 0, inner => $i );
    my $re   = $STRIP_RE{$side}{$what};
    my $repl = $STRIP_REPL{$side} // q{};

    for ( 1 .. $count ) {
        $tt->[ $idx{$side} ] =~ s/$re/$repl/;
    }

    return;
}

# --- Insert (add text/punctuation) ---

sub apply_insert {
    my ( $params, $i, $tt ) = @_;

    my ( $side, $text ) = extract_side($params);
    my $at = $params->{at};

    # Convert unicode em-dash to HTML entity for .dat format
    $text =~ s/\x{2014}/&mdash;/g;

    $INSERT_HANDLERS{$side}->( $tt, $i, $text, $at );

    return;
}

# --- Replace (bracket content) ---

sub apply_replace {
    my ( $params, $i, $tt ) = @_;

    my ( $text, $italic );
    if ( ref $params eq 'HASH' ) {
        $text   = $params->{text};
        $italic = $params->{italic};
    }
    else {
        $text   = $params;
        $italic = 0;
    }

    $tt->[$i] = $italic ? "<i>$text</i>" : $text;

    return;
}

# --- Regex (substitution in verse text) ---

sub apply_regex {
    my ( $params, $i, $tt ) = @_;

    my $from = $params->{from};
    my $to   = $params->{to};
    $tt->[0] =~ s{$from}{$to};

    return;
}

# --- Substitute (literal string replacement) ---

sub apply_substitute {
    my ( $params, $i, $tt, $location ) = @_;

    my $from = $params->{from};
    my $to   = $params->{to};

    foreach ( @{$tt} ) {
        if ( index( $_, $from ) >= 0 ) {
            s/ $from / $to /x;
            last;
        }
    }

    return;
}

# --- Pull-in (move words into bracket) ---

sub apply_pull_in {
    my ( $count, $i, $tt ) = @_;

    for ( 1 .. $count ) {
        my ($word) = $tt->[ $i - 1 ] =~ /(\S+)\s*$/;
        $tt->[$i] =~ s/^\[/[$word /;
        $tt->[ $i - 1 ] =~ s/(\S+)\s*$//;
    }

    return;
}

# --- Helpers ---

sub extract_side {
    my ($params) = @_;

    for my $key (qw(left right begin inner end)) {
        if ( exists $params->{$key} ) {
            return ( $key, $params->{$key} );
        }
    }

    die "No side found in params\n";
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
