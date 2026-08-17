#!/usr/bin/perl
# Сборка parsed81 из parsed78: разделение книг по conf/split-books.yaml.
# Формат .dat: строки `#глава:стих#текст` (нумерация печатная) и `#p#` (абзац).
# Выход: parsed81/*.dat и parsed81/description.yaml (главы пересчитываются по
# фактическому содержимому выходных файлов). В конце — verify: нормализованный
# текст разделённых книг обязан совпасть с книгой-источником.

use strict;
use warnings;
use v5.10;
use FindBin qw($Bin);
use YAML::PP;
use Encode qw(encode_utf8);
use Carp;
use English qw(-no_match_vars);
use Readonly;

# Разделитель склейки стихов при сверке: нулевой байт в тексте невозможен.
Readonly::Scalar my $VERSE_SEP => chr 0;

run();

sub run {
    my $cfg   = YAML::PP->new->load_file("$Bin/../conf/split-books.yaml");
    my $codes = YAML::PP->new->load_file("$Bin/../../conf/usfm-codes.yaml")->{codes};

    my $src_dir = "$Bin/../../" . $cfg->{source_dir};
    my $dst_dir = "$Bin/..";
    my $split   = $cfg->{splits}->[0];

    clean_target($dst_dir);

    my @src_lines = read_lines("$src_dir/$split->{from}");
    my ( $extracted, $cut ) = extract_books( $split, \@src_lines );
    my $rest    = renumber_rest( $split, \@src_lines, $cut );
    my $renamed = layout_files(
        {   cfg       => $cfg,
            split     => $split,
            src_dir   => $src_dir,
            dst_dir   => $dst_dir,
            rest      => $rest,
            extracted => $extracted,
        }
    );

    my $books = build_description( $split, $src_dir, $dst_dir, $codes, $renamed );
    write_description( "$dst_dir/description.yaml", $books );
    printf "parsed81: %d книг\n", scalar @{$books};

    verify_split( $split, $src_dir, $dst_dir, $renamed );
    return;
}

# Очистить каталог назначения от прошлых прогонов.
sub clean_target {
    my ($dst_dir) = @_;
    unlink glob "$dst_dir/*.dat";
    unlink "$dst_dir/description.yaml";
    return;
}

# Вырезать новые книги из книги-источника. Возвращает (файл -> строки) и
# множество вырезанных «глава:стих» для последующего удаления из остатка.
sub extract_books {
    my ( $split, $src_lines ) = @_;
    my ( %extracted, %cut );

    foreach my $ex ( @{ $split->{extract} } ) {
        my $r = $ex->{range};
        my ( $cf, $ct ) = ( $r->{chapter_from}, $r->{chapter_to} );
        my ( $vf, $vt ) = ( $r->{verse_from}, $r->{verse_to} );
        my $new_ch = $ex->{renumber}->{chapter};
        my $fv     = $ex->{renumber}->{first_verse};

        my @out;
        foreach my $line ( @{$src_lines} ) {
            if ( $line eq '#p#' ) {

                # #p# только внутри уже начатого блока
                if (@out) {
                    push @out, $line;
                }
                next;
            }
            my ( $c, $v, $tx ) = $line =~ /^#(\d+):(\d+)#(.*)$/s
                or croak "bad line: $line";
            next if $c < $cf || $c > $ct;
            next if defined $vf && ( $v < $vf || $v > $vt );
            $cut{"$c:$v"} = 1;
            my $nv = defined $fv ? $fv + ( $v - $vf ) : $v;
            push @out, sprintf '#%d:%d#%s', $new_ch, $nv, $tx;
        }
        while ( @out && $out[-1] eq '#p#' ) {
            pop @out;
        }
        if ( $ex->{strip_wrapping_brackets} ) {
            strip_outer_brackets( \@out );
        }
        $extracted{ $ex->{file} } = \@out;
    }
    return ( \%extracted, \%cut );
}

# Остаток книги-источника: без вырезанного, с перенумерацией хвоста.
sub renumber_rest {
    my ( $split, $src_lines, $cut ) = @_;
    my @keep;

    foreach my $line ( @{$src_lines} ) {
        if ( $line eq '#p#' ) {
            push @keep, $line;
            next;
        }
        my ( $c, $v, $tx ) = $line =~ /^#(\d+):(\d+)#(.*)$/s;
        next if $cut->{"$c:$v"};
        foreach my $rn ( @{ $split->{keep}->{renumber} || [] } ) {
            if ( $c == $rn->{chapter} && $v >= $rn->{verse_from} && $v <= $rn->{verse_to} ) {
                $v    = $rn->{to_first_verse} + ( $v - $rn->{verse_from} );
                $line = sprintf '#%d:%d#%s', $c, $v, $tx;
                last;
            }
        }
        push @keep, $line;
    }

    # схлопнуть двойные #p#, оставшиеся от вырезанных блоков
    my @out;
    foreach my $line (@keep) {
        next if $line eq '#p#' && ( !@out || $out[-1] eq '#p#' );
        push @out, $line;
    }
    while ( @out && $out[-1] eq '#p#' ) {
        pop @out;
    }
    return \@out;
}

