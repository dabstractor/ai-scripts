#!/usr/bin/env bash
set -u
SRC=/home/dustin/projects/formality/plan/005_8f88e0ec4482/tasks.json
WORK=/tmp/race-demo
A=P1.M1.T1.S1
B=P1.M1.T1.S2

# Faithful reproduction of tsk's operation: read whole JSON, mutate one node's
# status, write whole JSON back. A `sleep` widens the read->write window so the
# lost-update interleave is observable (tsk's own window is sub-ms, so it only
# fires under real supervisor/foreground timing -- which is exactly the
# 10-minute stuck-"Ready" item seen in production).
rmw() {
  local f="$1" id="$2" st="$3" body new filter
  filter='(.. | objects | select(.id=="'"$id"'") | .status) = "'"$st"'"'
  body=$(cat "$f")                       # == tsk TaskManager ctor load
  sleep 0.02                             # widen window (demo only)
  new=$(printf '%s' "$body" | jq "$filter")
  printf '%s' "$new" > "$f"              # == tsk saveBacklog writeFileSync
}
slow_update() {
  local mode="$1" f="$2" id="$3" st="$4"
  if [[ "$mode" == locked ]]; then
    ( flock 9; rmw "$f" "$id" "$st" ) 9>"${f}.lock"
  else
    rmw "$f" "$id" "$st"
  fi
}
reset() {
  local f="$1"; cp "$SRC" "$f"; rm -f "${f}.lock"
  rmw "$f" "$A" Planned; rmw "$f" "$B" Planned
}
run_trial() {
  local mode="$1" f="$2" N="${3:-15}"; reset "$f"
  local pids=()
  for ((i=0;i<N;i++)); do slow_update "$mode" "$f" "$A" Complete & pids+=($!); done
  for ((i=0;i<N;i++)); do slow_update "$mode" "$f" "$B" Complete & pids+=($!); done
  for p in "${pids[@]}"; do wait "$p"; done
  local sa sb
  sa=$(jq -r '..|objects|select(.id=="'"$A"'")|.status' "$f" | head -1)
  sb=$(jq -r '..|objects|select(.id=="'"$B"'")|.status' "$f" | head -1)
  if [[ "$sa" == "Complete" && "$sb" == "Complete" ]]; then echo OK
  else echo "REGRESSION (A=$sa B=$sb)"; fi
}
run_trials() {
  local mode="$1" label="$2" trials="${3:-10}" N="${4:-15}"
  local reg=0 ok=0 out
  for ((t=0;t<trials;t++)); do
    out=$(run_trial "$mode" "$WORK/$mode.mech.json" "$N")
    if [[ "$out" == OK ]]; then ok=$((ok+1)); else reg=$((reg+1)); fi
  done
  echo "$label: $ok/$trials OK, $reg lost-update regressions"
}
echo "Faithful slow read-modify-write reproduction of tsk's pattern (window widened):"
echo "=== BARE (no flock) ==="; run_trials bare "BARE  " 10 15
echo "=== LOCKED (flock wrapper) ==="; run_trials locked "LOCKED" 10 15
