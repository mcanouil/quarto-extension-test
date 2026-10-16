#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' 'first line' 'browser missing' >&2
exit 3