# Разложить файлы со сдвигом номеров; вернуть карту «слаг -> новое имя».
sub layout_files {
    my ($arg) = @_;
    my ( $cfg, $split, $src_dir, $dst_dir, $rest, $extracted )
        = @{$arg}{qw/cfg split src_dir dst_dir rest extracted/};
    my $shift = scalar @{ $split->{extract} };
    my %renamed;

    foreach my $path ( sort glob "$src_dir/*.dat" ) {
        my ($name) = $path =~ m{([^/]+)$}sm;
        my ( $num, $slug ) = $name =~ /^(\d+)-(.+)[.]dat$/sm;
        my $new_num  = $num > $cfg->{insert_after} ? $num + $shift : $num + 0;
        my $new_name = sprintf '%02d-%s.dat', $new_num, $slug;
        $renamed{$slug} = $new_name;
        write_lines( "$dst_dir/$new_name", $name eq $split->{from} ? $rest : [ read_lines($path) ] );
    }
    foreach my $ex ( @{ $split->{extract} } ) {
        write_lines( "$dst_dir/$ex->{file}", $extracted->{ $ex->{file} } );
    }
    return \%renamed;
}

# Описание книг: записи источника со сдвинутыми именами + новые книги.
sub build_description {
    my ( $split, $src_dir, $dst_dir, $codes, $renamed ) = @_;
    my $src_desc = YAML::PP->new->load_file("$src_dir/description.yaml")->{books};
    my @books;

    foreach my $b ( @{$src_desc} ) {
        my $slug = slug_of( $b->{file} );
        push @books, { %{$b}, file => $renamed->{$slug} };
        next if $b->{file} ne $split->{from};
        push @books,
            map { { file => $_->{file}, eng => $_->{eng}, rus => $_->{rus}, testament => $_->{testament}, } }
            @{ $split->{extract} };
    }

    my $id = 0;
    foreach my $b (@books) {
        my $slug = slug_of( $b->{file} );
        $b->{id}       = ++$id;
        $b->{usfm}     = $codes->{$slug} or croak "no usfm code for '$slug'";
        $b->{chapters} = count_chapters("$dst_dir/$b->{file}");
    }
    return \@books;
}

# Сверка: текст разделённых книг совпадает с книгой-источником.
sub verify_split {
    my ( $split, $src_dir, $dst_dir, $renamed ) = @_;

    my @src = normalized_verses("$src_dir/$split->{from}");
    my @dst;
    foreach my $file ( $renamed->{ slug_of( $split->{from} ) }, map { $_->{file} } @{ $split->{extract} } ) {
        push @dst, normalized_verses("$dst_dir/$file");
    }
    if ( ( join $VERSE_SEP, sort @src ) ne ( join $VERSE_SEP, sort @dst ) ) {
        croak 'VERIFY FAILED: текст разделённых книг не совпадает с источником';
    }

    # Совпадение мультимножества текста не ловит смещение границы: стих может
    # уехать не в ту книгу или встать не на тот адрес. Поэтому сверяем каждую
    # вынесенную книгу с конфигом — по числу стихов и непрерывности нумерации,
    # а также баланс скобок во всех затронутых файлах.
    my $rest_file = $renamed->{ slug_of( $split->{from} ) };
    foreach my $file ( $rest_file, map { $_->{file} } @{ $split->{extract} } ) {
        verify_brackets("$dst_dir/$file");
        verify_numbering("$dst_dir/$file");
    }
    verify_expected( $src_dir, $dst_dir, $rest_file );

    say 'verify: OK — текст, нумерация, скобки и контракт совпали';
    return;
}

