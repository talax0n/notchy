import Cocoa

@main
struct ScheduleNoticeTests {
    static func main() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let calendar = CalendarModel(id: "college", account: "Test", title: "College", color: .systemBlue,
            isSubscribed: true, isReminder: false)
        func event(_ id: String, start: Date, type: EventType = .event(.accepted), allDay: Bool = false) -> EventModel {
            EventModel(id: id, start: start, end: start.addingTimeInterval(3600), title: "Class \(id)",
                location: "Room 101", notes: nil, url: nil, isAllDay: allDay, type: type,
                calendar: calendar, participants: [], timeZone: nil, hasRecurrenceRules: false, priority: nil)
        }
        let options = ScheduleNoticeOptions()
        let classSoon = event("class", start: now.addingTimeInterval(600))
        let reminderDue = event("reminder", start: now, type: .reminder(completed: false))
        func due(_ events: [EventModel], ledger: ScheduleNoticeLedger = .init(), time: Date = now,
                 settings: ScheduleNoticeOptions = options, selected: Set<String> = ["college"]) -> [ScheduleNotice] {
            ScheduleNoticePlanner.dueNotices(events: events, selectedCalendarIDs: selected,
                options: settings, ledger: ledger, now: time)
        }
        precondition(due([classSoon]).count == 1)
        precondition(due([classSoon], time: now.addingTimeInterval(-1)).isEmpty)
        precondition(due([reminderDue]).first?.kind == .reminder)
        precondition(due([classSoon], selected: []).isEmpty)
        precondition(due([event("completed", start: now, type: .reminder(completed: true))]).isEmpty)
        precondition(due([event("all-day", start: now, allDay: true)]).isEmpty)
        precondition(due([event("date-only", start: now, type: .reminder(completed: false), allDay: true)]).isEmpty)
        precondition(due([event("declined", start: now.addingTimeInterval(600), type: .event(.declined))]).isEmpty)
        precondition(due([classSoon, classSoon]).count == 1)
        precondition(due([classSoon], time: now.addingTimeInterval(119)).count == 1)
        precondition(due([classSoon], time: now.addingTimeInterval(121)).isEmpty)
        precondition(due([event("tomorrow", start: now.addingTimeInterval(86400))]).isEmpty)
        var disabled = options
        disabled.calendarEnabled = false
        precondition(due([classSoon, reminderDue], settings: disabled).map(\.kind) == [.reminder])
        disabled.remindersEnabled = false
        precondition(due([classSoon, reminderDue], settings: disabled).isEmpty)
        var earlyReminder = options
        earlyReminder.reminderLeadMinutes = 5
        precondition(due([event("early", start: now.addingTimeInterval(300), type: .reminder(completed: false))], settings: earlyReminder).count == 1)
        let first = due([classSoon])[0]
        var ledger = ScheduleNoticeLedger()
        ledger.record(first, at: now)
        let restored = try JSONDecoder().decode(ScheduleNoticeLedger.self, from: JSONEncoder().encode(ledger))
        precondition(due([classSoon], ledger: restored).isEmpty)
        precondition(due([event("class", start: now.addingTimeInterval(660))], ledger: restored, time: now.addingTimeInterval(60)).count == 1)
        var preview = first
        preview.isPreview = true
        var previewLedger = ScheduleNoticeLedger()
        previewLedger.record(preview, at: now)
        precondition(previewLedger.delivered.isEmpty)
        let ordered = due([classSoon, event("earlier", start: now.addingTimeInterval(550))])
        precondition(ordered.map(\.eventID) == ["earlier", "class"])
        let midnight = Date(timeIntervalSince1970: 86400)
        precondition(due([event("midnight", start: midnight.addingTimeInterval(300))],
            time: midnight.addingTimeInterval(-300)).count == 1)
        ledger.prune(at: now.addingTimeInterval(4 * 86400))
        precondition(ledger.delivered.isEmpty)
        print("Schedule notification checks passed: lead times, due reminders, completion, selection, midnight-safe instants, dedup persistence, preview isolation, wake grace, queue order, pruning.")
    }
}
