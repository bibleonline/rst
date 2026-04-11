#!/usr/bin/perl

use strict;
use warnings FATAL => 'all';
use autodie qw(:io);
use Config::General;
use v5.10;
use Readonly;
use FindBin qw/$Bin/;

Readonly::Scalar my $SPLIT_LIMIT => 3;
Readonly::Scalar my $NO_MATCH    => -1;

Readonly::Scalar my $ACTION_REMOVE       => 'remove';
Readonly::Scalar my $ACTION_KEEP         => 'keep';
Readonly::Scalar my $ACTION_STRIP_SQUARE => 'strip_square';
Readonly::Scalar my $ACTION_ROUND_SQUARE => 'round';

Readonly::Scalar my $SRC_DIR         => "$Bin/../../parsed";
Readonly::Scalar my $DST_DIR         => "$Bin/..";
Readonly::Scalar my $BOOK_CONF_PATH  => "$Bin/../../parsed/description.conf";
Readonly::Scalar my $RULES_CONF_PATH => "$Bin/../conf/01-rules.conf";
Readonly::Scalar my $DST_CONF_PATH   => "$Bin/../description.conf";

Readonly::Scalar my $BOOK_DESCRIPTION_TPL => <<'TPL';
<book-%d>
%s
</book-%d>
TPL

my %TEXT_ACTIONS = (
    $ACTION_STRIP_SQUARE => \&strip_brackets,
    $ACTION_ROUND_SQUARE => \&round_brackets,
);

run();

# --- Entry point ---

sub run {
    my $book_conf = load_config($BOOK_CONF_PATH);
    my $rules     = load_rules($RULES_CONF_PATH);
    my @books     = get_canonical_books($book_conf);

    my $description = q{};
    my $book_id     = 0;

    for my $book (@books) {
        $book_id++;

        $description .= format_book_description( $book, $book_id );
        filter_and_write_book( $book->{File}, $rules );
    }

    write_file( $DST_CONF_PATH, $description );

    return;
}

# --- Configuration loading ---

sub load_config {
    my ($path) = @_;

    return { Config::General->new($path)->getall };
}

sub load_rules {
    my ($path) = @_;

    my $de = load_config($path)->{DE};

    return {
        chaps   => parse_chapter_rules( $de->{chaps} ),
        replace => parse_replace_rules( $de->{replace} ),
        verse   => parse_verse_rules( $de->{verse} ),
    };
}

# --- Rule parsing ---

sub parse_chapter_rules {
    my ($raw) = @_;

    my $result = {};
    for my $file ( keys %{$raw} ) {
        my $chapters = ensure_arrayref( $raw->{$file} );
        $result->{$file} = { map { $_ => $ACTION_REMOVE } @{$chapters} };
    }

    return $result;
}

sub parse_replace_rules {
    my ($raw) = @_;

    my $result = {};
    for my $file ( keys %{$raw} ) {
        my $entries    = ensure_arrayref( $raw->{$file} );
        my $file_rules = {};

        for my $entry ( @{$entries} ) {
            for my $line ( @{ ensure_arrayref($entry) } ) {
                my ( $place, $from, $to ) = split /\s+/, $line, $SPLIT_LIMIT;
                $file_rules->{$place} = { from => qr/$from/, to => $to };
            }
        }

        $result->{$file} = $file_rules;
    }

    return $result;
}

sub parse_verse_rules {
    my ($raw) = @_;

    my $result = {};
    for my $file ( keys %{$raw} ) {
        my $entries   = ensure_arrayref( $raw->{$file} );
        my $verse_map = {};

        for my $entry ( @{$entries} ) {
            my ( $chapter, $verse_spec ) = split /:/, $entry, 2;
            my $type = $ACTION_REMOVE;

            if ( $verse_spec =~ /(\S+)\s+(\S+)/ ) {
                ( $verse_spec, $type ) = ( $1, $2 );
            }

            expand_verse_spec( $verse_map, $chapter, $verse_spec, $type );
        }

        $result->{$file} = $verse_map;
    }

    return $result;
}

# Modifies $verse_map in place via reference
sub expand_verse_spec {
    my ( $verse_map, $chapter, $spec, $type ) = @_;

    if ( $spec =~ m{(\d+)/(\d+)-(\d+)} ) {
        my ( $verse, $part_from, $part_to ) = ( $1, $2, $3 );
        for my $part ( $part_from .. $part_to ) {
            $verse_map->{$chapter}->{"$verse/$part"} = $type;
        }
        return;
    }

    if ( $spec =~ m{/} ) {
        $verse_map->{$chapter}->{$spec} = $type;
        return;
    }

    my ( $from, $to ) = split /-/, $spec;
    $to //= $from;
    for my $verse ( $from .. $to ) {
        $verse_map->{$chapter}->{$verse} = $type;
    }

    return;
}

# --- Book processing ---

sub get_canonical_books {
    my ($conf) = @_;

    return map { $conf->{$_} }
        sort { extract_num($a) <=> extract_num($b) }
        grep { $conf->{$_}->{Testament} =~ /^[ON]T/ }
        keys %{$conf};
}

sub format_book_description {
    my ( $book, $book_id ) = @_;

    my %desc   = ( %{$book}, id => $book_id );
    my $fields = join "\n", map { join "\t", $_, $desc{$_} } sort keys %desc;

    return sprintf $BOOK_DESCRIPTION_TPL, $book_id, $fields, $book_id;
}

