//
//  BoringCalendar.swift
//  boringNotch
//
//  Created by Harsh Vardhan Goswami on 08/09/24.
//

import Defaults
import SwiftUI

struct CalendarView: View {
    @ObservedObject private var calendarManager = CalendarManager.shared
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    @State private var haptics = false

    private var weekDates: [Date] {
        let calendar = Calendar.current
        let start = calendar.dateInterval(of: .weekOfYear, for: selectedDate)?.start ?? selectedDate
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private var events: [EventModel] {
        EventListView.filteredEvents(events: calendarManager.events)
    }

    var body: some View {
        VStack(spacing: 12) {
            header
            weekStrip
            Rectangle().fill(.white.opacity(0.1)).frame(height: 1)
            HStack {
                Text(Calendar.current.isDateInToday(selectedDate) ? "Today’s agenda" : selectedDate.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
                Text("\(events.count) \(events.count == 1 ? "event" : "events")")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            if events.isEmpty {
                EmptyEventsView(selectedDate: selectedDate)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EventListView(events: events)
                    .id(selectedDate)
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(height: 320, alignment: .top)
        .sensoryFeedback(.selection, trigger: haptics)
        .task(id: selectedDate) {
            await calendarManager.updateCurrentDate(selectedDate)
        }
        .task {
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(60))
                } catch {
                    return
                }
                await calendarManager.refreshSchedules()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(selectedDate.formatted(.dateTime.month(.wide).year()))
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(.white)
            Spacer(minLength: 8)
            Button("Today") { selectDate(Date()) }
                .font(.system(size: 11, weight: .medium))
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(.white.opacity(0.08), in: Capsule())
                .help("Go to today")
            weekButton(symbol: "chevron.left", label: "Previous week", days: -7)
            weekButton(symbol: "chevron.right", label: "Next week", days: 7)
        }
        .frame(height: 30)
    }

    private var weekStrip: some View {
        HStack(spacing: 6) {
            ForEach(weekDates, id: \.self) { date in
                let selected = Calendar.current.isDate(date, inSameDayAs: selectedDate)
                let today = Calendar.current.isDateInToday(date)
                Button { selectDate(date) } label: {
                    VStack(spacing: 5) {
                        Text(date.formatted(.dateTime.weekday(.abbreviated)))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(selected ? Color.black.opacity(0.6) : .white.opacity(0.45))
                        Text(date.formatted(.dateTime.day()))
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundStyle(selected ? Color.black : .white)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(selected ? Color.white : today ? .white.opacity(0.07) : .clear,
                                in: RoundedRectangle(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(today && !selected ? .white.opacity(0.25) : .clear)
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
                .accessibilityAddTraits(selected ? .isSelected : [])
                .help(today ? "Today" : date.formatted(date: .complete, time: .omitted))
            }
        }
    }

    private func weekButton(symbol: String, label: String, days: Int) -> some View {
        Button {
            if let date = Calendar.current.date(byAdding: .day, value: days, to: selectedDate) {
                selectDate(date)
            }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 28, height: 28)
                .background(.white.opacity(0.06), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
    }

    private func selectDate(_ date: Date) {
        withAnimation(.easeInOut(duration: 0.15)) {
            selectedDate = Calendar.current.startOfDay(for: date)
        }
        if Defaults[.enableHaptics] { haptics.toggle() }
    }
}

private struct EmptyEventsView: View {
    let selectedDate: Date

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar")
                .font(.system(size: 25, weight: .light))
                .foregroundStyle(.white.opacity(0.35))
            Text(Calendar.current.isDateInToday(selectedDate) ? "Nothing scheduled today" : "Nothing scheduled")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
            Text("Choose another day to see your agenda.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}

struct EventListView: View {
    @Environment(\.openURL) private var openURL
    @ObservedObject private var calendarManager = CalendarManager.shared
    @Default(.autoScrollToNextEvent) private var autoScrollToNextEvent
    @Default(.showFullEventTitles) private var showFullEventTitles
    @State private var hoveredEventID: String?
    let events: [EventModel]

    static func filteredEvents(events: [EventModel]) -> [EventModel] {
        events.filter { event in
            if case .reminder(let completed) = event.type {
                return !completed || !Defaults[.hideCompletedReminders]
            }
            return !event.isAllDay || !Defaults[.hideAllDayEvents]
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: 7) {
                    ForEach(events) { event in
                        eventRow(event)
                            .id(event.id)
                    }
                }
                .padding(.trailing, 2)
            }
            .scrollIndicators(.automatic)
            .onAppear { scrollToRelevantEvent(proxy) }
            .onChange(of: events) { _, _ in scrollToRelevantEvent(proxy) }
            .onChange(of: autoScrollToNextEvent) { _, _ in scrollToRelevantEvent(proxy) }
        }
    }

    private func scrollToRelevantEvent(_ proxy: ScrollViewProxy) {
        guard autoScrollToNextEvent else { return }
        let next = events.first { !$0.isAllDay && $0.end > Date() }
        guard let target = next ?? events.first else { return }
        Task { @MainActor in
            withTransaction(Transaction(animation: nil)) {
                proxy.scrollTo(target.id, anchor: .top)
            }
        }
    }

    private func eventRow(_ event: EventModel) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if case .reminder(let completed) = event.type {
                Button {
                    Task {
                        await calendarManager.setReminderCompleted(reminderID: event.id, completed: !completed)
                    }
                } label: {
                    Image(systemName: completed ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 17))
                        .foregroundStyle(sourceColor(event))
                        .frame(width: 20, height: 25)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(completed ? "Mark \(event.title) incomplete" : "Complete \(event.title)")
                .help(completed ? "Mark incomplete" : "Mark complete")
            } else {
                RoundedRectangle(cornerRadius: 2)
                    .fill(sourceColor(event))
                    .frame(width: 3)
                    .frame(maxHeight: .infinity)
            }
            Button {
                if let url = event.calendarAppURL() { openURL(url) }
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    timeColumn(event)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(event.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.95))
                            .lineLimit(showFullEventTitles ? nil : 2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        if let location = event.location, !location.isEmpty {
                            Text(location)
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.5))
                                .lineLimit(1)
                        }
                        HStack(spacing: 6) {
                            Text(sourceLabel(event))
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(sourceColor(event))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(sourceColor(event).opacity(0.12), in: Capsule())
                            if !event.isAllDay && event.eventStatus == .inProgress {
                                Text("Now")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(hoveredEventID == event.id ? 0.65 : 0.2))
                        .padding(.top, 3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open \(event.title)")
        }
        .padding(10)
        .background(.white.opacity(hoveredEventID == event.id ? 0.085 : 0.045),
                    in: RoundedRectangle(cornerRadius: 11))
        .opacity(isCompleted(event) ? 0.5 : 1)
        .onHover { hoveredEventID = $0 ? event.id : nil }
    }

    private func timeColumn(_ event: EventModel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if event.isAllDay {
                Text("All day")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
            } else {
                Text(event.start, style: .time)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                Text(event.end, style: .time)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .monospacedDigit()
        .frame(width: 56, alignment: .leading)
    }

    private func sourceColor(_ event: EventModel) -> Color {
        switch event.calendar.id {
        case "schedule:teaching": return .teal
        case "schedule:college": return .blue
        default: return Color(event.calendar.color)
        }
    }

    private func sourceLabel(_ event: EventModel) -> String {
        switch event.calendar.id {
        case "schedule:teaching": return "Teaching"
        case "schedule:college": return "College"
        default: return event.calendar.title
        }
    }

    private func isCompleted(_ event: EventModel) -> Bool {
        if case .reminder(let completed) = event.type { return completed }
        return false
    }
}

#Preview {
    CalendarView()
        .padding(20)
        .frame(width: 640)
        .background(.black)
}
