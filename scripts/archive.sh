#!/bin/bash
set -euo pipefail

usage() {
  echo "Usage: $0 ios|macos [--unsigned] [additional xcodebuild arguments...]" >&2
  exit 2
}

[[ $# -ge 1 ]] || usage
case "$1" in
  ios) scheme=ForumIndex-iOS; destination='generic/platform=iOS' ;;
  macos) scheme=ForumIndex-macOS; destination='generic/platform=macOS' ;;
  *) usage ;;
esac
shift

signing=(CODE_SIGNING_ALLOWED=YES)
suffix=''
if [[ "${1:-}" == --unsigned ]]; then
  signing=(CODE_SIGNING_ALLOWED=NO)
  suffix=-unsigned
  shift
fi

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_dir"
archive_path="$repo_dir/build/archives/$scheme$suffix-$(date +%Y%m%d-%H%M%S).xcarchive"
[[ ! -e "$archive_path" ]] || { echo "Archive already exists: $archive_path" >&2; exit 1; }

xcodebuild -project ForumIndex.xcodeproj \
  -scheme "$scheme" -configuration Release \
  -destination "$destination" \
  -derivedDataPath "build/DerivedData-$scheme" \
  -archivePath "$archive_path" \
  "${signing[@]}" "$@" archive

echo "Archive: $archive_path"
if [[ -n "$suffix" ]]; then
  echo 'Unsigned verification archive only. Create a signed archive before distributing.'
fi
