import Cocoa

@main
struct BrowserScheduleTests {
    static func main() throws {
        func snapshot(_ events: [[String: Any]], version: Int = 1) throws -> BrowserScheduleSnapshot {
            let json: [String: Any] = ["version": version, "sources": [[
                "id": "teaching", "name": "Teaching", "url": "https://example.com/schedule",
                "events": events
            ]]]
            return try JSONDecoder().decode(BrowserScheduleSnapshot.self,
                from: JSONSerialization.data(withJSONObject: json))
        }
        func event(_ id: String, _ start: String, _ end: String) -> [String: Any] {
            ["id": id, "title": "Algorithms", "start": start, "end": end]
        }
        let overnight = event("night", "2026-11-05T23:30:00+07:00", "2026-11-06T00:30:00+07:00")
        let morning = event("morning", "2026-11-06T09:00:00+07:00", "2026-11-06T11:00:00+07:00")
        let nextDay = event("tomorrow", "2026-11-07T00:00:00+07:00", "2026-11-07T01:00:00+07:00")
        let cache = try snapshot([overnight, morning, nextDay])
        try cache.validate()
        let source = cache.sources[0]
        let start = BrowserScheduleEvent.date("2026-11-06T00:00:00+07:00")!
        let end = BrowserScheduleEvent.date("2026-11-07T00:00:00+07:00")!
        let models = source.eventModels(from: start, to: end)
        precondition(models.map(\.id) == ["schedule:teaching:night", "schedule:teaching:morning"])
        precondition(models[0].calendar.id == "schedule:teaching")
        precondition(models[0].calendarAppURL()?.absoluteString == "https://example.com/schedule")
        precondition(models[0].start == BrowserScheduleEvent.date("2026-11-05T16:30:00Z"))
        precondition(BrowserScheduleEvent.date("2026-11-05T16:30:00.123Z") != nil)
        let empty = try snapshot([])
        try empty.validate()
        precondition(empty.sources[0].eventModels(from: start, to: end).isEmpty)
        for bad in [
            try snapshot([morning, morning]),
            try snapshot([event("bad", "2026-11-06T09:00:00", "2026-11-06T11:00:00")]),
            try snapshot([event("bad", "2026-11-06T11:00:00Z", "2026-11-06T09:00:00Z")]),
            try snapshot([], version: 2)
        ] {
            do {
                try bad.validate()
                fatalError("Invalid schedule accepted")
            } catch {}
        }
        precondition(!BrowserScheduleEvent.isWebURL("javascript:alert(1)"))
        print("Browser schedule checks passed: midnight overlap, offsets, source links, empty schedules, invalid dates, duplicate IDs, schema version.")
    }
}
