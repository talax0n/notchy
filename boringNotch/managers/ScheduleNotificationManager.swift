import AppKit
import Defaults
import SwiftUI

@MainActor
final class ScheduleNotificationManager: ObservableObject {
    static let shared = ScheduleNotificationManager()

    @Published private(set) var activeNotice: ScheduleNotice?
    private let ledgerKey = "scheduleNoticeDeliveryLedger"
    private var ledger: ScheduleNoticeLedger
    private var pollTask: Task<Void, Never>?
    private var dismissTask: Task<Void, Never>?
    private var refreshing = false
    private var queued: [ScheduleNotice] = []
    private var previewQueue: [ScheduleNotice] = []
    private var wakeObserver: NSObjectProtocol?

    private init() {
        ledger = UserDefaults.standard.data(forKey: ledgerKey)
            .flatMap { try? JSONDecoder().decode(ScheduleNoticeLedger.self, from: $0) } ?? ScheduleNoticeLedger()
    }

    func start() {
        guard pollTask == nil else { return }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        dismissTask?.cancel()
        dismissTask = nil
        queued = []
        previewQueue = []
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
        activeNotice = nil
    }

    private var options: ScheduleNoticeOptions {
        ScheduleNoticeOptions(calendarEnabled: Defaults[.calendarBubbleNotifications],
            remindersEnabled: Defaults[.reminderBubbleNotifications],
            calendarLeadMinutes: Defaults[.calendarBubbleLeadMinutes],
            reminderLeadMinutes: Defaults[.reminderBubbleLeadMinutes])
    }

    private func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        let now = Date()
        let settings = options
        let lead = max(settings.calendarLeadMinutes, settings.reminderLeadMinutes)
        let manager = CalendarManager.shared
        let events = await manager.notificationEvents(from: now.addingTimeInterval(-settings.catchUpInterval),
            to: now.addingTimeInterval(Double(max(0, lead)) * 60 + 30))
        guard !Task.isCancelled else { return }
        ledger.prune(at: now)
        queued = ScheduleNoticePlanner.dueNotices(events: events,
            selectedCalendarIDs: manager.selectedCalendarIDs, options: options, ledger: ledger, now: Date())
        if let active = activeNotice, !active.isPreview {
            let stillAvailable = events.contains { event in
                event.id == active.eventID && event.start == active.start &&
                    manager.selectedCalendarIDs.contains(event.calendar.id) &&
                    !(event.type == .reminder(completed: true)) &&
                    (active.kind == .calendar ? options.calendarEnabled : options.remindersEnabled)
            }
            if !stillAvailable { dismiss(showNext: false) }
        }
        presentNext()
    }

    private func presentNext() {
        guard activeNotice == nil else { return }
        if let notice = queued.first {
            queued.removeFirst()
            ledger.record(notice, at: Date())
            if let data = try? JSONEncoder().encode(ledger) { UserDefaults.standard.set(data, forKey: ledgerKey) }
            show(notice)
        } else if !previewQueue.isEmpty {
            show(previewQueue.removeFirst())
        }
    }

    private func show(_ notice: ScheduleNotice) {
        dismissTask?.cancel()
        withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) { activeNotice = notice }
        dismissTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(10)) } catch { return }
            self?.dismiss()
        }
    }

    func dismiss(showNext: Bool = true) {
        dismissTask?.cancel()
        dismissTask = nil
        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) { activeNotice = nil }
        if showNext { Task { [weak self] in await self?.refresh() } }
    }

    func openActiveNotice() {
        guard let notice = activeNotice else { return }
        if let url = notice.url { NSWorkspace.shared.open(url) }
        dismiss()
    }

    func preview(_ kind: ScheduleNoticeKind) {
        let now = Date()
        let notice = ScheduleNotice(id: "preview-\(UUID().uuidString)", kind: kind, eventID: "preview",
            title: kind == .calendar ? "Your next class starts soon" : "Your reminder is due",
            source: "Preview", location: kind == .calendar ? "Room and schedule details appear here" : nil,
            start: kind == .calendar ? now.addingTimeInterval(600) : now, trigger: now, url: nil, isPreview: true)
        if activeNotice != nil {
            previewQueue.append(notice)
        } else {
            show(notice)
        }
    }
}
