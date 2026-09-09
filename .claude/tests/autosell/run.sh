#!/bin/sh
# Run the offline auto-sell suite. Works from anywhere; the suite itself reads addon files by
# path relative to the repo root, so it is run from there.
#
# It lives under .claude/ because publish.sh's CurseForge zip excludes .claude/* wholesale but
# excludes no other directory of .lua files - a top-level tests/ would ship inside the addon.
#
# Lua 5.1 in a container because that is WoW's interpreter version and nothing here should depend
# on a Lua the developer happens to have installed. Pinned by digest, not by the floating
# 5.1-alpine tag: a suite whose interpreter can change under it cannot tell a regression in the
# addon from a regression in the image. Repin deliberately with `docker image inspect` after
# pulling a newer one.
#
# Exit status is the suite's: 0 = all green.
set -e
image=akorn/lua@sha256:02c91360059f16c4b0b67e449c33444d24e0b0cc5398fc0bbfc450fd062466e0
repo=$(cd "$(dirname "$0")/../../.." && pwd)
exec docker run --rm -v "$repo":/w -w /w "$image" \
    lua .claude/tests/autosell/test_autosell.lua
