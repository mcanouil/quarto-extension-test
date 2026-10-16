#!/usr/bin/env bash
set -euo pipefail

report() {
	if [ "$1" = ok ]; then
		printf 'ok - %s\n' "$2"
	else
		printf 'not ok - %s\n' "$2"
	fi
}

if [[ "$EXTENSION_TEST_INPUT" == /* ]] && [ "$EXTENSION_TEST_INPUT" -ef check-env.qmd ]; then
	report ok input
else
	report no input
fi
if [[ "$EXTENSION_TEST_OUTPUT" == /* ]] && [ "$EXTENSION_TEST_OUTPUT" -ef _output/check-env.html ]; then
	report ok output
else
	report no output
fi
if [ "$EXTENSION_TEST_FORMAT" = html ]; then
	report ok format
else
	report no format
fi
if [ "$EXTENSION_TEST_CASE_ID" = render/check-env/html ]; then
	report ok 'case id'
else
	report no 'case id'
fi
