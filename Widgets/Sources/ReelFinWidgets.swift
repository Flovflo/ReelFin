import SwiftUI
import WidgetKit

#if canImport(ActivityKit)
import ActivityKit
#endif

struct ContinueWatchingEntry: TimelineEntry {
    let date: Date
    let title: String
    let subtitle: String
    let progress: Double
}

struct ContinueWatchingProvider: TimelineProvider {
    func placeholder(in context: Context) -> ContinueWatchingEntry {
        ContinueWatchingEntry(date: Date(), title: "Sample Title", subtitle: "Continue watching", progress: 0.42)
    }

    func getSnapshot(in context: Context, completion: @escaping (ContinueWatchingEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ContinueWatchingEntry>) -> Void) {
        let entry = ContinueWatchingEntry(date: Date(), title: "No active playback", subtitle: "Open ReelFin", progress: 0)
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(1800))))
    }
}

struct ContinueWatchingWidgetEntryView: View {
    var entry: ContinueWatchingProvider.Entry

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.17, green: 0.13, blue: 0.24), Color.black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: 8) {
                Text(entry.title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                Text(entry.subtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))

                ProgressView(value: entry.progress)
                    .tint(.red)
            }
            .padding(12)
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
        .description("Resume your latest title quickly.")
        .supportedFamilies([.systemSmall, .systemMedium])
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
            VStack(alignment: .leading, spacing: 8) {
                Text(context.attributes.title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                ProgressView(value: context.state.currentTime, total: max(context.state.duration, 1))
            }
            .padding(12)
            .background(Color.black)
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
        #if canImport(ActivityKit)
        if #available(iOSApplicationExtension 16.1, *) {
            NowPlayingActivityWidget()
        }
        #endif
    }
}
