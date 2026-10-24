#!/bin/sh
set -eu

# swift-sodium ships Clibsodium.xcframework as a path binaryTarget with no SwiftPM checksum,
# and its 0.11.0 tag is mutable upstream. Bind the resolved checkout to the recorded hashes.
# Builds using -clonedSourcePackagesDirPath pass the same path as REPO_MANAGER_SOURCE_PACKAGES.
checkout="${REPO_MANAGER_SOURCE_PACKAGES:-${BUILD_DIR%/Build/*}/SourcePackages}/checkouts/swift-sodium"
if [ ! -d "$checkout" ]; then
    if [ "${CONFIGURATION:-}" = "Debug" ]; then
        echo "warning: swift-sodium checkout not found at $checkout; set REPO_MANAGER_SOURCE_PACKAGES to verify it."
        exit 0
    fi
    echo "error: swift-sodium checkout not found at $checkout; set REPO_MANAGER_SOURCE_PACKAGES to the cloned source packages directory." >&2
    exit 1
fi
exec /usr/bin/python3 -I -c '
import hashlib, json, pathlib, sys
provenance, checkout = json.loads(pathlib.Path(sys.argv[1]).read_text()), pathlib.Path(sys.argv[2])
bad = [n for n, d in provenance["files"].items() if not (checkout/n).is_file() or hashlib.sha256((checkout/n).read_bytes()).hexdigest() != d]
if bad: sys.exit("error: swift-sodium checkout differs from Docs/DEPENDENCY_PROVENANCE.json: " + ", ".join(bad[:5]))
print(len(provenance["files"]), "swift-sodium files match recorded provenance")
' "${SRCROOT}/Docs/DEPENDENCY_PROVENANCE.json" "$checkout"
