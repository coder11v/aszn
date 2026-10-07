#!/usr/bin/env zsh
# Maintainer tool: bump version, tag, and update the Homebrew formula.
#   scripts/release.zsh 0.2.0
# Then copy Formula/aszn.rb into github.com/coder11v/homebrew-tap.
emulate -L zsh
setopt err_exit

local version=${1:?usage: scripts/release.zsh <version>}
local root=${0:A:h:h} repo=coder11v/aszn
cd $root

# 1. Bump ASZN_VERSION in the plugin.
local src=$(<aszn.zsh)
print -r -- ${src/ASZN_VERSION=[0-9.]##/ASZN_VERSION=$version} >| aszn.zsh

git add aszn.zsh
git commit -m "Release v$version"
git tag "v$version"
git push origin HEAD "v$version"

# 2. Point the formula at the new tarball.
local url="https://github.com/$repo/archive/refs/tags/v$version.tar.gz"
local sha=${$(curl -fsSL $url | shasum -a 256)[1]}
local f=$(<Formula/aszn.rb)
f=${f/url \"[^\"]##\"/url \"$url\"}
f=${f/sha256 \"[^\"]##\"/sha256 \"$sha\"}
print -r -- $f >| Formula/aszn.rb
if [[ -d homebrew/Formula ]]; then
  print -r -- $f >| homebrew/Formula/aszn.rb
fi
git commit -am "Formula: v$version" && git push

print "✓ v$version released. sha256=$sha"
print "  Updated Formula/aszn.rb and homebrew/Formula/aszn.rb."

