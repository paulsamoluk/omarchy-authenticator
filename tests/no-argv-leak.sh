#!/usr/bin/env bash
# Proves a copied OTP never appears in any process's arguments, that the
# clipboard is cleared after the timeout, and that newer clipboard content is
# left alone. Runs against a throwaway store and the real Wayland clipboard.
set -u
O=${OTP_HELPER:-$(cd "$(dirname "$0")/.." && pwd)/bin/otp}
WORK=$(mktemp -d)
export TOTP_DATA_DIR="$WORK" TOTP_CLIPBOARD_CLEAR=3
fail=0
say() { printf '%s\n' "$*"; }
check() { if [ "$2" = ok ]; then say "  PASS  $1"; else say "  FAIL  $1 ($2)"; fail=$((fail+1)); fi; }

printf 'JBSWY3DPEHPK3PXP\n' | $O add --label ArgvTest --issuer T >/dev/null 2>&1

say "copy a code"
CODE=$($O copy ArgvTest)
say "  copied: ${CODE:0:3}… (length ${#CODE})"
[ -n "$CODE" ] && check "code produced" ok || check "code produced" empty

say "the watchdog exists and carries no code in its argv"
# Find it precisely: python <plugin>/bin/otp _clipclear <seconds>. A plain
# pgrep on "_clipclear" also matches the shell that runs this test.
find_watchdog() {
  for d in /proc/[0-9]*; do
    [ -r "$d/cmdline" ] || continue
    mapfile -d '' args < "$d/cmdline" 2>/dev/null || continue
    [ "${#args[@]}" -ge 3 ] || continue
    case "${args[0]}" in *python*) ;; *) continue ;; esac
    case "${args[1]}" in */otp) ;; *) continue ;; esac
    [ "${args[2]}" = "_clipclear" ] || continue
    printf '%s' "${args[*]}"
    return 0
  done
  return 1
}

watchdog=""
for _ in 1 2 3 4 5 6; do
  watchdog=$(find_watchdog) && break
  sleep 0.3
done
if [ -n "$watchdog" ]; then
  check "watchdog started" ok
  say "  argv: $watchdog"
  case "$watchdog" in
    *"$CODE"*) check "watchdog argv has no code" "$watchdog" ;;
    *) check "watchdog argv has no code" ok ;;
  esac
else
  check "watchdog started" "no _clipclear process found"
fi

say "scan every process's command line for the code, over the whole timeout"
hit=""
for _ in 1 2 3 4 5 6 7 8; do
  for pid_dir in /proc/[0-9]*; do
    [ -r "$pid_dir/cmdline" ] || continue
    if tr '\0' ' ' < "$pid_dir/cmdline" 2>/dev/null | grep -q -- "$CODE"; then
      hit="$(cat "$pid_dir/comm" 2>/dev/null): $(tr '\0' ' ' < "$pid_dir/cmdline" | cut -c1-120)"
      break 2
    fi
  done
  sleep 0.5
done
[ -z "$hit" ] && check "no child process carries the code in argv" ok || check "no child process carries the code in argv" "$hit"

say "clipboard is cleared once the timeout passes"
sleep 4
after=$(wl-paste -n 2>/dev/null)
[ "$after" != "$CODE" ] && check "clipboard no longer holds the code" ok || check "clipboard no longer holds the code" "still there"

say "newer clipboard content survives"
CODE2=$($O copy ArgvTest)
printf 'newer-content' | wl-copy
sleep 4
kept=$(wl-paste -n 2>/dev/null)
[ "$kept" = "newer-content" ] && check "newer content untouched" ok || check "newer content untouched" "${kept:0:20}"

say "a URI on argv is refused"
out=$(printf '' | $O add-uri 'otpauth://totp/x?secret=JBSWY3DPEHPK3PXP' 2>&1)
case "$out" in *stdin*) check "add-uri refuses argv" ok ;; *) check "add-uri refuses argv" "$out" ;; esac

wl-copy --clear 2>/dev/null
rm -rf "$WORK"
say ""
[ "$fail" = "0" ] && say "ALL CHECKS PASSED" || say "$fail CHECK(S) FAILED"
exit "$fail"
