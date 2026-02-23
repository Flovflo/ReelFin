import SwiftUI
import WidgetKit

#if canImport(ActivityKit)
import ActivityKit
#endif

struct WidgetMediaCard: Codable, Hashable {
    let title: String
    let subtitle: String
    let progress: Double
}

private enum WidgetDataSource {
    static let appGroupID = "group.com.reelfin.shared"
    static let continueWatchingKey = "widget.continueWatching"
    static let recentAddedKey = "widget.recentlyAdded"

    static func loadCards(for key: String) -> [WidgetMediaCard]? {
        guard
            let defaults = UserDefaults(suiteName: appGroupID),
            let data = defaults.data(forKey: key),
            let cards = try? JSONDecoder().decode([WidgetMediaCard].self, from: data),
            !cards.isEmpty
        else {
            return nil
        }
        return cards
    }

    static func fallbackContinueWatching() -> [WidgetMediaCard] {
        [
            WidgetMediaCard(title: "The Studio", subtitle: "S1 • E4", progress: 0.68),
            WidgetMediaCard(title: "Severance", subtitle: "S2 • E2", progress: 0.34),
            WidgetMediaCard(title: "Silo", subtitle: "S2 • E8", progress: 0.81)
        ]
    }

    static func fallbackRecentlyAdded() -> [WidgetMediaCard] {
        [
            WidgetMediaCard(title: "The Instigators", subtitle: "Movie", progress: 0),
            WidgetMediaCard(title: "Ted Lasso", subtitle: "Series", progress: 0),
            WidgetMediaCard(title: "Foundation", subtitle: "Series", progress: 0)
        ]
    }
}

struct ContinueWatchingEntry: TimelineEntry {
    let date: Date
    let cards: [WidgetMediaCard]
}

struct ContinueWatchingProvider: TimelineProvider {
    func placeholder(in context: Context) -> ContinueWatchingEntry {
        ContinueWatchingEntry(date: Date(), cards: WidgetDataSource.fallbackContinueWatching())
    }

    func getSnapshot(in context: Context, completion: @escaping (ContinueWatchingEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ContinueWatchingEntry>) -> Void) {
        let cards = WidgetDataSource.loadCards(for: WidgetDataSource.continueWatchingKey)
            ?? WidgetDataSource.fallbackContinueWatching()
        let entry = ContinueWatchingEntry(date: Date(), cards: cards)
        let refreshDate = Calendar.current.date(byAdding: .minute, value: 20, to: Date()) ?? Date().addingTimeInterval(1200)
        completion(Timeline(entries: [entry], policy: .after(refreshDate)))
    }
}

struct RecentlyAddedEntry: TimelineEntry {
    let date: Date
    let cards: [WidgetMediaCard]
}

struct RecentlyAddedProvider: TimelineProvider {
    func placeholder(in context: Context) -> RecentlyAddedEntry {
        RecentlyAddedEntry(date: Date(), cards: WidgetDataSource.fallbackRecentlyAdded())
    }

    func getSnapshot(in context: Context, completion: @escaping (RecentlyAddedEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RecentlyAddedEntry>) -> Void) {
        let cards = WidgetDataSource.loadCards(for: WidgetDataSource.recentAddedKey)
            ?? WidgetDataSource.fallbackRecentlyAdded()
        let entry = RecentlyAddedEntry(date: Date(), cards: cards)
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(1800))))
    }
}

struct ContinueWatchingWidgetEntryView: View {
    var entry: ContinueWatchingProvider.Entry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let primaryCard = entry.cards.first ?? WidgetMediaCard(title: "No active playback", subtitle: "Open ReelFin", progress: 0)

        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.11, blue: 0.18),
                    Color(red: 0.06, green: 0.08, blue: 0.13),
                    Color.black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.white.opacity(0.09))
                .frame(width: 120, height: 120)
                .offset(x: 90, y: -70)

            VStack(alignment: .leading, spacing: 8) {
                Label("Continue Watching", systemImage: "play.rectangle.fill")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))

                Text(primaryCard.title)
                    .font(.system(size: family == .systemSmall ? 14 : 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                Text(primaryCard.subtitle)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))

                ProgressView(value: primaryCard.progress)
                    .tint(.white)

                if family != .systemSmall, entry.cards.count > 1 {
                    Text("Up next: \(entry.cards[1].title)")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                }
            }
            .padding(12)
        }
        .containerBackground(for: .widget) {
            Color.clear
        }
    }
}

struct RecentlyAddedWidgetEntryView: View {
    var entry: RecentlyAddedProvider.Entry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [
                    Color(red: 0.14, green: 0.09, blue: 0.07),
                    Color(red: 0.08, green: 0.07, blue: 0.09),
                    Color.black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: 8) {
                Label("Recently Added", systemImage: "clock.arrow.circlepath")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.82))

                let items = Array(entry.cards.prefix(family == .systemSmall ? 2 : 3))
                ForEach(items, id: \.self) { card in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(.white.opacity(0.6))
                            .frame(width: 4, height: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(card.title)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Text(card.subtitle)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.7))
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(12)
        }
        .containerBackground(for: .widget) {
            Color.clear
        }
    }
}

struct ContinueWatchingWidget: Widget {
    let kind: String = "ContinueWatchingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ContinueWatchingProvider()) { entry in
            ContinueWatchingWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Continue Watching")
        .description("Resume your latest title instantly.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
    }
}

struct RecentlyAddedWidget: Widget {
    let kind: String = "RecentlyAddedWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RecentlyAddedProvider()) { entry in
            RecentlyAddedWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Recently Added")
        .description("See fresh movies and series at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

#if canImport(ActivityKit)
@available(iOS 16.1, *)
struct NowPlayingActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var title: String
        var currentTime: TimeInterval
        var duration: TimeInterval
    }

    var title: String
}

@available(iOSApplicationExtension 16.1, *)
struct NowPlayingActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NowPlayingActivityAttributes.self) { context in
            ZStack {
                LinearGradient(
                    colors: [Color.black, Color(red: 0.06, green: 0.09, blue: 0.14)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text(context.attributes.title)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                    ProgressView(value: context.state.currentTime, total: max(context.state.duration, 1))
                        .tint(.white)
                }
                .padding(12)
            }
            .foregroundStyle(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.title)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
            } compactLeading: {
                Image(systemName: "play.fill")
            } compactTrailing: {
                Text("\(Int(context.state.currentTime))s")
            } minimal: {
                Image(systemName: "play.fill")
            }
        }
    }
}
#endif

@main
struct ReelFinWidgetsBundle: WidgetBundle {
    @WidgetBundleBuilder
    var body: some Widget {
        ContinueWatchingWidget()
        RecentlyAddedWidget()
        #if canImport(ActivityKit)
        if #available(iOSApplicationExtension 16.1, *) {
            NowPlayingActivityWidget()
        }
        #endif
    }
}
