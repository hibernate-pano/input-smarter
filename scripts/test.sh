#!/bin/bash
# Run the test suite.
#
# Swift Testing's `@Test` macro is a compiler plugin. SwiftPM does not load it
# by itself with the Command Line Tools, so the plugin library is named
# explicitly; without it the test target fails to build.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

PLUGIN=""
for candidate in \
    "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib" \
    "$(xcode-select -p 2>/dev/null)/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"; do
    if [ -f "$candidate" ]; then
        PLUGIN="$candidate"
        break
    fi
done

if [ -z "$PLUGIN" ]; then
    echo "cannot find libTestingMacros.dylib" >&2
    exit 1
fi

cd "$ROOT"
# Keep the test noise out of the user's log file.
export INPUT_SMARTER_LOG="${TMPDIR:-/tmp}/input-smarter-tests.log"
swift test -Xswiftc -load-plugin-library -Xswiftc "$PLUGIN" "$@"