sub filter_and_write_book {
    my ( $file, $rules ) = @_;

    my @lines = filter_book_lines( $file, $rules );

    if ( @lines && $lines[-1] =~ /\#p/ ) {
        pop @lines;
    }
    if ( @lines && $lines[0] =~ /\#p/ ) {
        shift @lines;
    }

    my $dst_path = "$DST_DIR/$file";
    write_file( $dst_path, join "\n", @lines );

    return;
}

sub filter_book_lines {
    my ( $file, $rules ) = @_;

    my @source = read_source_lines($file);
    my @output;
    my $prev_was_nonverse = 0;
    my $last_chapter      = $NO_MATCH;
    my $last_verse        = $NO_MATCH;
    my $verse_occurrence  = 1;
    my $skipped_verses    = {};

    for my $line (@source) {
        if ( $line =~ m/^#(\d+):(\d+)#(.*)/ ) {
            my ( $chapter, $verse, $text ) = ( $1, $2, $3 );
            $text =~ s/\s\[\d+\]\s/ /g;

            if ( $chapter != $last_chapter ) {
                $last_verse       = $NO_MATCH;
                $verse_occurrence = 1;
                $skipped_verses   = {};
            }

            $verse_occurrence
                = ( $last_verse == $verse )
                ? $verse_occurrence + 1
                : 1;

            my $ctx = {
                file       => $file,
                chapter    => $chapter,
                verse      => $verse,
                occurrence => $verse_occurrence,
            };

            my $output_line;
            ( $output_line, $skipped_verses ) = process_verse_line( $rules, $ctx, $text, $skipped_verses );

            if ( defined $output_line ) {
                push @output, $output_line;
                $prev_was_nonverse = 0;
            }

            $last_chapter = $chapter;
            $last_verse   = $verse;
        }
        else {
            next if $prev_was_nonverse;
            push @output, $line;
            $prev_was_nonverse = 1;
        }
    }

    return @output;
}

sub process_verse_line {
    my ( $rules, $ctx, $text, $skipped ) = @_;

    my $action;
    ( $action, $skipped ) = resolve_action( $rules, $ctx, $skipped );

    if ( $action eq $ACTION_REMOVE ) {
        return ( undef, $skipped );
    }

    $text = apply_text_action( $action, $text );
    warn_if_only_brackets( $ctx->{file}, $ctx->{chapter}, $ctx->{verse}, $text );
    $text = apply_replacement( $rules->{replace}, $ctx, $text );

    my $adjusted_verse = $ctx->{verse} - scalar keys %{$skipped};
    my $line = sprintf '#%d:%d#%s', $ctx->{chapter}, $adjusted_verse, $text;

    return ( $line, $skipped );
}

# --- Action resolution and application ---

sub resolve_action {
    my ( $rules, $ctx, $skipped ) = @_;

    my $file       = $ctx->{file};
    my $chapter    = $ctx->{chapter};
    my $verse      = $ctx->{verse};
    my $occurrence = $ctx->{occurrence};

    if ( my $action = rule_lookup( $rules->{chaps}, $file, $chapter ) ) {
        return ( $action, $skipped );
    }

    my $verse_part = "$verse/$occurrence";
    if ( my $action = rule_lookup( $rules->{verse}, $file, $chapter, $verse_part ) ) {
        return ( $action, $skipped );
    }

    if ( my $action = rule_lookup( $rules->{verse}, $file, $chapter, $verse ) ) {
        if ( $verse && $action eq $ACTION_REMOVE ) {
            $skipped->{$verse}++;
        }
        return ( $action, $skipped );
    }

    return ( $ACTION_KEEP, $skipped );
}

sub apply_text_action {
    my ( $action, $text ) = @_;

    if ( my $handler = $TEXT_ACTIONS{$action} ) {
        return $handler->($text);
    }

    return $text;
}

sub strip_brackets {
    my ($text) = @_;

    $text =~ s{ ^ [^\]]+ \] \s* }{}xg;    # leading partial: ...text]
    $text =~ s{ \s* \[ [^\]]+ $ }{}xg;    # trailing partial: [text...
    $text =~ s/\s+\[[^\[\]]+\]/ /g;       # inner with leading space
    $text =~ s/\[[^\[\]]+\]\s+/ /g;       # inner with trailing space

    return $text;
}

sub round_brackets {
    my ($text) = @_;

    $text =~ tr/[]/()/;

    return $text;
}

sub warn_if_only_brackets {
    return;
}

sub apply_replacement {
    my ( $replace_rules, $ctx, $text ) = @_;

    my $file = $ctx->{file};
    my $cv   = "$ctx->{chapter}:$ctx->{verse}";
    my $cvn  = "$cv/$ctx->{occurrence}";

    my $rule = rule_lookup( $replace_rules, $file, $cvn ) // rule_lookup( $replace_rules, $file, $cv );

    if ( ref $rule eq 'HASH' ) {
        my $to = $rule->{to};
        $text =~ s/$rule->{from}/$to/;
    }

    return $text;
}

# --- I/O ---

sub read_source_lines {
    my ($file) = @_;

    my $path = "$SRC_DIR/$file";
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

# --- Utilities ---

sub ensure_arrayref {
    my ($val) = @_;

    return ref $val eq 'ARRAY' ? $val : [$val];
}

sub rule_lookup {
    my ( $hash, @keys ) = @_;

    for my $key (@keys) {
        return if ref $hash ne 'HASH';
        return if !exists $hash->{$key};
        $hash = $hash->{$key};
    }

    return $hash;
}

sub extract_num {
    my ($str) = @_;

    $str =~ s/\D//g;

    return $str;
}
