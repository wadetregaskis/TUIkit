#!/bin/bash
# Builds the package and runs every case, printing what each one does.
#
#   ./run.sh            # debug — the crashing configuration
#   ./run.sh release    # release — everything passes
set -u
cd "$(dirname "$0")" || exit 2
config="${1:-debug}"
swift build ${config:+-c $config} > /dev/null 2>&1 || { echo "build failed"; exit 1; }
for name in crashes named-second-element conformed-in-its-own-module \
            conformed-in-the-protocols-module aggregate-stores-nothing not-a-pack; do
    printf '%-36s' "$name"
    ".build/$config/App" "$name" > /dev/null 2>&1
    code=$?
    case $code in
        0) echo "ok" ;;
        139) echo "SIGSEGV" ;;
        *) echo "exit $code" ;;
    esac
done
