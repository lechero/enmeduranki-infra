#!/bin/sh

# Usage: ./replace-domain.sh PLACEHOLDER

if [ -z "$1" ]; then
  echo "Usage: $0 <placeholder>"
  exit 1
fi

PLACEHOLDER="$1"

# Find and replace in all files under current folder
grep -rl "enmeduranki.com" . | xargs sed -i "s/enmeduranki\.com/${PLACEHOLDER}/g"

echo "✅ Replaced all occurrences of enmeduranki.com with '${PLACEHOLDER}'"
