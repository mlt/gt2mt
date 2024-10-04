/*
Copyright Mikhail Titov 2024.
Distributed under the Boost Software License, Version 1.0.
(See accompanying file LICENSE or copy at https://www.boost.org/LICENSE_1_0.txt)
*/

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdlib.h>
#include <locale.h>

/* Size in letters to fit the longest message (in UTF-16) */
#define BUFFER_SIZE 4096
#define MULTIPLIER 2

char* GetString(DWORD msgid) {
	static wchar_t buffer_wide[BUFFER_SIZE];
	static char buffer[BUFFER_SIZE * MULTIPLIER];
	static int locale_set = 0;
	static LANGID lang;
	static char* buffer_ptr = buffer;

	char* result = buffer_ptr;

	if (!locale_set) {
		locale_set = 1;
		lang = GetSystemDefaultLangID();
		/* Somehow this does not affect automagic selection with a fallback */
		/*
		LCID loc = GetSystemDefaultLCID();
		SetThreadLocale(loc);
		*/
	}

	DWORD chars = FormatMessageW(FORMAT_MESSAGE_IGNORE_INSERTS | FORMAT_MESSAGE_FROM_HMODULE,
		NULL, msgid, lang, buffer_wide, BUFFER_SIZE, NULL);
	if (!chars) {
		lang = LANG_NEUTRAL;
		FormatMessageW(FORMAT_MESSAGE_IGNORE_INSERTS | FORMAT_MESSAGE_FROM_HMODULE,
			NULL, msgid, lang, buffer_wide, BUFFER_SIZE, NULL);
	}

	size_t conv;
	wcstombs_s(&conv, result, BUFFER_SIZE, buffer_wide, BUFFER_SIZE);
	/* strip carriage returns */
	for (int i = 0, j = 0; i < conv; ++i)
		if (result[i] != '\r')
			result[j++] = result[i];

	/* allow for multiple calls within a single callee function */
	buffer_ptr += conv;
	if (buffer_ptr - buffer > BUFFER_SIZE)
		buffer_ptr = buffer;

	/* We don't need that if every msgstr ends with %0 */
	/* size_t len = strlen(buffer); */
	/* if (len > 2) /\* remove trailing \r\n inserted by FormatMessage *\/ */
	/* 	buffer[len - 2] = 0; */

	return result;
};
