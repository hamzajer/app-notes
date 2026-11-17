#!/usr/bin/env bash
# Copy the APP notes (Markdown only) from the Obsidian vault into content/.
# Course PDFs (CM/), TP subjects and code (TP/) and demos/ stay private.
set -euo pipefail

VAULT="${VAULT:-$HOME/Desktop/Workspace/APP}"
cd "$(dirname "$0")"

rm -rf content
mkdir content
rsync -a --prune-empty-dirs \
  --exclude='/CM/' --exclude='/TP/' --exclude='/demos/' \
  --include='*/' --include='*.md' --exclude='*' \
  "$VAULT/" content/

# The MOC becomes the home page; the alias keeps [[APP — MOC]] links working.
awk 'NR > 1 && /^---$/ && !done { print "aliases:"; print "  - \"APP — MOC\""; done = 1 } { print }' \
  "content/APP — MOC.md" > content/index.md
rm "content/APP — MOC.md"

echo "Synced $(find content -name '*.md' | wc -l) notes from $VAULT"
