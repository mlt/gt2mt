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
	static char locale_name[LOCALE_NAME_MAX_LENGTH * sizeof(WCHAR)];
	static _locale_t locale;
	static char* buffer_ptr = buffer;

	char* result = buffer_ptr;

	if (!locale_set) {
		locale_set = 1;
		GetSystemDefaultLocaleName((LPWSTR)locale_name, LOCALE_NAME_MAX_LENGTH);
		size_t len = wcsnlen_s((LPWSTR)locale_name, LOCALE_NAME_MAX_LENGTH);
		for (int i = 1; i <= len; ++i)
			locale_name[i] = locale_name[i * 2];
		locale = _create_locale(LC_ALL, locale_name);
		lang = GetSystemDefaultLangID();
	}

	DWORD chars = FormatMessageW(FORMAT_MESSAGE_IGNORE_INSERTS | FORMAT_MESSAGE_FROM_HMODULE,
	if (!chars)
		return NULL;
		NULL, msgid, lang, buffer_wide, BUFFER_SIZE, NULL);

	//setlocale(LC_ALL, locale_name); /* This does not cut it :( */
	size_t conv;
	errno_t err = _wcstombs_s_l(&conv, result, BUFFER_SIZE, buffer_wide, BUFFER_SIZE, locale);
	/* strip carriage returns */
	for (int i = 0, j = 0; i < conv; ++i)
		if (result[i] != '\r')
			result[j++] = result[i];

	/* allow for multiple calls within a single callee function */
	buffer_ptr += conv;
	if (buffer_ptr - buffer > BUFFER_SIZE)
		buffer_ptr = buffer;

	//_free_locale(locale);

	//wcstombs_s(&conv, buffer, BUFFER_SIZE, buffer_wide, BUFFER_SIZE);
	/* We don't need that if every msgstr ends with %0 */
	/* size_t len = strlen(buffer); */
	/* if (len > 2) /\* remove trailing \r\n inserted by FormatMessage *\/ */
	/* 	buffer[len - 2] = 0; */

	return result;
};
