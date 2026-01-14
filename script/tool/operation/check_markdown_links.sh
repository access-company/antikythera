#!/bin/bash
set -euo pipefail

# Check all markdown files for broken links
# Requires: markdown-link-check (npm install -g markdown-link-check)

cd "$(dirname "$0")/../../.."

find . -name '*.md' -not -path '*/deps/*' -not -path '*/node_modules/*' -print0 | xargs -0 -n1 markdown-link-check --quiet
