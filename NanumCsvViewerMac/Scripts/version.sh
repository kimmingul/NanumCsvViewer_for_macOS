#!/usr/bin/env bash
# Single source of truth for the release version.
#
# build-app.sh, build-appstore-app.sh, package-appstore.sh, and
# upload-appstore.sh all source this file, so cutting a release edits two lines
# here instead of four scripts. That drift is not hypothetical: build-app.sh
# shipped 1.10.0(200) for two months after an App Store re-upload moved the
# other scripts to 201, because only one of them was bumped.
#
# create-dmg.sh deliberately does not source this — it reads the version out of
# the bundle it is packaging, which is stricter, since it names the DMG after
# what was actually built.
#
# Override either value from the environment for a one-off build:
#   BUILD_NUMBER=999 Scripts/build-app.sh
VERSION="${VERSION:-1.10.1}"
BUILD_NUMBER="${BUILD_NUMBER:-203}"
