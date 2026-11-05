import Foundation

enum ScheduleNoticeKind: String, Codable {
    case calendar
    case reminder
}

struct ScheduleNotice: Identifiable, Equatable {
    let id: String
    let kind: ScheduleNoticeKind
    let eventID: String
    let title: String
    let source: String
    let location: String?
    let start: Date
    let trigger: Date
    let url: URL?
    var isPreview = false
}

struct ScheduleNoticeOptions {
    var calendarEnabled = true
    var remindersEnabled = true
    var calendarLeadMinutes = 10
    var reminderLeadMinutes = 0
    var catchUpInterval: TimeInterval = 120
}

struct ScheduleNoticeLedger: Codable {
    private(set) var delivered: [String: Date] = [:]

    mutating func record(_ notice: ScheduleNotice, at now: Date) {
        guard !notice.isPreview else { return }
        delivered[notice.id] = now
        prune(at: now)
    }

    mutating func prune(at now: Date) {
        delivered = delivered.filter { now.timeIntervalSince($0.value) < 3 * 24 * 60 * 60 }
        if delivered.count > 2048 {
            delivered = Dictionary(uniqueKeysWithValues: delivered.sorted { $0.value > $1.value }.prefix(2048).map { ($0.key, $0.value) })
        }
    }
}

enum ScheduleNoticePlanner {
    static func dueNotices(events: [EventModel], selectedCalendarIDs: Set<String>, options: ScheduleNoticeOptions,
                           ledger: ScheduleNoticeLedger, now: Date) -> [ScheduleNotice] {
        var unique: [String: ScheduleNotice] = [:]
        for event in events where selectedCalendarIDs.contains(event.calendar.id) {
            guard !event.isAllDay, event.attendance != .declined else { continue }
            let kind: ScheduleNoticeKind
            switch event.type {
            case .reminder(let completed):
                guard !completed, options.remindersEnabled else { continue }
                kind = .reminder
            case .event:
                guard options.calendarEnabled else { continue }
                kind = .calendar
            case .birthday:
                continue
            }
            guard kind == .reminder || event.end > now else { continue }
            let minutes = kind == .calendar ? options.calendarLeadMinutes : options.reminderLeadMinutes
            let trigger = event.start.addingTimeInterval(-Double(max(0, minutes)) * 60)
            guard trigger <= now, now.timeIntervalSince(trigger) <= options.catchUpInterval else { continue }
            let id = "\(kind.rawValue)|\(event.id.utf8.count):\(event.id)|\(event.start.timeIntervalSince1970)"
            guard ledger.delivered[id] == nil else { continue }
            unique[id] = ScheduleNotice(id: id, kind: kind, eventID: event.id, title: event.title,
                source: event.calendar.title, location: event.location, start: event.start,
                trigger: trigger, url: event.calendarAppURL())
        }
        return unique.values.sorted {
            if $0.trigger != $1.trigger { return $0.trigger < $1.trigger }
            if $0.start != $1.start { return $0.start < $1.start }
            return $0.id < $1.id
        }
    }
}
