#!/bin/bash
# Keeps this repo "active" so GitHub never disables the scheduled DNS-failover workflow.
# Every 25 days: append one random character to keepalive.txt and commit "Added letter X".
# Run daily from cron; the script itself decides if 25 days have passed.
set -euo pipefail
cd "$(dirname "$0")"

FILE=keepalive.txt
STAMP=.last_add
DAYS=25
BRANCH=main
CHARS=$'abcdefghijklmnopqrstuvwxyz1234567890!@#$%^&*()_+-=:;"\'<>?,./'

touch "$FILE"
today=$(date +%F)

if [ -s "$STAMP" ]; then
  age=$(( ( $(date -d "$today" +%s) - $(date -d "$(cat "$STAMP")" +%s) ) / 86400 ))
else
  age=999999   # first run: add immediately
fi
[ "$age" -ge "$DAYS" ] || exit 0

ch=${CHARS:$(( RANDOM % ${#CHARS} )):1}
printf '%s' "$ch" >> "$FILE"
echo "$today" > "$STAMP"
git add "$FILE" "$STAMP"
git commit -q -m "Added letter $ch"
echo "$(date '+%F %T') committed: Added letter $ch"

if git remote get-url origin >/dev/null 2>&1; then
  git push -q origin "$BRANCH" && echo "pushed"
else
  echo "no remote 'origin' yet - not pushed"
fi
