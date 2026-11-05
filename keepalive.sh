#!/bin/bash
# Keeps this repo "active" so GitHub never disables the scheduled DNS-failover workflow.
#  - every 25 days AND every 28 days: append one random character, commit "Added letter X"
#  - commits are local, so a missing internet connection cannot make a commit fail
#  - push is retried every day by cron, so anything that failed to upload goes out as soon as the net is back
# Run daily from cron; the script itself decides if 25 / 28 days have passed.
set -uo pipefail
cd "$(dirname "$0")"

FILE=keepalive.txt
BRANCH=main
CHARS=$'abcdefghijklmnopqrstuvwxyz1234567890!@#$%^&*()_+-=:;"\'<>?,./'
today=$(date +%F)
touch "$FILE"

age() {  # days since the date stored in file $1 (999999 if missing)
  [ -s "$1" ] || { echo 999999; return; }
  echo $(( ( $(date -d "$today" +%s) - $(date -d "$(cat "$1")" +%s) ) / 86400 ))
}

add_letter() {  # $1 = stamp file
  local ch=${CHARS:$(( RANDOM % ${#CHARS} )):1}
  printf '%s' "$ch" >> "$FILE"
  echo "$today" > "$1"
  git add "$FILE" "$1"
  git commit -q -m "Added letter $ch" && echo "$(date '+%F %T') committed: Added letter $ch"
}

# 28-day clock starts today on first run (the 25-day one commits immediately)
[ -s .last_add28 ] || echo "$today" > .last_add28

[ "$(age .last_add)"   -ge 25 ] && add_letter .last_add
[ "$(age .last_add28)" -ge 28 ] && add_letter .last_add28

# push every day: uploads new commits and retries any earlier failed push
if git remote get-url origin >/dev/null 2>&1; then
  if timeout 60 git push -q origin "$BRANCH" 2>/tmp/keepalive-push.err; then
    echo "$(date '+%F %T') push ok"
  else
    echo "$(date '+%F %T') push FAILED (will retry tomorrow): $(head -c 200 /tmp/keepalive-push.err)"
  fi
else
  echo "$(date '+%F %T') no remote 'origin' yet - not pushed"
fi
exit 0
