import SwiftUI

struct ScheduleNoticeBubble: View {
    let notice: ScheduleNotice
    let open: () -> Void
    let dismiss: () -> Void

    private var tint: Color { notice.kind == .calendar ? .blue : .orange }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: open) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: notice.kind == .calendar ? "calendar" : "checklist")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(tint)
                        .frame(width: 40, height: 40)
                        .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 5) {
                            Text(notice.kind == .calendar ? "UPCOMING EVENT" : "REMINDER")
                            Text("· \(notice.source)")
                        }
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(tint)
                        .lineLimit(1)
                        Text(notice.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        HStack(spacing: 6) {
                            Text(notice.start, style: .time).monospacedDigit()
                            if let location = notice.location, !location.isEmpty {
                                Text("· \(location)").lineLimit(1)
                            }
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(notice.kind == .calendar ? "Open event" : "Open reminder")
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 24, height: 24)
                    .background(.white.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss notification")
            .help("Dismiss notification")
        }
        .padding(16)
        .background(.black, in: RoundedRectangle(cornerRadius: 22))
        .overlay { RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.09)) }
        .shadow(color: .black.opacity(0.45), radius: 12, y: 5)
        .accessibilityElement(children: .contain)
    }
}
