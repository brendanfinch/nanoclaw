#!/bin/bash
# Filters today's meetings from all_meetings.json and copies matching transcripts.
# Run before the meeting insights agent task.
#
# Input:  ~/nanoclaw-data/granola-shared/all_meetings.json
#         ~/nanoclaw-data/granola-shared/transcripts/
# Output: ~/nanoclaw-data/granola-shared/todays_meetings.json
#         ~/nanoclaw-data/granola-shared/todays_transcripts/

set -euo pipefail

SHARED_DIR="$HOME/nanoclaw-data/granola-shared"
INPUT="$SHARED_DIR/all_meetings.json"
OUTPUT="$SHARED_DIR/todays_meetings.json"
TRANSCRIPTS_SRC="$SHARED_DIR/transcripts"
TRANSCRIPTS_DST="$SHARED_DIR/todays_transcripts"

TODAY=$(date -u +%Y-%m-%d)

if [ ! -f "$INPUT" ]; then
  echo "Error: $INPUT not found" >&2
  exit 1
fi

# Filter meetings where created_at or updated_at matches today
jq --arg today "$TODAY" '{
  date: $today,
  meetings: [.meetings[] | select(
    (.created_at // "" | startswith($today)) or
    (.updated_at // "" | startswith($today))
  )]
} | . + {total: (.meetings | length)}' "$INPUT" > "$OUTPUT"

COUNT=$(jq '.total' "$OUTPUT")
echo "$(date -Iseconds) Filtered $COUNT meetings for $TODAY"

# Copy matching transcripts
rm -rf "$TRANSCRIPTS_DST"
mkdir -p "$TRANSCRIPTS_DST"

jq -r '.meetings[].id' "$OUTPUT" | while read -r id; do
  short="${id%%-*}"
  src="$TRANSCRIPTS_SRC/transcript_${short}.json"
  if [ -f "$src" ]; then
    cp "$src" "$TRANSCRIPTS_DST/"
  fi
done

TCOUNT=$(ls "$TRANSCRIPTS_DST" 2>/dev/null | wc -l | tr -d ' ')
echo "$(date -Iseconds) Copied $TCOUNT transcripts to $TRANSCRIPTS_DST"