# Снять внешние скобки второканонической вставки.
#
# Вставка размечена НЕ одной парой на всю книгу: у s3y четыре блока
# (3:24; 3:25-45; 3:46-50; 3:51-90), у bel три, у sus один. Поэтому снимаем
# скобки глубины 1 — открывающую каждого блока и его закрывающую, — оставляя
# вложенные (обычные вставки перевода) нетронутыми. Баланс проверяется
# отдельно в verify_brackets.
sub strip_outer_brackets {
    my ($lines) = @_;
    my $depth = 0;

    foreach my $line ( @{$lines} ) {
        next if $line eq '#p#';
        my ( $head, $text ) = $line =~ /^(#\d+:\d+#)(.*)$/sm;
        my $out = q{};
        foreach my $ch ( split //sm, $text ) {
            if ( $ch eq '[' ) {
                $depth++;
                next if $depth == 1;    # внешняя открывающая — снимаем
            }
            elsif ( $ch eq ']' ) {
                $depth--;
                next if $depth == 0;    # внешняя закрывающая — снимаем
            }
            $out .= $ch;
        }
        $line = $head . $out;
    }
    return;
}

# Баланс скобок в файле: глубина не уходит в минус и в конце равна нулю.
sub verify_brackets {
    my ($path) = @_;
    my $depth = 0;

    foreach my $line ( read_lines($path) ) {
        next if $line eq '#p#';
        ( my $text = $line ) =~ s/^#\d+:\d+#//sm;
        foreach my $ch ( split //sm, $text ) {
            if    ( $ch eq '[' ) { $depth++ }
            elsif ( $ch eq ']' ) { $depth-- }
            if    ( $depth < 0 ) {
                croak "VERIFY FAILED: непарная ']' в $path";
            }
        }
    }
    if ( $depth != 0 ) {
        croak "VERIFY FAILED: незакрытая '[' в $path";
    }
    return;
}

# Адреса стихов файла в порядке следования: «глава:стих».
sub verse_refs {
    my ($path) = @_;
    my @refs;
    foreach my $line ( read_lines($path) ) {
        next if $line eq '#p#';
        if ( $line =~ /^#(\d+):(\d+)#/sm ) {
            push @refs, "$1:$2";
        }
    }
    return @refs;
}

# Нормализованные строки стихов файла: без маркеров, скобок и лишних пробелов.
# Обрамляющие скобки вынесенных книг сняты намеренно, поэтому в сверке скобки
# игнорируются целиком.
sub normalized_verses {
    my ($path) = @_;
    my @verses;
    foreach my $line ( read_lines($path) ) {
        next if $line eq '#p#';
        ( my $text = $line ) =~ s/^#\d+:\d+#//sm;
        push @verses, normalize_text($text);
    }
    return @verses;
}

# Остаток книги-источника: перенумерованный хвост стоит на заданных адресах,
# Сверка с независимым контрактом conf/expected-split.yaml.
#
# Ожидания не выводятся из split-books.yaml, а текст не фиксируется снимком:
# берём актуальные строки источника и сравниваем диапазон в диапазон с тем, что
# легло в выходные книги. Так ловится и смещение границы, и перенос стиха, при
# этом законная правка текста ничего не ломает.
sub verify_expected {
    my ( $src_dir, $dst_dir, $rest_file ) = @_;
    my $exp = YAML::PP->new->load_file("$Bin/../conf/expected-split.yaml");
    my @src = read_lines("$src_dir/$exp->{source_file}");

    my %taken;    # адреса источника, ушедшие в вынесенные книги
    foreach my $file ( sort keys %{ $exp->{extracted} } ) {
        my $r = $exp->{extracted}->{$file};
        my @want;
        foreach my $line (@src) {
            next if $line eq '#p#';
            my ( $c, $v, $text ) = $line =~ /^#(\d+):(\d+)#(.*)$/sm;
            next if $c != $r->{chapter};
            next if defined $r->{verse_from} && ( $v < $r->{verse_from} || $v > $r->{verse_to} );
            $taken{"$c:$v"} = 1;
            push @want, normalize_text($text);
        }
        my @got = normalized_verses("$dst_dir/$file");
        compare_verses( $file, \@want, \@got );
        check_starts_at_one( $file, "$dst_dir/$file", $r->{to_chapter} );
    }

    # остаток: всё, что не ушло, в исходном порядке и с перенумерацией контракта
    my @want_rest;
    foreach my $line (@src) {
        next if $line eq '#p#';
        my ( $c, $v, $text ) = $line =~ /^#(\d+):(\d+)#(.*)$/sm;
        next if $taken{"$c:$v"};
        push @want_rest, normalize_text($text);
    }
    my @got_rest = normalized_verses("$dst_dir/$rest_file");
    compare_verses( $rest_file, \@want_rest, \@got_rest );
    verify_rest_addresses( $exp, $src_dir, $dst_dir, $rest_file, \%taken );
    return;
}

# Адреса остатка: перенумерованный хвост стоит там, где велит контракт, а
# исходных номеров этого диапазона не осталось.
sub verify_rest_addresses {
    my ( $exp, $src_dir, $dst_dir, $rest_file, $taken ) = @_;
    my %have = map { $_ => 1 } verse_refs("$dst_dir/$rest_file");

    foreach my $rn ( @{ $exp->{rest_renumber} || [] } ) {
        foreach my $i ( 0 .. $rn->{verse_to} - $rn->{verse_from} ) {
            my $new = "$rn->{chapter}:" . ( $rn->{to_first_verse} + $i );
            if ( !$have{$new} ) {
                croak "VERIFY FAILED: в остатке нет стиха $new (контракт)";
            }
            my $old = "$rn->{chapter}:" . ( $rn->{verse_from} + $i );
            if ( $have{$old} ) {
                croak "VERIFY FAILED: в остатке остался исходный номер $old";
            }
        }
    }
    return;
}

# Сравнить последовательности нормализованных стихов.
sub compare_verses {
    my ( $file, $want, $got ) = @_;

    my $n_want = scalar @{$want};
    my $n_got  = scalar @{$got};
    if ( $n_want != $n_got ) {
        croak "VERIFY FAILED: $file — стихов $n_got, по контракту $n_want";
    }
    foreach my $i ( 0 .. $#{$want} ) {
        next if $want->[$i] eq $got->[$i];
        my $num = $i + 1;
        croak "VERIFY FAILED: $file — стих № $num не совпал с источником";
    }
    return;
}

# Вынесенная книга начинается с первого стиха заданной главы.
sub check_starts_at_one {
    my ( $file, $path, $chapter ) = @_;
    my @refs = verse_refs($path);

    if ( $refs[0] ne "$chapter:1" ) {
        croak "VERIFY FAILED: $file — первый стих $refs[0], ожидался $chapter:1";
    }
    return;
}

# Нормализация текста стиха: скобки и повторные пробелы отброшены.
sub normalize_text {
    my ($text) = @_;
    $text =~ s/[\[\]]//gsm;
    $text =~ s/\s+/ /gsm;
    return $text;
}

# Нумерация глав: внутри каждой главы номера идут непрерывно от 1 и не
# перескакивают. Инвариант структуры, из конфига не выводится: ловит и
# осиротевший стих, и пропуск в начале хвоста.
sub verify_numbering {
    my ($path) = @_;
    my %seen_max;

    foreach my $ref ( verse_refs($path) ) {
        my ( $c, $v ) = split /:/sm, $ref;
        my $prev = $seen_max{$c};
        if ( !defined $prev ) {
            if ( $v != 1 ) {
                croak "VERIFY FAILED: $path — глава $c начинается со стиха $v";
            }
        }
        elsif ( $v != $prev && $v != $prev + 1 ) {
            croak "VERIFY FAILED: $path — в главе $c за стихом $prev идёт $v";
        }
        $seen_max{$c} = $v;
    }
    return;
}

sub slug_of {
    my ($file) = @_;
    my ($slug) = $file =~ /^\d+-(.+)[.]dat$/sm;
    return $slug;
}

sub read_lines {
    my ($path) = @_;
    open my $fh, '<', $path or croak "$path: $OS_ERROR";
    my @lines = <$fh>;
    close $fh;
    chomp @lines;
    return @lines;
}

sub write_lines {
    my ( $path, $lines ) = @_;
    open my $fh, '>', $path or croak "$path: $OS_ERROR";
    print {$fh} join( "\n", @{$lines} ), "\n";
    close $fh;
    return;
}

# главы по факту содержимого; глава 0 (пролог) в счёт не входит
sub count_chapters {
    my ($path) = @_;
    my %ch;
    foreach my $line ( read_lines($path) ) {
        if ( $line =~ /^#(\d+):/ ) {
            $ch{$1} = 1;
        }
    }
    delete $ch{0};
    return scalar keys %ch;
}

sub write_description {
    my ( $path, $books ) = @_;
    my @out = ( '# Сгенерировано parsed81/scripts/split-books.pl — не редактировать руками.', 'books:', );
    foreach my $b ( @{$books} ) {
        push @out, sprintf '  - id: %d',        $b->{id};
        push @out, sprintf '    file: %s',      $b->{file};
        push @out, sprintf '    usfm: %s',      $b->{usfm};
        push @out, sprintf '    eng: %s',       encode_utf8( $b->{eng} );
        push @out, sprintf '    rus: %s',       encode_utf8( $b->{rus} );
        push @out, sprintf '    testament: %s', $b->{testament};
        push @out, sprintf '    chapters: %d',  $b->{chapters};
        if ( $b->{prologue} ) {
            push @out, '    prologue: true';
        }
    }
    open my $fh, '>', $path or croak "$path: $OS_ERROR";
    print {$fh} join( "\n", @out ), "\n";
    close $fh;
    return;
}
