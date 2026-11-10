#!/bin/bash
# Runs the tests. Extra arguments go to `swift test`, e.g. `scripts/test.sh --filter Todos`.
set -euo pipefail
cd "$(dirname "$0")/.."

args=()
# The Command Line Tools ship Swift Testing outside the default search path, and its Foundation
# overlay without a module, so point at the framework and leave the overlay out.
CLT_FRAMEWORKS=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
if [ "$(xcode-select -p)" = /Library/Developer/CommandLineTools ] && [ -d "$CLT_FRAMEWORKS/Testing.framework" ]; then
    args=(-Xswiftc -F -Xswiftc "$CLT_FRAMEWORKS" -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays
          -Xlinker -F -Xlinker "$CLT_FRAMEWORKS" -Xlinker -rpath -Xlinker "$CLT_FRAMEWORKS")
fi

# The MCP tests run the server binary. Same flags as the tests, so nothing is built twice.
swift build --product focusflow-mcp ${args[@]+"${args[@]}"}
swift test ${args[@]+"${args[@]}"} "$@"
