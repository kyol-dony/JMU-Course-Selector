#!/usr/bin/env bash
DIR="$(cd "$(dirname "$0")" && pwd)"
"$DIR/script/run_tests.sh"
echo
read -r -p "Press Return to close this window."
