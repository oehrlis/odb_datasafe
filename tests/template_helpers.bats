#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    VERSION="$(cat "${REPO_ROOT}/VERSION")"
}

@test "build script creates tarball and checksum" {
    dist="${BATS_TMPDIR}/dist"
    run bash -c "cd \"$REPO_ROOT\" && ./scripts/build.sh --dist \"$dist\""
    [ "$status" -eq 0 ]

    tarball="${dist}/odb_datasafe-${VERSION}.tar.gz"
    checksum="${tarball}.sha256"
    [ -f "$tarball" ]
    [ -f "$checksum" ]
}

@test "rename script supports dry run" {
    run bash -c "cd \"$REPO_ROOT\" && ./scripts/rename-extension.sh --name demo --dry-run"
    [ "$status" -eq 0 ]
    [[ "$output" == *"demo"* ]]
}
