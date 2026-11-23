import SwiftUI

/// The month, drawn for somebody else's screen.
///
/// Not a screenshot. A screenshot of Home carries the permission banner, the
/// tab bar, the battery and whatever sheet was half open; this is the month
/// and the three figures that describe it, on a plain card, at a size that
/// survives being sent through a messaging app.
///
/// It deliberately leaves the weight column out. The calendar on screen
/// carries a weekly weight in the gutter, and that is the one number on this
/// app most people would not want to put in a group chat by accident — the
/// share has to be a decision, not a side effect of the layout.
struct MonthShareCard: View {
    let grid: MonthGrid
    let activity: ActivityStore

    private var calendar: Calendar { activity.calendar }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(grid.month, format: .dateTime.month(.wide).year())
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                Spacer()
                Text("Verus")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.accentColor)
            }

            MonthCalendarView(
                grid: grid,
                activity: activity,
                // No weight in the gutter. See the note above.
                weeklyAverages: [:],
                showsWeight: false
            )

            HStack(spacing: 10) {
                tile(activity.averageSteps(in: grid).map(HomeView.grouped) ?? "—", "avg steps/day")
                if let miles = activity.totalMiles(in: grid) {
                    tile(miles.formatted(.number.precision(.fractionLength(0))), "miles")
                }
                tile("\(activity.daysAtGoal(in: grid))", "days at goal")
            }
        }
        .padding(22)
        .frame(width: 420)
        .background(Color(.systemBackground))
    }

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 11)
        .background(Color(.systemGroupedBackground), in: .rect(cornerRadius: 12))
    }
}

/// The rendered month, with the caption attached to it rather than sent
/// alongside as a second item.
///
/// Passing `[image, text]` works but shows a document icon in the share
/// sheet's preview, because the sheet previews the first item it can
/// describe. An item source lets the picture be the item *and* the
/// thumbnail, with the caption as the subject a mail client would use.
final class MonthShareItem: NSObject, UIActivityItemSource {
    private let image: UIImage
    private let caption: String

    init(image: UIImage, caption: String) {
        self.image = image
        self.caption = caption
    }

    func activityViewControllerPlaceholderItem(_ controller: UIActivityViewController) -> Any {
        image
    }

    func activityViewController(
        _ controller: UIActivityViewController,
        itemForActivityType type: UIActivity.ActivityType?
    ) -> Any? {
        image
    }

    func activityViewController(
        _ controller: UIActivityViewController,
        subjectForActivityType type: UIActivity.ActivityType?
    ) -> String {
        caption
    }

    func activityViewController(
        _ controller: UIActivityViewController,
        thumbnailImageForActivityType type: UIActivity.ActivityType?,
        suggestedSize size: CGSize
    ) -> UIImage? {
        image
    }
}

/// The system share sheet.
///
/// `ShareLink` wants its payload before the button is drawn, and rendering
/// a month to an image on every redraw of Home to satisfy that would be
/// absurd. This renders once, when the button is pressed.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
