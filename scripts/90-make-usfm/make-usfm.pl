#!perl
# Генератор USFM: из parsed<состав>/*.dat собирает usfm/rst<состав>/*.usfm
# и BookNames.xml к каждому составу.
#
# Результат сначала пишется в usfm2/, затем переносится в usfm/ только для
# изменившихся файлов — прогон идемпотентен, повторный запуск не трогает диск.

use strict;
use warnings;
use v5.10;
use English     qw(-no_match_vars);
use FindBin     qw($Bin);
use File::Path  qw(remove_tree);
use Encode      qw(decode_utf8 encode_utf8);
use Digest::MD5 qw(md5_hex);
use Data::Dumper;
use Readonly;
use YAML::PP;

Readonly my $ROOT  => "$Bin/../..";
Readonly my @TYPES => qw(78 66 81);

# Номера файлов книг с особой структурой вступления: у Есфири вступление
# закрывается \ie перед первой главой, у Сираха оно ещё и озаглавлено.
Readonly my $ESTHER_ID => 21;
Readonly my $SIRACH_ID => 28;

# U+0301 COMBINING ACUTE ACCENT — ударение, в исходниках стоит как &#769;
Readonly my $ACUTE => 769;

# «Ещё не было ни одной главы/стиха» — начальное состояние разбора книги.
Readonly my $NOTHING_YET => -1;

# Подробный лог разбора примечаний: нужен, когда правишь notes*.yaml и надо
# видеть, какое издание выбралось для стиха. По умолчанию молчим — за потоком
# отладки не видно ни ошибок, ни того, какие файлы изменились.
Readonly my $VERBOSE => $ENV{VERBOSE} ? 1 : 0;

# Сколько изменившихся файлов перечислять в сводке, прежде чем свернуть остаток.
Readonly my $REPORT_LIMIT => 8;

# Знаки конца фрагмента для разметки слов Христа (\wj).
Readonly my %CHAR_RE => (
    exclamation => qr/[!]/,
    colon       => qr/[:]/,
    dot         => qr/[.]/,
    question    => qr/[?]/,
    comma       => qr/[,]/,
);

foreach my $type (@TYPES) {
    build_edition($type);
}

# Сборка одного состава целиком: конфиги -> книги -> BookNames -> перенос.
sub build_edition {
    my ($type) = @_;

    my $conf   = load_conf("$ROOT/conf/booknames.yaml");
    my $codes  = load_conf("$ROOT/conf/usfm-codes.yaml")->{codes};
    my $uconf  = load_conf("$Bin/usfm.yaml");
    my $esv    = load_conf("$ROOT/conf/redletter.yaml")->{woc};
    my $alt    = normalize_alt( load_conf("$Bin/alt.yaml")->{ 'rst' . $type } );
    my $anotes = index_notes( load_conf("$Bin/notes$type.yaml") );

    # Структурные примечания состава (необязательный файл): объясняют, где
    # текст стоял в печатном издании и куда переехал. Врезаются в конец стиха.
    my $extra_path = "$ROOT/conf/notes$type-extra.yaml";
    my $extra      = -e $extra_path ? load_conf($extra_path)->{books} : {};

    my $rnote = select_paper_notes(
        anotes => $anotes,
        paper  => load_paper_notes("$ROOT/conf/paper-notes.yaml"),
    );

    my $parsed = "$ROOT/parsed$type/";
    my $out    = "$ROOT/usfm/rst$type/";
    my $out2   = "$ROOT/usfm2/rst$type/";
    foreach my $dir ( "$ROOT/usfm2/", $out, $out2 ) {
        next if -d $dir;
        mkdir $dir or die "mkdir $dir: $OS_ERROR\n";
    }

    my @books      = grep {/[.]dat\z/} read_dir($parsed);
    my %in_edition = map  { book_code( $codes, $_ ) => 1 } @books;
    check_extra_targets(
        extra    => $extra,
        known    => \%in_edition,
        chapters => chapter_counts("${parsed}description.yaml"),
        type     => $type,
    );

    my @booknames;
    foreach my $book (@books) {
        debug("= $book =");
        my ( $id, $sid ) = $book =~ /\A(\d+)-(.+)[.]dat\z/;
        my $cfg  = $conf->{$sid};
        my $code = book_code( $codes, $book );

        push @booknames, sprintf '<book code="%s" abbr="%s" short="%s" long="%s" />',
            $code, $cfg->{abbr}, $cfg->{name}, $cfg->{long};

        render_book(
            file  => "$parsed$book",
            path  => "$out2$id-$sid.usfm",
            id    => $id,
            sid   => $sid,
            code  => $code,
            type  => $type,
            ucfg  => $uconf->{$sid},
            note  => $rnote->{$sid} || {},
            extra => $extra->{$sid} || {},
            alt   => $alt->{$sid}   || {},
            esv   => $esv->{$sid},
        );
    }

    write_file( "${out2}BookNames.xml", join "\n", '<?xml version="1.0" encoding="utf-8"?>',
        '<BookNames>', @booknames, '</BookNames>', q{} );

    my $synced = sync_output( $out, $out2 );
    remove_tree("$ROOT/usfm2/");
    report_edition( $type, scalar @books, $synced );
    return;
}

