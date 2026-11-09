# Deliver through the existing Happy transport. Codex targets require exact
# server-side native identity; a failed check must never redirect the block.
inject_to() {
  local target_args native_id="${VOICE_NATIVE_ID:-}"
  if [ -n "$native_id" ]; then
    [ -n "${INJECT_SID:-}" ] || { echo 'native delivery requires exact Happy SID' >&2; return 2; }
    node --input-type=module - "$INJECT_SID" "$native_id" "${VOICE_PROJECT_CWD:-/root/projects/voice}" <<'JS' || return 1
import {readHappyState} from '/root/projects/agentops/bin/happy-session-state.mjs';
await readHappyState(process.argv[2], {native_id: process.argv[3], cwd: process.argv[4]});
JS
    target_args=(--to-sid "$INJECT_SID" --strict-sid --native-id "$native_id")
  elif [ -n "${INJECT_SID:-}" ]; then
    target_args=(--to-sid "$INJECT_SID")
  else
    target_args=(--to-cwd "$INJECT_CWD")
  fi
  node "$INJECT" "${target_args[@]}" --message "$1" >/dev/null 2>&1
}
