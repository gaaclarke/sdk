#!/usr/bin/env bash
#
# Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
# for details. All rights reserved. Use of this source code is governed by a
# BSD-style license that can be found in the LICENSE file.
#
# When in a Flutter Engine checkout, this script checks what version of the Dart
# SDK the engine is pinned to, and patches the engine if there is a known patch
# that needs to be applied on the next Dart SDK roll in the engine.
#
# This script is meant to be used by 3xHEAD CI infrastructure, allowing
# incompatible changes to be made to the Dart SDK requiring a matching change
# to the Flutter Engine, without breaking the CI. The patch is associated with
# the Dart SDK version the engine is pinned so. When the engine rolls its SDK,
# then it stops applying patches atomically as there isn't a patch available yet
# for the new roll.
#
# Usage: src/third_party/dart/tools/patches/flutter-engine/apply.sh
# (run inside the root of a flutter engine checkout)

set -e
if [ ! -e src/third_party/dart ]; then
  echo "$0: error: "\
       "This script must be run from the root of a flutter engine checkout" >&2
  exit 1
fi
pinned_dart_sdk=$(grep -E "'dart_revision':.*" src/flutter/DEPS |
                  sed -E "s/.*'([^']*)',/\1/")
need_runhooks=false
patch=src/third_party/dart/tools/patches/flutter-engine/${pinned_dart_sdk}.flutter.patch
if [ -e "$patch" ]; then
  (cd flutter && git apply ../$patch)
  need_runhooks=true
fi

patch=src/third_party/dart/tools/patches/flutter-engine/${pinned_dart_sdk}.patch
if [ -e "$patch" ]; then
  (cd src/flutter && git apply ../../$patch)
  need_runhooks=true
fi

if [ $need_runhooks = true ]; then
  # Check if .gclient configuration specifies a cache_dir. Local caches are used
  # by bots to reduce amount of Git traffic. .gclient configuration file
  # is a well-formed Python source so use Python load_source to parse it.
  # If cache_dir is specified then we need to force update the git cache,
  # otherwise git fetch below might fail to find tags and commits we are
  # referencing.
  # Normally gclient sync would update the cache - but we are bypassing
  # it here.
  git_cache = $(python -c 'import imp; config = imp.load_source("config", ".gclient"); print getattr(config, "cache_dir", "");')
  if [ "$git_cache" != "" ]; then
    echo "--- Forcing update of the git_cache ${git_cache}"
    git_cache.py fetch -c ${git_cache} -v --all
  fi

  # DEPS file might have been patched with new version of packages that
  # Dart SDK depends on. Get information about dependencies from the
  # DEPS file and forcefully update checkouts of those dependencies.
  gclient revinfo | grep 'src/third_party/dart/' | while read -r line; do
    # revinfo would produce lines in the following format:
    #     path: git-url@tag-or-hash
    # Where no spaces occur inside path, git-url or tag-or-hash.
    # To extract path and tag-or-hash we replace ': ' and '@' with ' '
    # and then create array from the resulting string which splits it
    # by whitespace.
    line="${line/: / }"
    line="${line/@/ }"
    line=(${line})
    dependency_path=${line[0]}
    dependency_tag_or_hash=${line[2]}

    # Inside dependency compare HEAD to specified tag-or-hash by rev-parse'ing
    # them and comparing resulting hashes.
    # Note: tag^0 forces rev-parse to return commit hash rather then the hash of
    # the tag object itself.
    pushd ${dependency_path} > /dev/null
    if [ $(git rev-parse HEAD) != $(git rev-parse ${dependency_tag_or_hash}^0) ]; then
      echo "${dependency_path} requires update to match DEPS file"
      git fetch origin
      git checkout ${dependency_tag_or_hash}
    fi
    popd > /dev/null
  done
  gclient runhooks
fi
