#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
swiftc boringNotch/models/CalendarModel.swift boringNotch/models/EventModel.swift \
  boringNotch/models/BrowserSchedule.swift tests/BrowserScheduleTests.swift \
  -o "$work/browser-schedule-tests"
"$work/browser-schedule-tests"