sub book_code {
    my ( $codes, $book ) = @_;

    my ($sid) = $book =~ /\A\d+-(.+)[.]dat\z/;
    my $code = uc( $codes->{$sid} // q{} );
    $code or die "no usfm code for $sid\n";
    return $code;
}

# Число глав по книгам состава — из описания, которое пишет сборка .dat.
sub chapter_counts {
    my ($path) = @_;

    return {} if !-e $path;
    my %count;
    foreach my $book ( @{ load_conf($path)->{books} || [] } ) {
        next if !$book->{usfm};
        $count{ uc $book->{usfm} } = $book->{chapters};
    }
    return \%count;
}

# Цель ссылки \x обязана быть книгой этого же состава и её существующей главой.
# Иначе в выгрузку молча уезжает ссылка в никуда: сам USFM её не проверяет, а
# глазами такое ловится только сплошным просмотром сносок.
sub check_extra_targets {
    my (%arg) = @_;
    my ( $extra, $known, $chapters, $type ) = @arg{qw(extra known chapters type)};

    foreach my $sid ( sort keys %{$extra} ) {
        foreach my $ch ( sort keys %{ $extra->{$sid} } ) {
            foreach my $vs ( sort keys %{ $extra->{$sid}->{$ch} } ) {
                foreach my $note ( @{ extra_list( $extra->{$sid}->{$ch}->{$vs} ) } ) {
                    check_targets_at(
                        entry    => $note,
                        known    => $known,
                        chapters => $chapters,
                        where    => "notes$type-extra.yaml: $sid $ch:$vs",
                    );
                }
            }
        }
    }
    return;
}

sub check_targets_at {
    my (%arg) = @_;
    my ( $entry, $known, $chapters, $where ) = @arg{qw(entry known chapters where)};

    foreach my $target ( @{ $entry->{xt} || [] } ) {
        my ( $code, $chapter ) = split /\s+/, $target;
        $code = uc( $code // q{} );
        if ( !$known->{$code} ) {
            die "$where -> '$target': книги $code нет в этом составе\n";
        }

        my $total = $chapters->{$code};
        next if !$total || !defined $chapter;
        if ( $chapter !~ /\A\d+\z/ || $chapter < 1 || $chapter > $total ) {
            die "$where -> '$target': в книге $code глав $total\n";
        }
    }
    return;
}

# alt.yaml задаёт альтернативную нумерацию сжато: «стих[-стих] дельта», где
# дельта '*' — стих без номера в 66-й нумерации. Разворачиваем в карту
# «печатный стих -> номер в 66-й нумерации».
sub normalize_alt {
    my ($alt) = @_;

    foreach my $bookid ( keys %{$alt} ) {
        foreach my $chap ( keys %{ $alt->{$bookid} } ) {
            my $src = $alt->{$bookid}->{$chap};
            if ( ref $src ne ref [] ) { $src = [$src] }
            my %map;
            foreach my $ver ( @{$src} ) {
                my ( $v, $delta ) = split /\s+/, $ver, 2;
                my ( $v1, $v2 ) = split /-/, $v;
                $v2 ||= $v1;
                foreach my $ve ( $v1 .. $v2 ) {
                    $map{$ve} = $delta eq q{*} ? $delta : $ve + $delta;
                }
            }
            $alt->{$bookid}->{$chap} = {%map};
        }
    }
    return $alt;
}

# notes<состав>.yaml: «издание» или «издание/якорное слово». Раскладываем по
# якорю, ANY — примечание без привязки к слову.
sub index_notes {
    my ($notes) = @_;

    my $anotes = {};
    foreach my $id ( keys %{$notes} ) {
        foreach my $ch ( keys %{ $notes->{$id} } ) {
            foreach my $vs ( keys %{ $notes->{$id}->{$ch} } ) {
                my $src = $notes->{$id}->{$ch}->{$vs};
                if ( ref $src ne ref [] ) { $src = [$src] }
                foreach my $s ( @{$src} ) {
                    my ( $tx, $wd ) = ( $s, 'ANY' );
                    if ( $s =~ m{(.*)/(.*)} ) {
                        ( $tx, $wd ) = ( $1, $2 );
                    }
                    $anotes->{$id}->{$ch}->{$vs}->{$wd} = $tx;
                }
            }
        }
    }
    return $anotes;
}

# Из всех примечаний печатных изданий отбираем те, что подходят изданию,
# указанному для этого стиха в notes<состав>.yaml.
sub select_paper_notes {
    my (%arg) = @_;
    my ( $anotes, $paper ) = @arg{qw(anotes paper)};

    my $rnote = {};
    foreach my $id ( keys %{$paper} ) {
        foreach my $ch ( keys %{ $paper->{$id} } ) {
            foreach my $vs ( keys %{ $paper->{$id}->{$ch} } ) {
                collect_verse_notes(
                    rnote  => $rnote,
                    anotes => $anotes->{$id}->{$ch}->{$vs},
                    paper  => $paper->{$id}->{$ch}->{$vs},
                    id     => $id,
                    ch     => $ch,
                    vs     => $vs,
                );
            }
        }
    }
    return $rnote;
}

sub collect_verse_notes {
    my (%arg) = @_;
    my ( $rnote, $anotes, $paper, $id, $ch, $vs ) = @arg{qw(rnote anotes paper id ch vs)};

    my $wanted
        = exists $anotes->{ANY}
        ? [ { word => 'ANY', t => $anotes->{ANY} } ]
        : [ map { { word => $_, t => $anotes->{$_} } } keys %{$anotes} ];
    my $src = ref $paper eq ref [] ? $paper : [$paper];

    foreach my $w ( @{$wanted} ) {
        my ( $word, $t ) = ( $w->{word}, $w->{t} );
        foreach my $s ( @{$src} ) {
            my ( $tr, $wd, $text ) = ( q{}, 'ANY', q{} );
            if ( $vs =~ /\A\d+\z/ ) {    # примечание к стиху — есть якорное слово
                ( $tr, $wd, $text ) = split /\s+/, $s, 3;
            }
            else {                       # примечание к книге (Desc) — якоря нет
                ( $tr, $text ) = split /\s+/, $s, 2;
            }

            my $mine = note_matches( $tr, $t );
            debug("[$id $ch:$vs / $mine / $tr]");
            next if !$mine;

            if ( $word eq 'ANY' || $word eq ( $wd // q{} ) ) {
                debug( "\tWD [" . ( $wd // q{} ) . "] $tr\t$text" );
                $rnote->{$id}->{$ch}->{$vs}->{$wd} = $text;
            }
            else {
                debug( sprintf 'WD: %s // %s', $wd // q{}, $word );
            }
        }
    }
    return;
}

# Алгебра изданий: подходит ли примечание, помеченное набором $tr, изданию $t.
# Правила разбиты на группы, но проверяются строго по порядку — первая
# группа, вернувшая решение, его и определяет. Неизвестное сочетание — ошибка
# сборки: молча потерять примечание хуже, чем упасть.
sub note_matches {
    my ( $tr, $t ) = @_;

    foreach my $rule ( \&note_excluded, \&note_rbs66_first, \&note_own, \&note_modern, \&note_foreign, \&note_rest ) {
        my $verdict = $rule->( $tr, $t );
        return $verdict if defined $verdict;
    }
    die "ERROR\nTR: $tr / $t\n";
}

# Наборы, которые нашему изданию не подходят ни при каких условиях.
sub note_excluded {
    my ( $tr, $t ) = @_;

    return 0 if $tr eq 'SYNOT' || $tr eq 'SKIP';
    return 0 if $tr eq 'AL-' . $t;
    return 0 if $tr eq 'BL'    && $tr ne $t;
    return 0 if $tr eq 'RBS77' && $t eq 'RBS66';
    return 0 if $tr eq 'RBS66' && $t eq 'RBS77';
    return;
}

# У РБО-66 своя очередь разбора: часть наборов отсекается раньше общих правил.
sub note_rbs66_first {
    my ( $tr, $t ) = @_;

    return   if $t ne 'RBS66';
    return 0 if $tr =~ /\A(?:OR|AL-(?:RBSPR|PR|RBS))\z/;
    return 0 if $tr eq 'PR' || $tr eq 'AL-RBS66';
    return 1 if $tr =~ /\A(?:PR|AL-(?:BL|OR|RBS77))\z/;
    return;
}

# Примечание «для всех» или ровно нашего издания.
sub note_own {
    my ( $tr, $t ) = @_;

    return 1 if $tr eq 'AL' || $tr eq $t;
    return;
}

# Современные издания: МП-2016 и РБО-77.
sub note_modern {
    my ( $tr, $t ) = @_;

    return   if $t ne 'MP2016' && $t ne 'RBS77';
    return 1 if $tr =~ /\A(?:AL|OR|$t)(?:[+].*|(?:-(?:PR|BL|RBS66|MP1976)))?\z/;
    return 0 if $tr =~ /\A(?:PR|BL|MP1976)/;
    return;
}

# Примечание чужой традиции: явное исключение нашего издания либо МП vs РБО.
sub note_foreign {
    my ( $tr, $t ) = @_;

    return 0 if $t eq 'RBS66' && $tr =~ /\A(?:MP|OR)/;
    return 0 if $tr                  =~ /-$t/;
    return 0 if $t                   =~ /MP/  && $tr =~ /\ARBS\d*(?:[+-].*)?\z/;
    return 0 if $t                   =~ /RBS/ && $tr =~ /\AMP(?:\d+|NT)?(?:-.*)?\z/;
    return;
}

# Составные наборы вида «AL-RBS», «MP+RBS77» — разбираются последними.
sub note_rest {
    my ( $tr, $t ) = @_;

    return 1 if $t eq 'MP2016' && ( $tr =~ /\A(?:(?:AL|MP|OR)-RBS(?:\d*|PR)?|MP(?:2016)?)\z/ || $tr =~ /\AMP[+]/ );
    return 1 if $t eq 'RBS77'  && $tr =~ /\A(?:(?:AL|RBS|OR)-MP\d*|RBS(?:77)?)\z/;

    return   if $t ne 'RBS66';
    return 1 if $tr =~ /\A(?:(?:AL|RBS|OR)-MP\d*|RBS(?:66)?)\z/;
    return 0 if $tr =~ /\A(?:MP\d*|RBS77)[+](?:RBS77|BL|MP\d*)\z/;
    return;
}

# Сборка одной книги: шапка, титулы, стихи с примечаниями и разметкой.
sub render_book {
    my (%arg) = @_;

    my $note = $arg{note};
    my $desc = extract_desc($note);
    my $res  = book_header( code => $arg{code}, type => $arg{type}, ucfg => $arg{ucfg}, desc => \$desc );

    $desc =~ s{<i>\s*}{\\em }g;
    $desc =~ s{</i>}{\\em*}g;
    if ($desc) {
        $desc = sprintf '\\f + \\fr 1.1 \\ft * %s \\f*', $desc;
        debug($desc);
    }

    my $st = { resn => [], pcb => $NOTHING_YET, pvb => $NOTHING_YET, p => 0, curv => {}, desc => $desc };
    foreach my $line ( read_lines( $arg{file} ) ) {
        if ( $line =~ /#(\d+):(\d+)#(\S.*\S)/ ) {
            add_verse( st => $st, book => \%arg, chapter => $1, verse => $2, text => $3 );
        }
        elsif ( $line =~ /#p#/ ) {
            $st->{p} = 1;
        }
    }

    # Примечание, для которого в тексте не нашлось адреса, молча пропадает из
    # выгрузки — поэтому о нём кричим в STDERR даже в тихом режиме.
    foreach my $pc ( sort keys %{$note} ) {
        if ( !keys %{ $note->{$pc} } ) { delete $note->{$pc}; next }
        foreach my $pv ( sort keys %{ $note->{$pc} } ) {
            warn "! rst$arg{type} $arg{sid} $pc:$pv — примечание не встало в текст\n";
        }
    }

    my $body = join q{}, map { cleanup_markup($_) } grep {defined} @{ $st->{resn} };
    write_file( $arg{path}, $res . $body );
    return;
}

# Примечание к книге целиком: заголовочное важнее обычного.
sub extract_desc {
    my ($note) = @_;

    return q{} if !exists $note->{Desc};
    my $desc = $note->{Desc}->{Header}->{ANY} // $note->{Desc}->{Note}->{ANY} // q{};
    delete $note->{Desc};
    return $desc;
}

# \id, \ide, \rem и титульные маркеры книги. Дата сборки в \id намеренно не
# проставляется: она делала выгрузку недетерминированной (менялась от mtime
# исходника), а стандарт USFM держит её необязательным свободным текстом.
sub book_header {
    my (%arg) = @_;
    my ( $code, $type, $ucfg, $desc ) = @arg{qw(code type ucfg desc)};

    # Адрес книги на сайте: состав без второканонических книг живёт в /rst/,
    # составы с ними — в /rst-dc/; книга адресуется USFM-кодом.
    my $edition = $type eq '66' ? 'rst' : 'rst-dc';
    my $res = sprintf "\\id %s, only.bible\n\\ide UTF-8\n\\rem https://only.bible/%s/%s/\n", $code, $edition, lc $code;

    my $titles = ref $ucfg->{T} eq ref [] ? $ucfg->{T} : [ $ucfg->{T} ];
    foreach my $s ( @{$titles} ) {
        if ( $s =~ /[*]/ ) {    # '*' в титуле — место для примечания к книге
            ${$desc} = sprintf '\\f + \\fr 1.1 \\ft * %s \\f*', ${$desc};
            $s =~ s/[*]/${$desc}/;
        }
        $s =~ s/\s+/ /g;
        $s =~ s/\Amt1/mt/g;
        $res .= "\n\\$s";
    }
    return $res . "\n\n";
}

# Один стих: чистка разметки, слова Христа, примечания, вывод в главу.
sub add_verse {
    my (%arg) = @_;
    my ( $st, $book, $pc, $pv, $v ) = @arg{qw(st book chapter verse text)};

    $st->{curv}->{$pc}->{$pv}++;
    $v = clean_verse($v);
    $v = apply_redletter(
        text    => $v,
        esv     => $book->{esv},
        chapter => $pc,
        verse   => $pv,
        seen    => $st->{curv}->{$pc}->{$pv},
    );

    if ( $st->{pcb} != $pc ) {
        start_chapter( st => $st, id => $book->{id}, chapter => $pc );
    }

    # Структурные сноски состава: якоря нет, pos start — в начало стиха,
    # иначе в конец; ссылка \x — только если в конфиге заданы цели.
    if ( my $ex = $book->{extra}->{$pc}->{$pv} ) {
        my ( $pre, $post ) = ( q{}, q{} );
        foreach my $note ( @{ extra_list($ex) } ) {
            my $text = structural_note( $pc, $pv, $note );
            if   ( ( $note->{pos} // q{} ) eq 'start' ) { $pre  .= "$text " }
            else                                        { $post .= $text }
        }
        $v = $pre . $v . $post;
    }
    if ( my $n = $book->{note}->{$pc}->{$pv} ) {
        $v = apply_notes(
            text    => $v,
            notes   => $n,
            note    => $book->{note},
            chapter => $pc,
            verse   => $pv,
            type    => $book->{type},
        );
    }

    if ( !$pv ) { $pv = q{} }
    my $resn = $st->{resn};
    if ( !$pc ) {    # вступление книги
        if ( $book->{id} == $ESTHER_ID ) { $resn->[0] .= "\\ib\n" }
        $resn->[0] .= "\\ip $v\n";
    }

    # pvb пуст после вступительного блока (стих 0) — приводим к числу, иначе
    # сравнение шумит предупреждением на каждой такой книге
    elsif ( $pv && $pv != ( $st->{pvb} || 0 ) ) {
        if ( $st->{p} ) { $resn->[$pc] .= '\p ' }
        $resn->[$pc]
            .= verse_marker( $pv, $book->{alt}->{$pc}->{$pv} ) . ( $st->{desc} ? " $st->{desc}" : q{} ) . " $v\n";
        $st->{desc} = q{};
    }
    else {    # продолжение того же стиха
        $resn->[$pc] .= "\\m $v\n";
    }

    $st->{pvb} = $pv;
    $st->{p}   = 0;
    return;
}

# \v с учётом альтернативной нумерации: \va — печатный номер, \v — 66-й.
sub verse_marker {
    my ( $pv, $real ) = @_;

    return "\\v $pv"       if !defined $real;
    return "\\va $pv\\va*" if $real eq q{*};
    return "\\v $real \\va $pv\\va*";
}

sub start_chapter {
    my (%arg) = @_;
    my ( $st, $id, $pc ) = @arg{qw(st id chapter)};

    my $resn = $st->{resn};
    if ( $pc == 1 && $resn->[0] && ( $id == $ESTHER_ID || $id == $SIRACH_ID ) ) {
        $resn->[$pc] .= "\\ie\n";
    }
    if ($pc) { $resn->[$pc] .= "\\c $pc\n" }

    if ( !$pc && $id == $SIRACH_ID ) {
        $resn->[0] .= "\\ib\n\\is Предисловие\n";    # тег \s не работает
    }
    elsif ($pc) {
        $resn->[$pc] .= '\p ';
    }

    $st->{pcb} = $pc;
    $st->{pvb} = $NOTHING_YET;
    return;
}

# Разметка исходника (.dat) -> разметка USFM.
sub clean_verse {
    my ($text) = @_;

    $text =~ s{<i>(.*?)</i>}{\\add-$1\\add*}g;
    $text =~ s/(&mdash;)\z/$1 /g;
    $text =~ s/&mdash;/—/g;
    $text =~ s/&hellip;/…/g;
    $text =~ s/&nbsp;/ /g;

    my $wide = decode_utf8($text);
    $wide =~ s/&[#]769;/chr $ACUTE/eg;
    $text = encode_utf8($wide);

    if ( $text =~ /&/ ) {    # неизвестная сущность — молча пропускать нельзя
        $text =~ s/&/>>> & <<</g;
        die " $text ";
    }
    return $text;
}

# Слова Христа: redletter.yaml задаёт главы, стихи и фрагменты внутри стиха.
sub apply_redletter {
    my (%arg) = @_;
    my ( $v, $esvt, $pc, $pv, $seen ) = @arg{qw(text esv chapter verse seen)};

    return $v if !$esvt;

    foreach my $k ( sort keys %{$esvt} ) {
        my ( $chap, $vers, $evers, $cnt ) = ();
        if ( $k =~ m{\A(\d+)\z} ) {
            $chap = $1;
        }
        elsif ( $k =~ m{\A(\d+):(\d+(?:/\d+)?)\z} ) {
            ( $chap, $vers ) = ( $1, $2 );
        }
        elsif ( $k =~ m{\A(\d+):(\d+)-(\d+)\z} ) {
            ( $chap, $vers, $evers ) = ( $1, $2, $3 );
        }
        next if !defined $chap || $chap != $pc;

        my $rules = ref $esvt->{$k} eq ref [] ? $esvt->{$k} : [ $esvt->{$k} ];
        foreach my $e ( @{$rules} ) {
            my ( $start, $end ) = split /\s+/, $e, 2;
            if ( defined $vers && $vers =~ m{(\d+)/(\d+)} ) {
                ( $vers, $cnt ) = ( $1, $2 );
            }
            else {
                $cnt = 0;
            }

            if ( !defined $vers || !length $vers ) {    # вся глава
                $v = sprintf '\\wj %s\\wj*', plus($v);
                next;
            }
            $evers ||= $vers;
            $v = redletter_verse(
                text  => $v,
                from  => $vers,
                to    => $evers,
                verse => $pv,
                start => $start,
                end   => $end,
                cnt   => $cnt,
                seen  => $seen,
            );
        }
    }
    return $v;
}

sub redletter_verse {
    my (%arg) = @_;
    my ( $v, $from, $to, $pv, $start, $end, $cnt, $seen ) = @arg{qw(text from to verse start end cnt seen)};

    foreach my $vrs ( $from .. $to ) {
        next if $vrs ne $pv;
        next if $cnt && $cnt != $seen;    # нужное по счёту вхождение стиха

        $v = $start eq 'full' ? sprintf '\\wj %s\\wj*', plus($v) : repl_woc( $v, $start, $end );
    }
    return $v;
}

# Запись extra к стиху — одна сноска или список сносок.
sub extra_list {
    my ($ex) = @_;

    return ref $ex eq ref [] ? $ex : [$ex];
}

# Сноска о переезде текста между составами; \x — ссылки на книги-получатели.
sub structural_note {
    my ( $pc, $pv, $ex ) = @_;

    my $note = sprintf '\\f + \\fr %d.%d \\ft %s \\f*', $pc, $pv, $ex->{text};
    if ( $ex->{xt} && @{ $ex->{xt} } ) {
        $note .= sprintf '\\x - \\xo %d.%d %s\\x*', $pc, $pv,
            join q{ }, map { sprintf '\\xt %s\\xt*', normalize_target($_) } @{ $ex->{xt} };
    }
    return $note;
}

# Код книги в ссылке пишем в верхнем регистре, как его пишет сам USFM: проверка
# цели регистронезависима, и без нормализации строчный код из конфига уехал бы
# в выгрузку как есть.
sub normalize_target {
    my ($target) = @_;

    my ( $code, $rest ) = split /\s+/, $target, 2;
    return defined $rest ? uc($code) . " $rest" : uc $code;
}

# Врезка примечаний печатного издания в текст стиха по якорному слову.
sub apply_notes {
    my (%arg) = @_;
    my ( $v, $n, $note, $pc, $pv ) = @arg{qw(text notes note chapter verse)};

    my $nv = $v;
    foreach my $ns ( keys %{$n} ) {
        my $rs = $ns;
        my $repl
            = $pc && $pv
            ? sprintf '\\f + \\fr %d.%d \\ft %s \\f*', $pc, $pv, $n->{$ns}
            : sprintf '\\f + \\fr %d \\ft %s \\f*', $pc, $n->{$ns};
        $repl =~ s/(Пс\s81.*\d)[.]/\\fv $1\\fv*/;
        $rs   =~ s/\[1\]\z//;

        if ( $rs =~ /[*]BEFORE[*](.*)/ ) {    # сноска ставится перед якорем
            my $pat = $1;
            $nv =~ /$pat/ or die "ERROR\n NOT FOUND $pat in $nv";
            $nv =~ s/($pat)/$repl . $1/e;
        }
        elsif ( $rs =~ /(.*)\[(\d+)\]/ ) {    # якорь по счёту вхождения
            my ( $pat, $count ) = ( $1, $2 );
            $nv =~ s/($pat)/--$count == 0 ? $1 . $repl : $1/ge;
        }
        else {
            $nv = insert_note( $nv, $rs, $repl, $arg{type} );
        }

        delete $n->{$ns};
        if ( !keys %{$n} )             { delete $note->{$pc}->{$pv} }
        if ( !keys %{ $note->{$pc} } ) { delete $note->{$pc} }
    }
    debug( sprintf "replace for\n\t%s\nnew line:\n\t%s", $v, $nv );
    return $nv;
}

# Якорь ищем в символах, а не в байтах: иначе точки-кванторы режут UTF-8.
sub insert_note {
    my ( $text, $anchor, $repl, $type ) = @_;

    my ( $wide, $pat, $note ) = map { decode_utf8($_) } $text, $anchor, $repl;
    $wide =~ /$pat/ or die "ERROR [$type]\n NOT FOUND $anchor in $text";
    $wide =~ s/($pat)/$1 . $note/e;
    return encode_utf8($wide);
}

# Финальная чистка разметки главы: порядок сносок, схлопывание \p, слова Христа.
sub cleanup_markup {
    my ($text) = @_;

    $text =~ s{([\\]f .*?[\\]f[*])([\\]add[*])}{$2$1}g;
    $text =~ s{(?:[\\]p\s+)+[\\](pi|ip)}{\\$1 }g;
    $text =~ s{(?:[\\]p\s+)+}{\\p }g;
    $text =~ s{[\\]p\s+([\\]m)}{$1}gsm;
    $text =~ s{([\\]wj )(.+?)([\\]wj[*])}{$1 . wj($2) . $3}eg;
    $text =~ s{([\\](?:wj|[+]?add))-}{$1 }g;
    $text =~ s{[\\]add[*](\s+)[\\]add\s+}{$1}g;
    $text =~ s/  +/ /g;
    return $text;
}

# Перенос собранного из usfm2/ в usfm/: только изменившиеся файлы. Возвращает
# имена тех, что реально легли на диск, — из них складывается сводка прогона.
sub sync_output {
    my ( $out, $out2 ) = @_;

    my @built = grep { -f "$out2/$_" } read_dir($out2);
    my %built = map  { $_ => 1 } @built;

    my @touched;
    foreach my $fn (@built) {
        my $new = "$out2/$fn";
        my $cur = "$out/$fn";

        # Нового состава в usfm/ ещё нет — сравнивать не с чем, просто кладём.
        if ( !-e $cur ) {
            push @touched, $fn;
            rename $new, $cur or die "rename $new: $OS_ERROR\n";
            next;
        }

        # Сравниваем файлы целиком, включая первую строку: \id детерминирован
        # и зависит от conf/usfm-codes.yaml, его правка обязана доехать до
        # выгрузки.
        if ( md5_hex( read_file($cur) ) eq md5_hex( read_file($new) ) ) {
            unlink $new or die "unlink $new: $OS_ERROR\n";
            next;
        }
        push @touched, $fn;
        rename $new, $cur or die "rename $new: $OS_ERROR\n";
    }

    my @sorted  = sort @touched;
    my @removed = remove_stale( $out, \%built );
    return { touched => \@sorted, removed => \@removed };
}

# Книга, исчезнувшая из parsed (удалена или переименована при смене состава),
# оставила бы в выгрузке файл-призрак: по формату он валиден, но составу уже не
# соответствует, и следующий потребитель прочитает лишнюю книгу. Удаляем только
# то, что генерируем сами (*.usfm), — чужие файлы в каталоге не наши.
sub remove_stale {
    my ( $out, $built ) = @_;

    my @removed;
    foreach my $fn ( read_dir($out) ) {
        next if $fn !~ /[.]usfm\z/;
        next if $built->{$fn};
        unlink "$out/$fn" or die "unlink $out/$fn: $OS_ERROR\n";
        push @removed, $fn;
    }
    return @removed;
}

# Итог прогона по составу: сколько книг собрано и что легло на диск.
sub report_edition {
    my ( $type, $books, $result ) = @_;

    my @parts;
    push @parts, describe_files( 'изменено', $result->{touched} );
    push @parts, describe_files( 'удалено',  $result->{removed} );
    @parts = grep {length} @parts;
    if ( !@parts ) { @parts = ('изменений нет') }

    say sprintf 'rst%s: книг %d, %s', $type, $books, join '; ', @parts;
    return;
}

sub describe_files {
    my ( $label, $files ) = @_;

    return q{} if !@{$files};
    my @shown = @{$files};
    my $tail  = @shown > $REPORT_LIMIT ? sprintf ' и ещё %d', @shown - $REPORT_LIMIT : q{};
    if ($tail) { @shown = @shown[ 0 .. $REPORT_LIMIT - 1 ] }
    return sprintf '%s %d: %s%s', $label, scalar @{$files}, ( join ', ', @shown ), $tail;
}

# Разметка слов Христа внутри стиха: начало и конец фрагмента заданы правилом.
sub repl_woc {
    my ( $text, $start, $end ) = @_;

    # правило вида «colon» без второй части — конца у фрагмента нет
    return defined $end && $end =~ /\S/ ? woc_ranged( $text, $start, $end ) : woc_open( $text, $start );
}

# Правило без конца: до конца стиха от двоеточия, предложение или цитата.
sub woc_open {
    my ( $text, $start ) = @_;

    if ( $start =~ /(colon)(\d*)/ ) {
        my ( $char, $num ) = ( $CHAR_RE{$1}, $2 || 0 );
        if ($num) {
            my @data = split /($char)/, $text;
            $data[ $num * 2 ] = sprintf '\\wj %s\\wj*', plus( $data[ $num * 2 ] );
            return join q{}, @data;
        }
        $text =~ s{($char\s*)(.*)}{sprintf '%s\\wj %s\\wj*', $1, plus($2)}eg;
    }
    elsif ( $start =~ /sentence(\d*)/ ) {
        my $num  = $1 || 1;
        my @data = split /([.!?])/, $text;
        $data[ ( $num - 1 ) * 2 ]     = sprintf '\\wj %s', plus( $data[ ( $num - 1 ) * 2 ] );
        $data[ ( $num - 1 ) * 2 + 1 ] = sprintf '%s\\wj*', plus( $data[ ( $num - 1 ) * 2 + 1 ] );
        return join q{}, @data;
    }
    elsif ( $start =~ /quote\d*/ ) {
        $text =~ s{(«.+?»)}{sprintf '\\wj %s\\wj*', plus($1)}eg;
    }
    return $text;
}

# Правило с концом: диапазон слов либо от двоеточия до знака препинания.
sub woc_ranged {
    my ( $text, $start, $end ) = @_;

    if ( $start =~ /\A\d+\z/ && $end =~ /\A\d+\z/ ) {
        return woc_words( $text, $start, $end );
    }
    my ( $name, $num ) = $start =~ /\A(colon)(\d*)\z/;
    return $text if !defined $name;

    my $char = $CHAR_RE{$name};
    return $num
        ? woc_nth_colon( $text, $char, $num, $end )
        : woc_each_colon( $text, $char, $end );
}

# От N-го двоеточия до ближайшего знака конца; суффикс -1 оставляет знак вне \wj.
sub woc_nth_colon {
    my ( $text, $char, $num, $end ) = @_;

    my ( $name, $back ) = $end =~ /\A(exclamation|dot|question|comma)(-1)?\z/;
    return $text if !defined $name;
    my $stop = $CHAR_RE{$name};

    my @data = split /($char)/, $text;
    $data[ $num * 2 ] =~ s{
        (.*?)
        ($stop)
    }{' \\wj ' . $1 . plus($back ? q{} : $2) . '\\wj*' . ($back ? $2 : q{})}ex;
    return join q{}, @data;
}

# То же для каждого двоеточия в стихе.
sub woc_each_colon {
    my ( $text, $char, $end ) = @_;

    my ($name) = $end =~ /\A(exclamation|dot|question|comma)(?:\d*)(?:-1)?\z/;
    return $text if !defined $name;
    my $stop = $CHAR_RE{$name};

    $text =~ s{
        ($char\s*)(.*?)($stop)
    }{sprintf '%s \\wj %s\\wj*', $1, plus($2 . $3)}egx;
    return $text;
}

# Диапазон слов стиха: с $start-го по $end-е слово.
sub woc_words {
    my ( $text, $start, $end ) = @_;

    my $head = join q{}, map {'\\S+\\s+'} ( 1 .. $start - 1 );
    my $body = $end > $start ? ( join '\\s+', map {'\\S+'} ( 1 .. $end - $start + 1 ) ) : q{.+};
    $head = qr/$head/;
    $body = qr/$body/;
    $text =~ s{
        ($head)($body)
    }{sprintf '%s \\wj-%s\\wj*', $1, plus($2)}ex;
    return $text;
}

sub plus {
    my ($text) = @_;
    return $text;
}

# Внутри \wj вложенные маркеры оформляются иначе: \add -> \+add, сноска
# разрывает участок слов Христа.
sub wj {
    my ($text) = @_;

    $text =~ s{([\\])(add)}{${1}+$2}g;
    $text =~ s{([\\]f .*?[\\]f[*])}{\\wj*${1}\\wj }g;
    return $text;
}

# Загрузка YAML вместо Config::General. YAML::PP отдаёт декодированные строки,
# а генератор работает с байтами (print без слоёв) — кодируем рекурсивно.
sub load_conf {
    my ($path) = @_;
    my $data = YAML::PP->new->load_file($path);
    return deep_encode($data);
}

sub deep_encode {
    my ($node) = @_;
    if ( ref $node eq ref {} ) {
        foreach my $k ( keys %{$node} ) {
            $node->{$k} = deep_encode( $node->{$k} );
        }
    }
    elsif ( ref $node eq ref [] ) {
        foreach my $item ( @{$node} ) {
            $item = deep_encode($item);
        }
    }
    elsif ( defined $node && !ref $node ) {
        $node = encode_utf8($node);
    }
    return $node;
}

# conf/paper-notes.yaml структурирован: for (издание/набор; список = «+»),
# except («X-Y» источника), anchor, text; skip — «в этих изданиях сноски нет».
# Старый код разбирал строки «издание слово текст» — нормализуем структуру в
# прежнюю внутреннюю форму, не трогая логику сопоставления изданий.
sub paper_expr {
    my ($e)  = @_;
    my $base = ref $e->{for} eq ref [] ? join q{+}, @{ $e->{for} } : $e->{for};
    return $e->{except} ? "$base-$e->{except}" : $base;
}

sub load_paper_notes {
    my ($path) = @_;

    my $src = load_conf($path);
    my $out = {};
    foreach my $slug ( keys %{$src} ) {
        my $b = $src->{$slug} or next;
        foreach my $sec (qw(desc header)) {
            my $key = $sec eq 'desc' ? 'Note' : 'Header';
            foreach my $e ( @{ $b->{$sec} || [] } ) {
                my $line
                    = exists $e->{skip}
                    ? join q{ }, 'SKIP', paper_expr( { %{$e}, for => $e->{skip} } )
                    : join q{ }, paper_expr($e), $e->{text};
                push @{ $out->{$slug}->{Desc}->{$key} }, $line;
            }
        }
        my $ch = $b->{chapters} || {};
        foreach my $c ( keys %{$ch} ) {
            foreach my $v ( keys %{ $ch->{$c} } ) {
                push @{ $out->{$slug}->{$c}->{$v} }, map { paper_note_line($_) } @{ $ch->{$c}->{$v} };
            }
        }
    }
    return $out;
}

sub paper_note_line {
    my ($e) = @_;

    return join q{ }, 'SKIP', paper_expr( { %{$e}, for => $e->{skip} } ) . ( $e->{anchor} ? "/$e->{anchor}" : q{} )
        if exists $e->{skip};
    return join q{ }, paper_expr($e), ( $e->{anchor} // q{} ), ( $e->{text} // q{} );
}

sub debug {
    my (@msg) = @_;

    return if !$VERBOSE;
    say @msg;
    return;
}

sub read_dir {
    my ($path) = @_;

    opendir my $dh, $path or die "$path: $OS_ERROR\n";
    my @entries = sort grep { -f "$path/$_" } readdir $dh;
    closedir $dh;
    return @entries;
}

sub read_lines {
    my ($path) = @_;

    open my $fh, '<', $path or die "$path: $OS_ERROR\n";
    my @lines = <$fh>;
    close $fh;
    return @lines;
}

sub read_file {
    my ($path) = @_;

    open my $fh, '<', $path or die "$path: $OS_ERROR\n";
    local $INPUT_RECORD_SEPARATOR = undef;
    my $data = <$fh>;
    close $fh;
    return $data // q{};
}

sub write_file {
    my ( $path, $data ) = @_;

    open my $fh, '>', $path or die "$path: $OS_ERROR\n";
    print {$fh} $data or die "$path: $OS_ERROR\n";
    close $fh;
    return;
}
