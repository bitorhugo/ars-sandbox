#!/usr/bin/env bash
# Smoke tests for the ars-sandbox image. Runs INSIDE the container, launched
# through the real run configuration from the repo root:
#
#   bin/ars --shell tests/smoke.sh [--pandoc] [--tectonic] [--pdf-classifier]
#
# Flags assert that the matching optional component was installed.
set -euo pipefail
# The bash -c bodies below are single-quoted on purpose: they expand in the subshell.
# shellcheck disable=SC2016

expect_pandoc=false
expect_tectonic=false
expect_pdf_classifier=false
for arg in "$@"; do
  case "$arg" in
    --pandoc) expect_pandoc=true ;;
    --tectonic) expect_tectonic=true ;;
    --pdf-classifier) expect_pdf_classifier=true ;;
    *) echo "smoke: unknown flag $arg" >&2; exit 2 ;;
  esac
done

failures=0
check() {
  local name="$1"; shift
  if output="$("$@" 2>&1)"; then
    echo "ok   - $name"
  else
    echo "FAIL - $name"
    printf '%s\n' "$output" | sed 's/^/       /'
    failures=$((failures + 1))
  fi
}

# --- tools -------------------------------------------------------------------
for tool in bash jq curl git python3 claude; do
  check "$tool is on PATH" command -v "$tool"
done
check "claude runs" claude --version
check "python3 is the venv" test "$(command -v python3)" = /opt/venv/bin/python3
check "ARS Python deps import" \
  python3 -c 'import yaml, ruamel.yaml, jsonschema, pypdf, defusedxml, markdown_it, linkify_it'

if $expect_pandoc; then
  check "pandoc installed" pandoc --version
fi
if $expect_tectonic; then
  check "tectonic installed" tectonic --version
fi
if $expect_pdf_classifier; then
  check "pdf classifier imports" python3 -c 'import pdf_inspector'
fi

# --- ARS plugin --------------------------------------------------------------
check "ARS version recorded" grep -qE '^v[0-9]+(\.[0-9]+)*$' /opt/ars/.ars-ref
check "ARS plugin validates" claude plugin validate /opt/ars
check "update check disabled" test "${ARS_UPDATE_CHECK:-}" = 0

announce() {
  echo '{"hook_event_name":"SessionStart","source":"startup"}' \
    | bash /opt/ars/scripts/announce-ars-loaded.sh \
    | jq -e '.hookSpecificOutput.additionalContext | length > 0'
}
check "SessionStart hook emits context" announce

guard() {
  jq -n --arg cwd "$PWD" \
    '{hook_event_name:"PreToolUse", tool_name:"Bash", tool_input:{command:"ls"}, cwd:$cwd}' \
    | bash /opt/ars/hooks/run_guard.sh \
    | jq -e '.hookSpecificOutput.hookEventName == "PreToolUse"
             and (.hookSpecificOutput.permissionDecision // "") != "deny"'
}
check "write-scope guard allows a harmless command" guard

# --- isolation ---------------------------------------------------------------
check "runs as non-root" test "$(id -u)" != 0
check "UID matches the workspace owner" test "$(id -u)" = "$(stat -c %u .)"
check "root filesystem is read-only" bash -c '! touch /opt/ars/.write-test 2>/dev/null'
check "/tmp is writable" bash -c 'f=$(mktemp) && rm "$f"'
check "home is writable" bash -c 'touch ~/.write-test && rm ~/.write-test'
check "workspace is writable" bash -c 'f=$(mktemp -p .) && rm "$f"'
# Non-root has no effective capabilities anyway; the bounding set shows --cap-drop ALL.
check "capabilities dropped" bash -c 'grep -q "^CapBnd:[[:space:]]*0*$" /proc/self/status'
check "no-new-privileges set" bash -c 'grep -q "^NoNewPrivs:[[:space:]]*1$" /proc/self/status'

echo
if [ "$failures" -gt 0 ]; then
  echo "$failures check(s) failed"
  exit 1
fi
echo "all checks passed"
