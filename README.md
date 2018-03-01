# Russian Synodal Bible Translation

## About Sources (Об источнике данных)
Original sources files downloaded from [Logos Bible Software](https://www.logos.com/resources/LLS_BB_SBB_RUSBT/russian-synodal-bible-translation).

* Author:	Bible Society of Russia
* Published by:	Российское Библейское общество (1995)
* ISBN:	9785855243284 / 978-5-85524-328-4
* Copyright: Public Domain
* Extended Copyright: Public Domain

## Сравнение с печатными изданиями
Для разрешения вопросов в правильности набора текста производим сравнение с изданиями из 77 книг:

2002. РБО. ISBN 978-5-85524-150-1
2016. МП РПЦ, Изд 5, ISBN 978-5-88017-237-5

Издание 66 книг (протестантское издание), получается на базе издания 77 книг, путём удаления скобок. Для корректного удаления скобок и сравнения, была произведена вычитка текста по печатному изданию из 66 книг:
2016. РБО. ISBN 978-5-85524-071-9 (текст 1998 г.)

## Файлы и каталоги

* source -- Оригинальные файлы (как есть)
* issues -- вопросы по тексту
* parsed -- Подготовленные файлы для дальнейшей работы
* parsed66 -- Подготовленные файлы для дальнейшей работы протестантского издания
* usfm -- Библия в формате USFM
* redletter -- красные буквы (слова Христа)
 * NN-bookname.dat -- подготовленный файл по каждой из книг библии
 * [description.conf](https://github.com/sopov/rst/blob/master/parsed/description.conf) -- Описание, построенное на данных из оригинальных файлов
* scripts -- Скрипты для обновления файлов
 * [syn.json](https://github.com/sopov/rst/blob/master/scripts/syn.json) -- Список книг и глав
 * [00-update-sources.cgi](https://github.com/sopov/rst/blob/master/scripts/00-update-sources.cgi) -- Инициализационный скрипт для исправления оригинальных файлов
 * [10-parse-sources.cgi](https://github.com/sopov/rst/blob/master/scripts/10-parse-sources.cgi) -- конвертор оригинальных файлов в удобный формат для дальнейшей работы с файлами
 * [20-fix-parsed](https://github.com/sopov/rst/tree/master/scripts/20-fix-parsed) -- обновление распарсенных файлов для устранения ошибок в исходных файлах
