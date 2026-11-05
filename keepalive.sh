#!/bin/bash
# Keeps this repo "active" so GitHub never disables the scheduled DNS-failover workflow.
#  - every 25 days: append the next letter of  a..z, aabbcc..zz  to keepalive.txt  (commit "Added letter X")
#  - every 28 days: delete the last letter from keepalive.txt                       (commit "Deleted letter X")
# Run daily from cron; the script itself decides if 25/28 days have passed.
set -euo pipefail
cd "$(dirname "$0")"

FILE=keepalive.txt
SEQ="abcdefghijklmnopqrstuvwxyzaabbccddeeffgghhiijjkkllmmnnooppqqrrssttuuvvwwxxyyzz"
ADD_DAYS=25
DEL_DAYS=28
BRANCH=main
touch "$FILE"

today=$(date +%F)
age() {  # days since date stored in file $1 (999999 if missing)
  [ -s "$1" ] || { echo 999999; return; }
  echo $(( ( $(date -d "$today" +%s) - $(date -d "$(cat "$1")" +%s) ) / 86400 ))
}
commit() {
  git add "$FILE" .last_add .last_del
  git commit -q -m "$1"
  echo "$(date '+%F %T') committed: $1"
  changed=1
}

changed=0
# first run: start the 28-day delete clock today, don't delete anything yet
[ -s .last_del ] || echo "$today" > .last_del

if [ "$(age .last_add)" -ge "$ADD_DAYS" ]; then
  content=$(cat "$FILE")
  ch=${SEQ:$(( ${#content} % ${#SEQ} )):1}
  printf '%s' "$content$ch" > "$FILE"
  echo "$today" > .last_add
  commit "Added letter $ch"
fi

if [ "$(age .last_del)" -ge "$DEL_DAYS" ]; then
  content=$(cat "$FILE")
  if [ -n "$content" ]; then
    ch=${content: -1}
    printf '%s' "${content%?}" > "$FILE"
    echo "$today" > .last_del
    commit "Deleted letter $ch"
  fi
fi

if [ "$changed" = 1 ]; then
  if git remote get-url origin >/dev/null 2>&1; then
    git push -q origin "$BRANCH" && echo "pushed"
  else
    echo "no remote 'origin' yet - not pushed"
  fi
fi
