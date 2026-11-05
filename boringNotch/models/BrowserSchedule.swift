import Cocoa

struct BrowserScheduleSnapshot: Decodable {
    let version: Int
    let sources: [BrowserScheduleSource]

    func validate() throws {
        guard version == 1, Set(sources.map(\.id)).count == sources.count else {
            throw CocoaError(.fileReadCorruptFile)
        }
        for source in sources {
            guard source.id.range(of: "^[a-zA-Z0-9_-]+$", options: .regularExpression) != nil,
                !source.name.isEmpty, BrowserScheduleEvent.isWebURL(source.url),
                Set(source.events.map(\.id)).count == source.events.count,
                source.events.allSatisfy({ $0.isValid }) else {
                throw CocoaError(.fileReadCorruptFile)
            }
        }
    }
}

struct BrowserScheduleSource: Decodable, Identifiable {
    let id: String
    let name: String
    let url: String
    let lastSuccessAt: String?
    let error: String?
    let events: [BrowserScheduleEvent]

    var lastSync: Date? { lastSuccessAt.flatMap(BrowserScheduleEvent.date) }

    var calendar: CalendarModel {
        let colors: [NSColor] = [.systemTeal, .systemOrange, .systemPurple, .systemBlue]
        let colorIndex = id.utf8.reduce(0) { ($0 + Int($1)) % colors.count }
        return CalendarModel(id: "schedule:\(id)", account: "Browser schedules", title: name,
            color: colors[colorIndex], isSubscribed: true, isReminder: false)
    }

    func eventModels(from day: Date, to dayEnd: Date) -> [EventModel] {
        events.compactMap { event in
            guard let start = BrowserScheduleEvent.date(event.start),
                let end = BrowserScheduleEvent.date(event.end), start < dayEnd, end > day else {
                return nil
            }
            return EventModel(id: "schedule:\(id):\(event.id)", start: start, end: end,
                title: event.title, location: event.location, notes: nil,
                url: URL(string: event.url ?? url), isAllDay: false, type: .event(.accepted),
                calendar: calendar, participants: [], timeZone: nil,
                hasRecurrenceRules: false, priority: nil)
        }
    }
}

struct BrowserScheduleEvent: Decodable {
    let id: String
    let title: String
    let start: String
    let end: String
    let location: String?
    let url: String?

    static func date(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    static func isWebURL(_ value: String) -> Bool {
        guard let url = URL(string: value), let host = url.host, !host.isEmpty else { return false }
        return url.scheme == "https" || url.scheme == "http"
    }

    var isValid: Bool {
        guard !id.isEmpty, !title.isEmpty, let startDate = Self.date(start),
            let endDate = Self.date(end), endDate > startDate else { return false }
        return url.map(Self.isWebURL) ?? true
    }
}
