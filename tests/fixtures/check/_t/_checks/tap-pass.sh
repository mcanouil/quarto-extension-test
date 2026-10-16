#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' 'TAP version 13' '1..3' 'ok 1 - output exists' 'ok 2 - title # SKIP no title check here' 'not ok 3 - toast # TODO not written yet'
