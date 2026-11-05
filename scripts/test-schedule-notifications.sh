#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
swiftc boringNotch/models/CalendarModel.swift boringNotch/models/EventModel.swift \
  boringNotch/models/ScheduleNotice.swift tests/ScheduleNoticeTests.swift \
  -o "$work/schedule-notice-tests"
"$work/schedule-notice-tests"
