#!/usr/bin/env bash
# Headless tests for the DaxCalendar spoon. Needs only `lua` (5.3+) -- no
# Hammerspoon, no GUI.
#
#   tests/run.sh            # all scenarios
#   tests/run.sh 2026-10-01 # one scenario
set -uo pipefail
cd "$(dirname "$0")"

DATES=("$@")
if [ ${#DATES[@]} -eq 0 ]; then
	# Today, a holiday with a 休 badge, a 4-row month (Feb 2026), a year-wrap
	# window (Jan and Dec), and a leap-February window.
	DATES=("2026-09-17" "2026-10-01" "2026-02-10" "2026-01-15" "2026-12-31" "2028-02-29")
fi

fails=0
for d in "${DATES[@]}"; do
	echo "############ $d"
	if ! DATE_Y=${d%%-*} DATE_M=$(echo "$d" | cut -d- -f2) DATE_D=${d##*-} lua harness.lua; then
		fails=$((fails + 1))
	fi
	echo
done

if [ $fails -eq 0 ]; then
	echo "ALL SCENARIOS PASSED (${#DATES[@]} dates)"
else
	echo "$fails SCENARIO(S) FAILED"
fi
exit $((fails > 0))
