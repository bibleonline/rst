# Russian Synodal Bible Translation

## About Sources (Об источнике данных)
Original sources files downloaded from [Logos Bible Software](https://www.logos.com/resources/LLS_BB_SBB_RUSBT/russian-synodal-bible-translation).

* Author:	Bible Society of Russia
* Published by:	Российское Библейское общество (1995)
* ISBN:	9785855243284
* Copyright: Public Domain
* Extended Copyright: Public Domain

## Файлы и каталоги

* source -- Оригинальные файлы (как есть)
* parsed -- Подготовленные файлы для дальнейшей работы
 * NN-bookname.dat -- подготовленный файл по каждой из книг библии
 * [description.conf](https://github.com/sopov/rst/blob/master/parsed/description.conf) -- Описание, построенное на данных из оригинальных файлов
* scripts -- Скрипты для обновления файлов
 * (syn.json)[https://github.com/sopov/rst/blob/master/scripts/syn.json] -- Список книг и глав
 * (00-update-sources.cgi)[https://github.com/sopov/rst/blob/master/scripts/00-update-sources.cgi] -- Инициализационный скрипт для исправления оригинальных файлов
 * (10-parse-sources.cgi)[https://github.com/sopov/rst/blob/master/scripts/10-parse-sources.cgi] -- конвертор оригинальных файлов в удобный для дальнейшей работы файлов
