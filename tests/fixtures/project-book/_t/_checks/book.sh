#!/usr/bin/env bash
set -euo pipefail

report() {
	if [ "$1" = ok ]; then
		printf 'ok - %s\n' "$2"
	else
		printf 'not ok - %s\n' "$2"
	fi
}

if [[ "$EXTENSION_TEST_INPUT" == /* ]] && [ "$EXTENSION_TEST_INPUT" -ef book ]; then
	report ok input
else
	report no input
fi
case "$EXTENSION_TEST_FORMAT" in
html) expected=book/_book/index.html ;;
typst) expected=book/_book/Fixture-Book.pdf ;;
*) expected='' ;;
esac
if [[ "$EXTENSION_TEST_OUTPUT" == /* ]] && [ -n "$expected" ] && [ "$EXTENSION_TEST_OUTPUT" -ef "$expected" ]; then
	report ok output
else
	report no output
fi
if [ "$EXTENSION_TEST_CASE_ID" = "render/book/$EXTENSION_TEST_FORMAT" ]; then
	report ok 'case id'
else
	report no 'case id'
fi
