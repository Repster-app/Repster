#!/bin/zsh

set -euo pipefail

if [[ $# -ne 1 ]]; then
  print "Usage: scripts/bump_release.sh \"One sentence summary.\""
  exit 1
fi

summary="${1//$'\n'/ }"
summary="${summary#"${summary%%[![:space:]]*}"}"
summary="${summary%"${summary##*[![:space:]]}"}"

if [[ -z "$summary" ]]; then
  print "Release summary cannot be empty."
  exit 1
fi

script_dir="${0:A:h}"
project_root="${script_dir:h}"
project_file="$project_root/Reppo.xcodeproj/project.pbxproj"
changelog_file="$project_root/CHANGELOG.md"
note_line='Versioning rule: the app marketing version uses `0.x`, and each release bumps `x` by 1.'

current_version="$(
  grep -m1 'MARKETING_VERSION = ' "$project_file" |
  sed -E 's/.*MARKETING_VERSION = ([^;]+);/\1/'
)"

if [[ ! "$current_version" =~ ^0\.([0-9]+)$ ]]; then
  print "Expected MARKETING_VERSION in 0.x format, found $current_version."
  exit 1
fi

current_minor="${match[1]}"
next_version="0.$((current_minor + 1))"

current_build="$(
  grep -m1 'CURRENT_PROJECT_VERSION = ' "$project_file" |
  sed -E 's/.*CURRENT_PROJECT_VERSION = ([^;]+);/\1/'
)"

if [[ ! "$current_build" =~ ^[0-9]+$ ]]; then
  print "Expected CURRENT_PROJECT_VERSION to be an integer, found $current_build."
  exit 1
fi

next_build="$((current_build + 1))"

CURRENT_VERSION="$current_version" \
NEXT_VERSION="$next_version" \
CURRENT_BUILD="$current_build" \
NEXT_BUILD="$next_build" \
perl -0pi -e '
  s/\QMARKETING_VERSION = $ENV{CURRENT_VERSION};\E/MARKETING_VERSION = $ENV{NEXT_VERSION};/g;
  s/\QCURRENT_PROJECT_VERSION = $ENV{CURRENT_BUILD};\E/CURRENT_PROJECT_VERSION = $ENV{NEXT_BUILD};/g;
' "$project_file"

entry=$'## '"$next_version"$' ('"$(date +%F)"$')\n'"$summary"$'\n\n'

if [[ -f "$changelog_file" ]]; then
  CHANGELOG_ENTRY="$entry" CHANGELOG_NOTE="$note_line" perl -0pi -e '
    my $header = "# Changelog\n\n";
    my $note = $ENV{CHANGELOG_NOTE} . "\n\n";
    if (s/\Q$header$note\E/$header . $note . $ENV{CHANGELOG_ENTRY}/e) {
      # Entry inserted after the versioning note.
    } elsif (s/\Q$header\E/$header . $ENV{CHANGELOG_ENTRY}/e) {
      # Entry inserted after the header.
    } else {
      $_ = $header . $note . $ENV{CHANGELOG_ENTRY} . $_;
    }
  ' "$changelog_file"
else
  {
    print -r -- "# Changelog"
    print
    print -r -- "$note_line"
    print
    print -r -- "## $next_version ($(date +%F))"
    print -r -- "$summary"
  } > "$changelog_file"
fi

print "Bumped MARKETING_VERSION $current_version -> $next_version"
print "Bumped CURRENT_PROJECT_VERSION $current_build -> $next_build"
print "Added changelog entry to $changelog_file"
