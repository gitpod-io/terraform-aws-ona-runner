#!/bin/sh
set -eu

printf '%s\n' "$@" >> "${AWS_TEST_LOG:?}"
exit "${AWS_TEST_STATUS:?}"
