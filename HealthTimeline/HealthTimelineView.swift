import Charts
import SwiftUI

enum RhythmStyle {
    static func tone(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }

    // A barely tinted page; blocks on it are white and slightly see-through.
    static let canvas = tone(0xF8F6FF, 0x0B0A10)
    static let canvasMid = tone(0xEFF7FF, 0x0A0F14)
    static let canvasEnd = tone(0xFFF5EE, 0x120C0B)
    static let surface = tone(0xFFFFFF, 0x1E1D24)
    static let track = Color.primary.opacity(0.06)
    static let accent = tone(0x8B5CF6, 0xA78BFA)
    static let grid = Color.primary.opacity(0.07)
    static let divider = Color.primary.opacity(0.14)
    static let rule = Color.primary.opacity(0.16)
    static let axisLabelWidth: CGFloat = 30
    static let cardRadius: CGFloat = 26
    /// A faint see-through tint, so blocks read as panels without leaving the white page.
    static let card = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: 0.07) : UIColor(white: 1, alpha: 0.82)
    })
    static let cardEdge = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: 0.08) : UIColor(white: 1, alpha: 1)
    })

    // Candy palette: lime, sky, tangerine, pink, violet
    static let readingBlue = tone(0x0EA5E9, 0x38BDF8)
    static let heart = tone(0xEC4899, 0xF472B6)
    static let hrvTone = tone(0x0EA5E9, 0x38BDF8)
    static let activity = tone(0xF97316, 0xFB923C)
    static let sleep = tone(0x8B5CF6, 0xA78BFA)
    static let rem = tone(0xD946EF, 0xE879F9)
    static let sage = tone(0x84CC16, 0xA3E635)
    static let straw = tone(0xFACC15, 0xFDE047)
    static let ochre = tone(0xF97316, 0xFB923C)
    static let terracotta = tone(0xEC4899, 0xF472B6)

    // Type: monospaced throughout, like an instrument readout
    static func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
    static let sectionTitle = Font.footnote.weight(.semibold)
    static let kicker = Font.caption.weight(.semibold)
}

/// The app's only animation curves, so every screen moves the same way.
enum RhythmMotion {
    /// A finger down on a row, tile or cell.
    static let press = Animation.snappy(duration: 0.15)
    /// Changing a selection: tabs, switches, bars, days, metrics.
    static let select = Animation.snappy(duration: 0.28)
    /// Scrolling to a section.
    static let scroll = Animation.snappy(duration: 0.4)
    /// A block appearing for the first time.
    static let reveal = Animation.easeOut(duration: 0.45)
    /// Custom bars and the dial drawing in.
    static let grow = Animation.spring(duration: 0.9, bounce: 0.18)
}

private enum TimelinePeriod: CaseIterable {
    case day, week, month, year

    var title: LocalizedStringKey {
        switch self {
        case .day: "Day"
        case .week: "Week"
        case .month: "Month"
        case .year: "Year"
        }
    }

    var component: Calendar.Component {
        switch self {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        case .year: .year
        }
    }

    var bucketSize: DateComponents {
        self == .year ? DateComponents(month: 1) : DateComponents(day: 1)
    }

    /// Debug builds can open on another period with `-rhythmDebugPeriod week|month|calendar|year`.
    static var initial: TimelinePeriod {
        #if DEBUG
        switch UserDefaults.standard.string(forKey: "rhythmDebugPeriod") {
        case "week": return .week
        case "month", "calendar": return .month
        case "year": return .year
        default: return .day
        }
        #else
        return .day
        #endif
    }
}

struct HealthTimelineView: View {
    private enum ScrollTarget { case top }
    private enum AnalysisSectionID: Hashable { case training(DateInterval), recovery(DateInterval), trends(DateInterval) }

    private struct LoadKey: Equatable {
        let interval: DateInterval?
        let period: TimelinePeriod
        let active: Bool
        let connected: Bool
    }

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.calendar) private var calendar
    @AppStorage("didRequestHealthAccess") private var didRequestAccess = false
    @State private var health = HealthStore()
    /// Debug builds can open on an earlier day with `-rhythmDebugDaysAgo 1`; the key is never set otherwise.
    @State private var selectedDate = Date().addingTimeInterval(-86400 * UserDefaults.standard.double(forKey: "rhythmDebugDaysAgo"))
    @State private var todayJump = 0
    @State private var refreshTick = 0
    @State private var period = TimelinePeriod.initial
    @State private var monthLayout = UserDefaults.standard.string(forKey: "rhythmDebugPeriod") == "calendar"
        ? MonthLayout.calendar : MonthLayout.charts
    @State private var calendarMetric = HeartMetric.hrvScore
    @State private var analysis = AnalysisTab.initial
    @State private var report: DayReport?
    @State private var trends: TrendReport?
    @State private var recovery: RecoveryReport?
    @State private var training: TrainingReport?
    @State private var refreshID: UUID?
    @State private var authorizing = false
    @State private var authorizationError = false
    @Binding var language: RhythmLanguage
    @Binding var appearance: RhythmAppearance
    @State private var showingSettings = false
    @State private var showingDatePicker = false
    @State private var showingPressureGuide = false
    @State private var historyMetric: HeartHistoryMetric?
    @State private var cache = ReportCache()
    @State private var prefetchTask: Task<Void, Never>?
    /// A day-view section to scroll to after opening a day ("workouts").
    @State private var pendingFocus: String?
    #if DEBUG
    @State private var debugWorkout: HealthInterval?
    #endif

    private var selectedInterval: DateInterval? { calendar.dateInterval(of: period.component, for: selectedDate) }

    var body: some View {
        NavigationStack {
            Group {
                if !health.isAvailable {
                    ContentUnavailableView(
                        "Apple Health Unavailable", systemImage: "heart.slash",
                        description: Text("Open Rhythm Log on an iPhone that supports Apple Health.")
                    )
                } else if !didRequestAccess {
                    WelcomeView(authorizing: authorizing, connect: connect)
                } else {
                    dayScreen
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RhythmBackdrop().ignoresSafeArea())
            .navigationTitle(Text(verbatim: "Rhythm Log"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if didRequestAccess && health.isAvailable {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Today", action: goToToday)
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text(verbatim: "RHYTHM LOG")
                        .font(.footnote.weight(.bold))
                        .tracking(1.6)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
            .sheet(item: $historyMetric) { metric in
                HeartHistorySheet(metric: metric, endingOn: selectedDate, health: health)
            }
            #if DEBUG
            // `-rhythmDebugWorkout YES` opens the day's first workout, for simulator screenshots.
            .sheet(item: $debugWorkout) { workout in
                NavigationStack { WorkoutDetailView(workout: workout, health: health) }
            }
            .onChange(of: report?.workouts.first?.id) { _, id in
                if id != nil, debugWorkout == nil, UserDefaults.standard.bool(forKey: "rhythmDebugWorkout") {
                    debugWorkout = report?.workouts.first
                }
            }
            #endif
            .sheet(isPresented: $showingPressureGuide) {
                PressureGuide()
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showingSettings) {
                RhythmSettings(language: $language, appearance: $appearance, updateHealthAccess: connect, authorizing: authorizing)
            }
            // A light tap when a sheet opens or closes.
            .sensoryFeedback(.impact(weight: .light), trigger: showingSettings)
            .sensoryFeedback(.impact(weight: .light), trigger: showingPressureGuide)
            .sensoryFeedback(.impact(weight: .light), trigger: historyMetric)
            .sensoryFeedback(.impact(weight: .light), trigger: showingDatePicker)
            .sheet(isPresented: $showingDatePicker) {
                NavigationStack {
                    DatePicker("Date", selection: $selectedDate, in: ...Date(), displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .padding(.horizontal)
                        .frame(maxWidth: 450)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .navigationTitle("Choose Date")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("Today") {
                                    goToToday()
                                    showingDatePicker = false
                                }
                            }
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showingDatePicker = false }
                            }
                        }
                }
                .tint(RhythmStyle.accent)
                .presentationDetents([.height(560), .large])
            }
            .task(id: LoadKey(interval: selectedInterval, period: period, active: scenePhase == .active, connected: didRequestAccess)) {
                await reload()
            }
            .alert("Couldn’t Request Health Data Access", isPresented: $authorizationError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Try again later or check this app’s permissions from your profile in Apple Health.")
            }

        }
        .tint(RhythmStyle.accent)
        .environment(\.openWorkoutDay) { date in showDay(date, focus: "workouts") }
    }

    private var dayScreen: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    RhythmTabs("Time Range", selection: $period, choices: TimelinePeriod.allCases) { $0.title }
                        .id(ScrollTarget.top)

                    dateControls

                    if period == .day, let report, report.day == selectedInterval {
                        DayDetails(report: report, health: health, showPressureGuide: { showingPressureGuide = true },
                                   showHistory: { historyMetric = $0 },
                                   jump: { target in
                                       withAnimation(RhythmMotion.scroll) { proxy.scrollTo(target, anchor: .top) }
                                   })
                            .id(report.day)
                            .onAppear {
                                // Arriving from a training calendar: scroll to that day's workouts.
                                guard let focus = pendingFocus else { return }
                                pendingFocus = nil
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                                    withAnimation(RhythmMotion.scroll) { proxy.scrollTo(focus, anchor: .top) }
                                }
                            }
                    } else if period != .day, let trends, trends.interval == selectedInterval {
                        if period == .year {
                            TrendDetails(report: trends, period: period, openDay: openDay)
                        } else {
                            // One row: what to look at (left), how to show it (right, month only).
                            AnalysisBar(analysis: $analysis, layout: $monthLayout, showsLayout: period == .month)
                            if period == .month && monthLayout == .calendar {
                                if analysis == .training {
                                    if let training, training.interval == selectedInterval {
                                        TrainingCalendar(month: trends.interval, workouts: training.workouts,
                                                         selectedDate: selectedDate) { date in
                                            showDay(date, focus: "workouts")
                                        }
                                    } else {
                                        ProgressView("Loading Workouts")
                                            .frame(maxWidth: .infinity, minHeight: 100)
                                    }
                                } else {
                                    MonthCalendar(report: trends, selectedDate: selectedDate, metric: $calendarMetric,
                                                  openDay: openDay)
                                }
                            } else if analysis == .training {
                                if let training, training.interval == selectedInterval {
                                    TrainingView(report: training, health: health).id(AnalysisSectionID.training(training.interval))
                                } else {
                                    ProgressView("Loading Workouts")
                                        .frame(maxWidth: .infinity, minHeight: 100)
                                }
                            } else {
                                if let recovery, recovery.interval == selectedInterval {
                                    SleepRecoveryView(report: recovery, openDay: openDay)
                                        .id(AnalysisSectionID.recovery(recovery.interval))
                                } else {
                                    ProgressView("Loading Recovery")
                                        .frame(maxWidth: .infinity, minHeight: 100)
                                }
                                TrendDetails(report: trends, period: period, openDay: openDay)
                                    .id(AnalysisSectionID.trends(trends.interval))
                            }
                        }
                    } else {
                        ProgressView("Loading Health Data")
                            .frame(maxWidth: .infinity, minHeight: 160)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
            .refreshable {
                await health.clearCache()
                cache.clear()
                await reload(force: true)
                refreshTick += 1
            }
            // Haptics: a tick when the date changes, a soft confirmation when a pull-to-refresh finishes.
            .sensoryFeedback(.selection, trigger: selectedDate)
            .sensoryFeedback(.success, trigger: refreshTick)
            .id(period)
            .onChange(of: todayJump) { _, _ in
                proxy.scrollTo(ScrollTarget.top, anchor: .top)
            }
            .onChange(of: pendingFocus) { _, focus in
                // Already on that day: scroll now instead of waiting for the day to load.
                guard let focus, period == .day, report?.day == selectedInterval else { return }
                pendingFocus = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    withAnimation(RhythmMotion.scroll) { proxy.scrollTo(focus, anchor: .top) }
                }
            }
            #if DEBUG
            .task {
                guard let target = UserDefaults.standard.string(forKey: "rhythmDebugScroll") else { return }
                try? await Task.sleep(for: .seconds(1.5))
                proxy.scrollTo(target, anchor: .top)
            }
            #endif
        }
    }

    private var dateControls: some View {
        HStack(spacing: 8) {
            periodButton(-1)

            Button {
                showingDatePicker = true
            } label: {
                VStack(spacing: 2) {
                    if period == .day {
                        Text(selectedDate, format: .dateTime.weekday(.wide))
                            .font(.caption.weight(.medium))
                            .textCase(.uppercase)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 6) {
                        dateHeading
                            .font(.headline)
                            .textCase(.uppercase)
                            .multilineTextAlignment(.center)
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(RhythmStyle.accent)
                            .accessibilityHidden(true)
                    }
                }
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, minHeight: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the date picker")

            periodButton(1)
                .disabled(selectedInterval?.contains(Date()) != false)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private var dateHeading: some View {
        switch period {
        case .day:
            Text(selectedDate, format: .dateTime.month(.wide).day().year())
        case .week:
            if let interval = selectedInterval {
                Text(interval.start..<interval.end.addingTimeInterval(-1), format: .interval.month(.abbreviated).day())
            }
        case .month:
            Text(selectedDate, format: .dateTime.month(.wide).year())
        case .year:
            Text(selectedDate, format: .dateTime.year())
        }
    }

    private func periodButton(_ direction: Int) -> some View {
        let previous = direction < 0
        return Button {
            movePeriod(by: direction)
        } label: {
            Image(systemName: previous ? "chevron.backward" : "chevron.forward")
                .font(.footnote.weight(.semibold))
                .frame(width: 22, height: 22)
        }
        .rhythmGlassButton()
        .accessibilityLabel(period == .day
            ? Text(previous ? "Previous Day" : "Next Day")
            : Text(previous ? "Previous Period" : "Next Period"))
    }

    private func openDay(_ date: Date) {
        withAnimation(RhythmMotion.select) {
            selectedDate = date
            period = .day
        }
    }

    /// Opens a day and scrolls to one of its sections once it has loaded.
    private func showDay(_ date: Date, focus: String) {
        pendingFocus = focus
        openDay(date)
    }

    private func goToToday() {
        selectedDate = Date()
        todayJump += 1
    }

    private func movePeriod(by amount: Int) {
        guard let start = selectedInterval?.start,
              let next = calendar.date(byAdding: period.component, value: amount, to: start) else { return }
        selectedDate = min(next, Date())
    }

    private func connect() {
        authorizing = true
        Task {
            defer { authorizing = false }
            do {
                try await health.requestReadAccess()
                didRequestAccess = true
                await reload()
            } catch {
                authorizationError = true
            }
        }
    }

    private func reload(force: Bool = false) async {
        guard health.isAvailable, didRequestAccess, scenePhase == .active, let interval = selectedInterval else { return }
        let requestedPeriod = period
        let id = UUID()
        refreshID = id
        prefetchTask?.cancel()
        func current() -> Bool {
            !Task.isCancelled && refreshID == id && period == requestedPeriod && selectedInterval == interval
        }

        if requestedPeriod == .day {
            // Show what's cached at once; read again only if it's stale.
            if let cached = cache.days[interval] {
                report = cached.value
                if !force && cached.isFresh(for: interval) { prefetch(around: interval, period: .day); return }
            }
            let next = await health.readDay(interval, calendar: calendar)
            cache.days[interval] = .init(next)
            guard current() else { return }
            report = next
        } else {
            let cachedTrends = cache.trends[interval]
            let cachedTraining = cache.training[interval]
            let cachedRecovery = cache.recovery[interval]
            if let cachedTrends { trends = cachedTrends.value }
            if let cachedTraining { training = cachedTraining.value }
            if let cachedRecovery { recovery = cachedRecovery.value }
            let needsSide = requestedPeriod != .year
            if !force, cachedTrends?.isFresh(for: interval) == true,
               !needsSide || (cachedTraining?.isFresh(for: interval) == true && cachedRecovery?.isFresh(for: interval) == true) {
                prefetch(around: interval, period: requestedPeriod)
                return
            }

            async let nextTrends = health.readTrends(interval, by: requestedPeriod.bucketSize, calendar: calendar)
            async let nextRecovery = needsSide ? health.readRecovery(interval, calendar: calendar) : nil
            async let nextTraining = needsSide ? health.readTraining(interval, calendar: calendar) : nil
            let next = await nextTrends
            cache.trends[interval] = .init(next)
            guard current() else { return }
            trends = next
            if let updatedTraining = await nextTraining {
                cache.training[interval] = .init(updatedTraining)
                guard current() else { return }
                training = updatedTraining
            }
            if let updatedRecovery = await nextRecovery {
                // Sleep, HRV and resting heart rate first; the overnight vitals follow.
                guard current() else { return }
                if cachedRecovery == nil { recovery = updatedRecovery }
                let complete = await health.readRecoveryVitals(updatedRecovery, calendar: calendar)
                cache.recovery[interval] = .init(complete)
                guard current() else { return }
                recovery = complete
            }
        }
        prefetch(around: interval, period: requestedPeriod)
    }

    /// Reads likely next screens into the cache in the background: the period before this one, and from a
    /// day, its week and month (Training and Recovery are one tap away).
    private func prefetch(around interval: DateInterval, period: TimelinePeriod) {
        prefetchTask?.cancel()
        prefetchTask = Task(priority: .utility) {
            try? await Task.sleep(for: .milliseconds(600))
            var targets: [(DateInterval, TimelinePeriod)] = []
            if let earlier = calendar.date(byAdding: period.component, value: -1, to: interval.start),
               let previous = calendar.dateInterval(of: period.component, for: earlier) {
                targets.append((previous, period))
            }
            if period == .day {
                for wider in [TimelinePeriod.week, .month] {
                    if let range = calendar.dateInterval(of: wider.component, for: interval.start) {
                        targets.append((range, wider))
                    }
                }
            }
            for (range, kind) in targets {
                guard !Task.isCancelled else { return }
                await warm(range, period: kind)
            }
        }
    }

    private func warm(_ interval: DateInterval, period: TimelinePeriod) async {
        if period == .day {
            guard cache.days[interval] == nil else { return }
            let report = await health.readDay(interval, calendar: calendar)
            cache.days[interval] = .init(report)
            return
        }
        if cache.trends[interval] == nil {
            let next = await health.readTrends(interval, by: period.bucketSize, calendar: calendar)
            cache.trends[interval] = .init(next)
        }
        guard period != .year, !Task.isCancelled else { return }
        if cache.training[interval] == nil {
            let next = await health.readTraining(interval, calendar: calendar)
            cache.training[interval] = .init(next)
        }
        guard !Task.isCancelled else { return }
        if cache.recovery[interval] == nil {
            let base = await health.readRecovery(interval, calendar: calendar)
            let next = await health.readRecoveryVitals(base, calendar: calendar)
            cache.recovery[interval] = .init(next)
        }
    }
}

/// Reports already read this session, so returning to a day or month shows instantly.
@MainActor private final class ReportCache {
    struct Entry<Value> {
        let value: Value
        let time = Date()

        init(_ value: Value) { self.value = value }

        /// Past periods stay fresh for 30 minutes; anything that includes today, for 2 minutes.
        func isFresh(for interval: DateInterval) -> Bool {
            let age = Date().timeIntervalSince(time)
            return interval.end <= Date() ? age < 30 * 60 : age < 2 * 60
        }
    }

    var days: [DateInterval: Entry<DayReport>] = [:]
    var trends: [DateInterval: Entry<TrendReport>] = [:]
    var training: [DateInterval: Entry<TrainingReport>] = [:]
    var recovery: [DateInterval: Entry<RecoveryReport>] = [:]

    func clear() {
        days = [:]
        trends = [:]
        training = [:]
        recovery = [:]
    }
}

private struct WelcomeView: View {
    let authorizing: Bool
    let connect: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(RhythmStyle.accent)
                    .frame(width: 66, height: 66)
                    .background(RhythmStyle.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 22))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 9) {
                    Text("Get to know your rhythm")
                        .font(.largeTitle.weight(.bold))
                        .accessibilityAddTraits(.isHeader)
                    Text("See how your heart readings, training, and daily activity change over time.")
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 17) {
                    feature("Day timeline", detail: "See heart readings, workouts, and steps in the context of your day.",
                            icon: "clock", color: RhythmStyle.readingBlue)
                    feature("Training patterns", detail: "Compare weekly minutes, heart rate zones, and workouts at similar paces.",
                            icon: "figure.run", color: RhythmStyle.activity)
                    feature("Recovery, with or without sleep", detail: "Start with daytime HRV and resting heart rate. Overnight charts appear when records are available.",
                            icon: "heart.text.clipboard", color: RhythmStyle.sleep)
                }
                .rhythmCard()
                VStack(alignment: .leading, spacing: 14) {
                    Label("Choose what to share. Rhythm Log reads Apple Health records on this iPhone.", systemImage: "lock.shield")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button(action: connect) {
                        if authorizing {
                            ProgressView().frame(maxWidth: .infinity, minHeight: 50)
                                .accessibilityLabel("Connecting to Apple Health")
                        } else {
                            Text("Connect Apple Health")
                                .font(.headline)
                                .frame(maxWidth: .infinity, minHeight: 50)
                        }
                    }
                    .rhythmProminentButton()
                    .buttonBorderShape(.capsule)
                    .disabled(authorizing)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
    }

    private func feature(_ title: LocalizedStringKey, detail: LocalizedStringKey, icon: String, color: Color) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: icon).foregroundStyle(color)
        }
        .accessibilityElement(children: .combine)
    }
}

/// One quiet control rather than a row of buttons. The main switcher is a single soft track with a
/// light thumb; `quiet` renders a secondary choice as plain words, so it never competes with the main one.
private struct RhythmTabs<Selection: Hashable>: View {
    let title: LocalizedStringKey
    @Binding var selection: Selection
    let choices: [Selection]
    let quiet: Bool
    var alignment: Alignment = .trailing
    let label: (Selection) -> LocalizedStringKey
    @Namespace private var thumb

    init(
        _ title: LocalizedStringKey, selection: Binding<Selection>, choices: [Selection], quiet: Bool = false,
        alignment: Alignment = .trailing, label: @escaping (Selection) -> LocalizedStringKey
    ) {
        self.title = title
        _selection = selection
        self.choices = choices
        self.quiet = quiet
        self.alignment = alignment
        self.label = label
    }

    var body: some View {
        Group {
            if quiet { words } else { track }
        }
        .sensoryFeedback(.selection, trigger: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(title))
    }

    private var track: some View {
        HStack(spacing: 0) {
            ForEach(choices, id: \.self) { choice in
                let active = choice == selection
                Button {
                    withAnimation(RhythmMotion.select) { selection = choice }
                } label: {
                    Text(label(choice))
                        .font(.caption.weight(active ? .semibold : .regular))
                        .textCase(.uppercase)
                        .tracking(0.6)
                        .foregroundStyle(active ? .primary : .secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background {
                            if active { thumbShape }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
        .padding(3)
        .background(RhythmStyle.track, in: Capsule())
    }

    /// The selected segment is Liquid Glass on iOS 26 and later, a plain white capsule before that.
    @ViewBuilder private var thumbShape: some View {
        if #available(iOS 26.0, *) {
            Capsule()
                .fill(.clear)
                .glassEffect(.regular.interactive(), in: .capsule)
                .matchedGeometryEffect(id: "thumb", in: thumb)
        } else {
            Capsule()
                .fill(RhythmStyle.surface)
                .shadow(color: .black.opacity(0.07), radius: 2, y: 1)
                .matchedGeometryEffect(id: "thumb", in: thumb)
        }
    }

    private var words: some View {
        HStack(spacing: 18) {
            ForEach(choices, id: \.self) { choice in
                let active = choice == selection
                Button {
                    withAnimation(RhythmMotion.select) { selection = choice }
                } label: {
                    Text(label(choice))
                        .font(.caption.weight(active ? .semibold : .regular))
                        .textCase(.uppercase)
                        .tracking(0.6)
                        .foregroundStyle(active ? .primary : .tertiary)
                        .frame(minHeight: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment)
        .padding(.horizontal, alignment == .leading ? 4 : 18)
    }
}

/// Week and Month controls in one row: Training | Recovery on the left, and on Month a small
/// chart/calendar switch on the right.
private struct AnalysisBar: View {
    @Binding var analysis: AnalysisTab
    @Binding var layout: MonthLayout
    let showsLayout: Bool

    var body: some View {
        HStack(spacing: 12) {
            RhythmTabs("Analysis", selection: $analysis, choices: AnalysisTab.allCases, quiet: true,
                       alignment: .leading) { $0.title }
            if showsLayout {
                LayoutSwitch(selection: $layout)
            }
        }
    }
}

/// Two icons in a small track, same thumb as the main period switcher.
private struct LayoutSwitch: View {
    @Binding var selection: MonthLayout
    @Namespace private var thumb

    var body: some View {
        HStack(spacing: 0) {
            ForEach([MonthLayout.charts, .calendar], id: \.self) { option in
                let active = option == selection
                Button {
                    withAnimation(RhythmMotion.select) { selection = option }
                } label: {
                    Image(systemName: option == .charts ? "chart.bar.xaxis" : "calendar")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(active ? .primary : .secondary)
                        .frame(width: 40, height: 30)
                        .background {
                            if active {
                                Capsule()
                                    .fill(RhythmStyle.surface)
                                    .shadow(color: .black.opacity(0.07), radius: 2, y: 1)
                                    .matchedGeometryEffect(id: "layoutThumb", in: thumb)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option == .charts ? Text("Charts") : Text("Calendar"))
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
        .padding(3)
        .background(RhythmStyle.track, in: Capsule())
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// The page behind every screen: a faint lilac-to-sky-to-peach wash that shows through the blocks.
private struct RhythmBackdrop: View {
    var body: some View {
        LinearGradient(colors: [RhythmStyle.canvas, RhythmStyle.canvasMid, RhythmStyle.canvasEnd],
                       startPoint: .top, endPoint: .bottom)
    }
}

/// Blocks fade and rise slightly the first time they come on screen. Skipped when Reduce Motion is on.
private struct CardReveal: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 14)
            .onAppear {
                withAnimation(RhythmMotion.reveal) { shown = true }
            }
    }
}

/// The rounded block behind every section. See-through by default, solid when Reduce Transparency is on.
private struct CardSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: RhythmStyle.cardRadius, style: .continuous)
        content
            .background(reduceTransparency ? RhythmStyle.surface : RhythmStyle.card, in: shape)
            .overlay { shape.strokeBorder(RhythmStyle.cardEdge).allowsHitTesting(false) }
            .modifier(CardReveal())
    }
}

/// Rows and tiles dip slightly while pressed.
private struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.5 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(RhythmMotion.press, value: configuration.isPressed)
    }
}

private struct HorizontalLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

private struct DashedRule: View {
    var body: some View {
        HorizontalLine()
            .stroke(RhythmStyle.rule, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

private struct DialRay {
    let hour: Int
    /// 0 to 1
    let length: Double
    let color: Color
}

private struct DialArc {
    /// Hours from the start of the day
    let start: Double
    let end: Double
    let color: Color
}

/// A 24-hour clock face: one ray per hour, arcs for spans such as sleep, and a dot for the current time.
private struct DayDial: View, Animatable {
    let rays: [DialRay]
    var arcs: [DialArc] = []
    var now: Double? = nil
    /// 0 to 1. Rays sweep in clockwise as this rises.
    var progress: Double = 1
    var selected: Int? = nil

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    private func angle(_ hour: Double) -> Double { hour / 24 * 2 * .pi - .pi / 2 }

    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let inner = side * 0.27
            let reach = side * 0.14
            let width = side * 0.026
            func point(_ hour: Double, _ radius: CGFloat) -> CGPoint {
                let a = angle(hour)
                return CGPoint(x: center.x + radius * CGFloat(cos(a)), y: center.y + radius * CGFloat(sin(a)))
            }
            let values = Dictionary(rays.map { ($0.hour, $0) }, uniquingKeysWith: { first, _ in first })
            for hour in 0..<24 {
                let mid = Double(hour) + 0.5
                var path = Path()
                path.move(to: point(mid, inner))
                if let ray = values[hour] {
                    let grown = min(max(progress * 1.7 - Double(hour) / 24 * 0.7, 0), 1)
                    let length = reach * CGFloat(0.14 + 0.86 * min(max(ray.length, 0), 1)) * CGFloat(grown)
                    let dimmed = selected != nil && selected != hour
                    path.addLine(to: point(mid, inner + length))
                    context.stroke(path, with: .color(ray.color.opacity(dimmed ? 0.22 : 1)),
                                   style: StrokeStyle(lineWidth: selected == hour ? width * 1.4 : width, lineCap: .round))
                } else {
                    path.addLine(to: point(mid, inner + side * 0.012))
                    context.stroke(path, with: .color(RhythmStyle.rule), style: StrokeStyle(lineWidth: width, lineCap: .round))
                }
            }
            for arc in arcs where arc.end > arc.start {
                var path = Path()
                path.addArc(center: center, radius: inner - side * 0.05,
                            startAngle: .radians(angle(arc.start)),
                            endAngle: .radians(angle(arc.start + (arc.end - arc.start) * min(progress * 1.3, 1))),
                            clockwise: false)
                context.stroke(path, with: .color(arc.color), style: StrokeStyle(lineWidth: side * 0.03, lineCap: .round))
            }
            if let now {
                var hand = Path()
                hand.move(to: point(now, inner - side * 0.02))
                hand.addLine(to: point(now, inner + reach + side * 0.02))
                context.stroke(hand, with: .color(.primary), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
                let dot = point(now, inner + reach + side * 0.02)
                context.fill(Path(ellipseIn: CGRect(x: dot.x - 4, y: dot.y - 4, width: 8, height: 8)), with: .color(.primary))
            }
            for hour in [0, 6, 12, 18] {
                let label = Text(verbatim: String(format: "%02d", hour))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                context.draw(label, at: point(Double(hour), inner + reach + side * 0.05))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

private struct StatRow: View {
    let title: LocalizedStringKey
    let color: Color
    let value: String?
    var unit: String? = nil
    var showsRule = true
    /// When set, the row is a button and shows a chevron.
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            if showsRule { DashedRule() }
            if let action {
                Button(action: action) { row }
                    .buttonStyle(PressableStyle())
            } else {
                row
            }
        }
    }

    private var row: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(title)
                .font(.footnote.weight(.medium))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(verbatim: value ?? "—")
                .font(.body.weight(.semibold))
                .monospacedDigit()
            if let unit, value != nil {
                Text(verbatim: unit)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if action != nil {
                Image(systemName: "chevron.forward")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}

private struct RhythmSettings: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var language: RhythmLanguage
    @Binding var appearance: RhythmAppearance
    let updateHealthAccess: () -> Void
    let authorizing: Bool

    var body: some View {
        NavigationStack {
            List {
                Section("Language") {
                    Picker("App Language", selection: $language) {
                        Text("Follow System").tag(RhythmLanguage.system)
                        Text(verbatim: "English").tag(RhythmLanguage.english)
                        Text(verbatim: "简体中文").tag(RhythmLanguage.simplifiedChinese)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section("Display") {
                    Picker("Appearance", selection: $appearance) {
                        ForEach(RhythmAppearance.allCases, id: \.self) { option in
                            Text(option.title).tag(option)
                        }
                    }
                }

                Section("Training") {
                    NavigationLink("Manual Heart Rate Zones") {
                        ManualWorkoutZonesSettings()
                    }
                }

                Section("Health Data Access") {
                    Button("Update Apple Health Access", action: updateHealthAccess)
                        .disabled(authorizing)
                    Label {
                        Text("In Apple Health, tap your profile picture, then choose Apps under Privacy. Select Rhythm Log to review or change access.")
                            .font(.footnote)
                    } icon: {
                        Image(systemName: "heart.text.clipboard")
                            .foregroundStyle(RhythmStyle.accent)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(RhythmBackdrop().ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(RhythmStyle.accent)
        .preferredColorScheme(appearance.scheme)
    }
}

private struct ManualWorkoutZonesSettings: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("rhythmManualWorkoutZones") private var saved = ""
    @State private var boundaries = Array(repeating: "", count: 4)

    private var entry: String { boundaries.joined(separator: ",") }
    private var canSave: Bool { WorkoutHeartRateZones(manualBoundaries: entry) != nil }

    var body: some View {
        List {
            Section {
                ForEach(boundaries.indices, id: \.self) { index in
                    HStack {
                        Text("Zone \(index + 2) starts at")
                        TextField("BPM", text: $boundaries[index])
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .accessibilityLabel(Text("Zone \(index + 2) starts at"))
                    }
                }
            } header: {
                Text("Lower limits")
            } footer: {
                Text("Enter four increasing BPM limits. Zone 1 starts below the first limit. These limits are used when Apple Health has no zones available.")
            }

            Section {
                Button("Save Zones") {
                    saved = entry
                    dismiss()
                }
                .disabled(!canSave)

                if !saved.isEmpty {
                    Button("Clear Manual Zones") {
                        saved = ""
                        dismiss()
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(RhythmBackdrop().ignoresSafeArea())
        .navigationTitle("Manual Heart Rate Zones")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            let parts = saved.split(separator: ",", omittingEmptySubsequences: false)
            if parts.count == 4 { boundaries = parts.map(String.init) }
        }
    }
}

private struct DayDetails: View {
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @AppStorage("rhythmManualWorkoutZones") private var manualZones = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dialProgress = 0.0
    @State private var selectedHour: Int?
    /// True only while a finger is held on the dial; the hour detail clears when it lifts.
    @GestureState private var holdingDial = false
    let report: DayReport
    let health: HealthStore
    let showPressureGuide: () -> Void
    let showHistory: (HeartHistoryMetric) -> Void
    /// Scrolls the day view to a section: "sleep" or "steps".
    var jump: (String) -> Void = { _ in }

    var body: some View {
        UnavailableMetrics(names: report.unavailable)

        hero
        statRows
        overnightCard

        SectionCaption("Heart Readings").id("heart")

        ReadingChart(title: "HRV Through the Day", unit: "ms", color: RhythmStyle.readingBlue,
                     readings: report.hrv, range: report.day,
                     hrvAssessments: report.hrvAssessments, baseline: report.hrvBaseline, onInfo: showPressureGuide,
                     onHistory: { showHistory(.hrv) })
        ReadingChart(title: "Heart Rate", unit: "BPM", color: RhythmStyle.heart, readings: report.heartRate, range: report.day,
                     workouts: report.workouts, rawOnly: true)
            .id("hr")
        ReadingChart(title: "Resting Heart Rate", unit: "BPM", color: RhythmStyle.readingBlue,
                     readings: report.restingHeartRate, range: report.day, rawOnly: true,
                     onHistory: { showHistory(.restingHeartRate) })
        SectionCaption("Activity & Rest").id("activity")

        BucketChart(title: "Hourly Steps", unit: "steps", color: RhythmStyle.activity, buckets: report.steps,
                    interval: report.day, period: .day, rawOnly: true)
            .id("steps")
        if !report.sleep.isEmpty {
            sleepCard.id("sleep")
        }
        workoutCard.id("workouts")

        Text("Times use your iPhone’s current time zone. If readings are missing, check your records and this app’s permissions in Apple Health.")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    private var hero: some View {
        let score = report.dailyHRV?.score
        let focus = selectedHour.flatMap { hour in stressRays.first { $0.hour == hour } }
        let shown = focus.map { max(Int(($0.length * 100).rounded()), 1) } ?? score
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("Daily HRV Score")
                    .font(RhythmStyle.sectionTitle)
                    .textCase(.uppercase)
                    .tracking(0.8)
                    .accessibilityAddTraits(.isHeader)
                if calendar.isDateInToday(report.day.start) {
                    Text(verbatim: "·").foregroundStyle(.secondary)
                    Text("Today so far")
                        .font(.footnote)
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 6)
                Button(action: showPressureGuide) {
                    Image(systemName: "info.circle")
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Understanding Pressure")
            }

            DayDial(rays: stressRays, arcs: dialArcs, now: nowHour, progress: dialProgress, selected: selectedHour)
                .background {
                    // A faint glow of the level color behind the number.
                    if let shown {
                        GeometryReader { proxy in
                            let side = min(proxy.size.width, proxy.size.height)
                            RadialGradient(colors: [PressureBand(score: shown).color.opacity(0.16),
                                                    PressureBand(score: shown).color.opacity(0)],
                                           center: .center, startRadius: 0, endRadius: side * 0.3)
                                .opacity(dialProgress)
                                .animation(RhythmMotion.select, value: shown)
                        }
                        .accessibilityHidden(true)
                    }
                }
                .overlay {
                    VStack(spacing: 2) {
                        if let shown {
                            Text(PressureBand.percent(shown))
                                .font(RhythmStyle.display(40))
                                .monospacedDigit()
                                .fixedSize()
                                .foregroundStyle(PressureBand(score: shown).color)
                                .contentTransition(.numericText())
                            Text(PressureBand(score: shown).title)
                                .font(.caption.weight(.bold))
                                .textCase(.uppercase)
                                .tracking(1)
                                .foregroundStyle(PressureBand(score: shown).color)
                            if let selectedHour {
                                Text(verbatim: String(format: "%02d:00", selectedHour))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .transition(.opacity)
                            }
                        } else {
                            Text(verbatim: "—")
                                .font(RhythmStyle.display(40))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                .overlay {
                    GeometryReader { proxy in
                        Color.clear
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .updating($holdingDial) { _, state, _ in state = true }
                                    .onChanged { drag in selectHour(at: drag.location, in: proxy.size) }
                            )
                            .accessibilityHidden(true)
                    }
                }
                .frame(maxWidth: 330)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .sensoryFeedback(.selection, trigger: selectedHour)
                .onChange(of: holdingDial) { _, holding in
                    if !holding {
                        withAnimation(RhythmMotion.select) { selectedHour = nil }
                    }
                }
                .sensoryFeedback(.impact(weight: .light), trigger: dialProgress)
                .onAppear {
                    if reduceMotion {
                        dialProgress = 1
                    } else {
                        withAnimation(.spring(duration: 1.2, bounce: 0.25).delay(0.15)) { dialProgress = 1 }
                    }
                }

            VStack(spacing: 6) {
                PressureColorKey()
                HStack(spacing: 12) {
                    if !report.sleep.isEmpty { ColorKeyItem(color: RhythmStyle.sleep, title: "Sleep") }
                    if !report.workouts.isEmpty { ColorKeyItem(color: RhythmStyle.activity, title: "Workout") }
                }
            }
            .frame(maxWidth: .infinity)

            if let summary = report.dailyHRV, summary.score != nil {
                VStack(alignment: .leading, spacing: 8) {
                    scoreLede(summary)
                    ScoreEvidence(summary: summary)
                }
                .padding(.top, 16)
            } else {
                Text(dailyScoreUnavailableReason)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 16)
            }
        }
        .rhythmCard()
    }

    /// While held, the hour under the finger is shown; sliding round the dial moves between hours.
    private func selectHour(at location: CGPoint, in size: CGSize) {
        let dx = location.x - size.width / 2
        let dy = location.y - size.height / 2
        let scored = Set(stressRays.map(\.hour))
        var next: Int?
        if hypot(dx, dy) > min(size.width, size.height) * 0.2 {
            var turn = (atan2(dy, dx) + .pi / 2) / (2 * .pi)
            if turn < 0 { turn += 1 }
            let hour = min(Int(turn * 24), 23)
            next = [hour, hour - 1, hour + 1].first { scored.contains($0) }
        }
        guard next != selectedHour else { return }
        withAnimation(RhythmMotion.select) { selectedHour = next }
    }

    /// One ray per hour that has a pressure estimate, as the mean of that hour's estimates.
    private var stressRays: [DialRay] {
        var scores: [Int: [Int]] = [:]
        for reading in report.hrv {
            guard case let .score(value, _)? = report.hrvAssessments[reading.id] else { continue }
            let hour = Int(reading.time.timeIntervalSince(report.day.start) / 3600)
            scores[min(max(hour, 0), 23), default: []].append(value)
        }
        return scores.map { hour, values in
            let mean = max(values.reduce(0, +) / values.count, 1)
            return DialRay(hour: hour, length: Double(mean) / 100, color: PressureBand(score: mean).color)
        }
    }

    private var dialArcs: [DialArc] {
        func hours(_ date: Date) -> Double { date.timeIntervalSince(report.day.start) / 3600 }
        let sleep = report.sleep.compactMap { item -> DialArc? in
            guard let stage = item.sleepStage, stage != .inBed, stage != .awake,
                  let window = item.clipped(to: report.day) else { return nil }
            return DialArc(start: hours(window.start), end: hours(window.end), color: RhythmStyle.sleep)
        }
        let workouts = report.workouts.compactMap { item -> DialArc? in
            item.clipped(to: report.day).map {
                DialArc(start: hours($0.start), end: hours($0.end), color: RhythmStyle.activity)
            }
        }
        return sleep + workouts
    }

    private var nowHour: Double? {
        let now = Date()
        return report.day.contains(now) ? now.timeIntervalSince(report.day.start) / 3600 : nil
    }

    private var statRows: some View {
        let whole = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0)).locale(locale)
        let steps = report.steps.map(\.value).reduce(0, +)
        return VStack(spacing: 0) {
            StatRow(title: "HRV", color: RhythmStyle.hrvTone,
                    value: report.hrv.last.map { $0.value.formatted(whole) }, unit: "ms", showsRule: false,
                    action: { showHistory(.hrv) })
            StatRow(title: "Resting HR", color: RhythmStyle.heart,
                    value: report.restingHeartRate.last.map { $0.value.formatted(whole) }, unit: "BPM",
                    action: { showHistory(.restingHeartRate) })
            if !report.sleep.isEmpty {
                StatRow(title: "Sleep", color: RhythmStyle.sleep,
                        value: asleepSeconds > 0
                            ? Duration.seconds(asleepSeconds).formatted(.units(allowed: [.hours, .minutes], width: .narrow).locale(locale))
                            : nil,
                        action: { jump("sleep") })
            }
            StatRow(title: "Steps", color: RhythmStyle.activity,
                    value: report.steps.isEmpty ? nil : steps.formatted(whole),
                    action: { jump("steps") })
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 4)
        .modifier(CardSurface())
    }

    private func scoreValue(_ score: Int) -> some View {
        Text(PressureBand.percent(score))
            .font(RhythmStyle.display(60))
            .monospacedDigit()
    }

    private func scoreStatus(_ score: Int) -> some View {
        Text(PressureBand(score: score).title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(PressureBand(score: score).color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(PressureBand(score: score).color.opacity(0.14), in: Capsule())
    }

    @ViewBuilder private func scoreLede(_ summary: HRVDailyScore) -> some View {
        if case let .score(score, days) = summary.assessment {
            Text("Compared with your previous \(days) days, daytime HRV was lower than on about \(PressureBand.percent(score)) of them.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var asleepSeconds: Double {
        report.sleep.reduce(0.0) { total, item in
            guard let stage = item.sleepStage, stage != .inBed, stage != .awake, stage != .other,
                  let window = item.clipped(to: report.day) else { return total }
            return total + window.duration
        }
    }

    /// The hours that contain this date's sleep, so the stages fill the chart.
    private var sleepWindow: DateInterval {
        let windows = report.sleep.compactMap { $0.clipped(to: report.day) }
        guard let start = windows.map(\.start).min(), let end = windows.map(\.end).max(),
              let from = calendar.dateInterval(of: .hour, for: start)?.start,
              let to = calendar.dateInterval(of: .hour, for: end.addingTimeInterval(-1))?.end, from < to
        else { return report.day }
        return DateInterval(start: from, end: to)
    }

    private var overnightCard: some View {
        TimelineCard(title: "Overnight HRV", icon: "moon.stars", tint: RhythmStyle.sleep,
                     onInfo: showPressureGuide) {
            if let night = report.overnightHRV {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(night.samples.median, format: .number.precision(.fractionLength(0)))
                        .font(RhythmStyle.display(44))
                        .monospacedDigit()
                    Text(verbatim: "ms")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    if let score = night.score {
                        scoreStatus(score)
                    }
                }
                if let score = night.score {
                    PressureScale(score: score)
                }
                Text(night.assessment.description(in: locale))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("Median of \(night.samples.count) readings recorded during sleep")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(night.samples.source)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("No HRV readings recorded during sleep for this date.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var dailyScoreUnavailableReason: LocalizedStringKey {
        guard !report.hrv.isEmpty else { return "No HRV readings available for this date." }
        let readingsOutsideScoringWindow = report.hrv.allSatisfy { reading in
            switch report.hrvAssessments[reading.id] {
            case .outsideDaytime, .duringSleepOrWorkout: true
            default: false
            }
        }
        if readingsOutsideScoringWindow {
            return "HRV was recorded outside scoring hours or during sleep or a workout."
        }
        return "HRV was recorded. The data needed to calculate a daily score is unavailable."
    }

    private var sleepCard: some View {
        TimelineCard(title: "Sleep", icon: "moon.stars", tint: RhythmStyle.sleep) {
            if report.sleep.isEmpty {
                Text("No Sleep Records").font(.footnote).foregroundStyle(.secondary)
            } else {
                ValueHeader(
                    value: Duration.seconds(asleepSeconds)
                        .formatted(.units(allowed: [.hours, .minutes], width: .narrow).locale(locale)),
                    unit: "", caption: Text("Time Asleep")
                )
                activityTrack(report.sleep, color: RhythmStyle.sleep, stages: true)
                let stages = SleepStage.allCases.filter { stage in report.sleep.contains { $0.sleepStage == stage } }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), alignment: .leading)], spacing: 5) {
                    ForEach(stages, id: \.self) { stage in
                        ColorKeyItem(color: stage.color, title: stage.title)
                    }
                }
                DisclosureGroup("Sleep Details (\(report.sleep.count))") {
                    ForEach(report.sleep) { segment in
                        intervalRow(segment)
                    }
                }
            }
        }
    }

    private var workoutCard: some View {
        TimelineCard(title: "Workouts", icon: "figure.run", tint: RhythmStyle.activity) {
            if report.workouts.isEmpty {
                Text("No Workouts").font(.footnote).foregroundStyle(.secondary)
            } else {
                activityTrack(report.workouts, color: RhythmStyle.activity)
                ForEach(report.workouts) { workout in
                    NavigationLink {
                        workoutDetails(workout)
                    } label: {
                        WorkoutRow(workout: workout)
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
    }

    /// Vertical position, in points from the top of the plot, for an interval's bar.
    private static func trackBand(_ stage: SleepStage?, stages: Bool) -> (top: CGFloat, bottom: CGFloat) {
        guard stages, let stage else { return stage == .inBed ? (26, 33) : (8, 24) }
        switch stage {
        case .awake: return (4, 18)
        case .rem: return (24, 38)
        case .core, .asleep, .other: return (44, 58)
        case .deep: return (64, 78)
        case .inBed: return (86, 90)
        }
    }

    private func activityTrack(_ intervals: [HealthInterval], color: Color, stages: Bool = false) -> some View {
        Chart(intervals) { interval in
            if let window = interval.clipped(to: report.day) {
                let band = Self.trackBand(interval.sleepStage, stages: stages)
                RectangleMark(
                    xStart: .value(Text("Start"), window.start),
                    xEnd: .value(Text("End"), window.end),
                    yStart: band.top,
                    yEnd: band.bottom
                )
                .foregroundStyle((interval.sleepStage?.color ?? color).opacity(0.78))
                .cornerRadius(4)
                .accessibilityLabel(Text(interval.title))
                .accessibilityValue(Text(window.start..<window.end, format: .interval.hour().minute()))
            }
        }
        .dayAxis(stages ? sleepWindow : report.day, hourStride: stages && sleepWindow.duration <= 12 * 3600 ? 2 : 6)
        .chartYAxis(.hidden)
        .frame(height: stages ? 118 : 60)
    }

    private func intervalRow(_ interval: HealthInterval) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Circle().fill(interval.sleepStage?.color ?? RhythmStyle.activity)
                    .frame(width: 7, height: 7).accessibilityHidden(true)
                Text(interval.title).font(.subheadline.weight(.medium))
            }
            Group {
                Text(interval.start, format: .dateTime.month().day().hour().minute())
                + Text(" – ")
                + Text(interval.end, format: .dateTime.month().day().hour().minute())
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func workoutDetails(_ workout: HealthInterval) -> some View {
        let isWithinDay = workout.start >= report.day.start && workout.end <= report.day.end
        let readings = isWithinDay ? report.heartRate.filter { $0.time >= workout.start && $0.time < workout.end } : nil
        return WorkoutDetailView(workout: workout, health: health, readings: readings,
                                 preferredZones: report.preferredWorkoutZones)
    }
}

struct UnavailableMetrics: View {
    @Environment(\.locale) private var locale
    let names: [LocalizedStringResource]

    var body: some View {
        if !names.isEmpty {
            let list = names.map { $0.localized(in: locale) }.formatted(.list(type: .and).locale(locale))
            Label("Couldn’t load \(list). Pull down to retry.", systemImage: "exclamationmark.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

private struct TrendDetails: View {
    let report: TrendReport
    let period: TimelinePeriod
    var openDay: ((Date) -> Void)? = nil

    var body: some View {
        if period != .year {
            BucketChart(title: HeartMetric.hrvScore.title, unit: "%", color: .gray,
                        buckets: HeartMetric.hrvScore.buckets(in: report), interval: report.interval,
                        period: period, dailyScores: report.dailyHRV, openDay: openDay)
        }

        SectionCaption(period == .year ? "Monthly averages" : "Daily heart rate averages")

        UnavailableMetrics(names: report.unavailable)
        ForEach(HeartMetric.allCases.filter { $0 == .heartRate || (period == .year && $0 != .hrvScore) }, id: \.self) { metric in
            BucketChart(title: metric.title, unit: metric.unit, color: metric.color,
                        buckets: metric.buckets(in: report), interval: report.interval, period: period,
                        rawOnly: metric == .heartRate || metric == .restingHeartRate, openDay: openDay)
        }
    }
}

private enum AnalysisTab: CaseIterable {
    case training, recovery

    static var initial: Self {
        #if DEBUG
        if UserDefaults.standard.string(forKey: "rhythmDebugAnalysis") == "recovery" { return .recovery }
        #endif
        return .training
    }

    var title: LocalizedStringKey {
        switch self {
        case .training: "Training"
        case .recovery: "Recovery"
        }
    }
}

private enum MonthLayout: Hashable {
    case charts, calendar
}

private enum HeartMetric: CaseIterable {
    case hrvScore, heartRate, hrv, restingHeartRate

    var title: LocalizedStringKey {
        switch self {
        case .hrvScore: "Daily HRV Score"
        case .heartRate: "Heart Rate"
        case .hrv: "Heart Rate Variability (SDNN)"
        case .restingHeartRate: "Resting Heart Rate"
        }
    }

    var unit: LocalizedStringKey {
        switch self {
        case .hrvScore: "%"
        case .hrv: "ms"
        case .heartRate, .restingHeartRate: "BPM"
        }
    }

    var color: Color {
        switch self {
        case .hrvScore: .gray
        case .heartRate: RhythmStyle.heart
        case .hrv: RhythmStyle.hrvTone
        case .restingHeartRate: RhythmStyle.readingBlue
        }
    }

    func buckets(in report: TrendReport) -> [MetricBucket] {
        switch self {
        case .hrvScore: report.dailyHRV.values.compactMap(\.bucket).sorted { $0.id < $1.id }
        case .heartRate: report.heartRate
        case .hrv: report.hrv
        case .restingHeartRate: report.restingHeartRate
        }
    }
}

private struct MonthCalendar: View {
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale

    let report: TrendReport
    let selectedDate: Date
    @Binding var metric: HeartMetric
    let openDay: (Date) -> Void

    var body: some View {
        let start = report.interval.start
        let today = calendar.startOfDay(for: Date())
        let buckets = metric.buckets(in: report).filter {
            calendar.startOfDay(for: $0.interval.start) <= today
        }
        let values = valuesByDay(buckets)
        let rawHRV = metric == .hrvScore ? valuesByDay(report.hrv) : [:]
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        let offset = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
        let days = calendar.range(of: .day, in: .month, for: start)?.count ?? 0

        TimelineCard(title: "Recovery Calendar", icon: "heart", tint: RhythmStyle.readingBlue,
                     accessory: AnyView(metricMenu)) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let median = median(buckets.map(\.value)) {
                    Text(median, format: .number.precision(.fractionLength(0)))
                        .font(RhythmStyle.display(34))
                        .contentTransition(.numericText())
                    Group {
                        if metric == .hrvScore { Text(verbatim: "% ") + Text("median") } else { Text(metric.unit) + Text(verbatim: " ") + Text("median") }
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                } else {
                    Text(verbatim: "—").font(RhythmStyle.display(34))
                }
                Spacer()
                Group {
                    if metric == .hrvScore { Text("\(buckets.count) scored days") } else { Text("\(buckets.count) days with readings") }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            UnavailableMetrics(names: report.unavailable)

            LazyVGrid(columns: columns, spacing: 5) {
                ForEach(weekdayLabels.indices, id: \.self) { index in
                    Text(verbatim: weekdayLabels[index])
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                ForEach(0..<offset, id: \.self) { _ in
                    Color.clear.frame(height: 44).accessibilityHidden(true)
                }
                ForEach(0..<days, id: \.self) { index in
                    if let date = calendar.date(byAdding: .day, value: index, to: start) {
                        let day = calendar.startOfDay(for: date)
                        dayCell(day, value: values[day], rawHRV: rawHRV[day],
                                dailyScore: report.dailyHRV[day], today: today)
                    }
                }
            }
            .animation(RhythmMotion.select, value: metric)

            if metric == .hrvScore {
                HRVLegend(daily: true, showsTitle: false)
            } else if metric == .hrv {
                PressureColorKey(context: .daily)
            }
            Text("Tap a date to open it.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .sensoryFeedback(.selection, trigger: metric)
    }

    private var metricMenu: some View {
        Menu {
            Picker("Metric", selection: $metric.animation(RhythmMotion.select)) {
                ForEach(HeartMetric.allCases, id: \.self) { option in
                    Text(option == .hrv ? "HRV (SDNN)" : option.title).tag(option)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(metric == .hrv ? "HRV (SDNN)" : metric.title)
                Image(systemName: "chevron.up.chevron.down").font(.caption2.weight(.semibold))
            }
            .font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .foregroundStyle(RhythmStyle.accent)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityLabel("Metric")
    }

    private func median(_ values: [Double]) -> Double? {
        let sorted = values.filter(\.isFinite).sorted()
        guard !sorted.isEmpty else { return nil }
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    private func valuesByDay(_ buckets: [MetricBucket]) -> [Date: Double] {
        Dictionary(buckets.map { (calendar.startOfDay(for: $0.interval.start), $0.value) },
                   uniquingKeysWith: { first, _ in first })
    }

    private var weekdayLabels: [String] {
        var localizedCalendar = calendar
        localizedCalendar.locale = locale
        let symbols = localizedCalendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    private func dayCell(
        _ date: Date, value: Double?, rawHRV: Double?, dailyScore: HRVDailyScore?, today: Date
    ) -> some View {
        let future = date > today
        let color: Color
        switch metric {
        case .hrvScore, .hrv:
            color = PressureBand.color(for: dailyScore?.score)
        case .heartRate, .restingHeartRate:
            color = metric.color
        }
        let selected = calendar.isDate(date, inSameDayAs: selectedDate)
        return Button {
            openDay(date)
        } label: {
            VStack(spacing: 2) {
                Text(calendar.component(.day, from: date), format: .number)
                    .font(.caption.weight(selected ? .bold : .semibold))
                    .foregroundStyle(future ? .secondary : .primary)
                if let value, !future {
                    Group {
                        if metric == .hrvScore {
                            Text(PressureBand.percent(Int(value)))
                        } else {
                            Text(value, format: .number.precision(.fractionLength(0...1)))
                        }
                    }
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .overlay(alignment: .bottom) {
                        Capsule()
                            .fill(color)
                            .frame(width: 9, height: 2)
                            .offset(y: 3)
                            .accessibilityHidden(true)
                    }
                } else if let rawHRV, !future {
                    Text("\(rawHRV, format: .number.precision(.fractionLength(0))) ms")
                        .font(.caption2.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                } else if !future {
                    Text(verbatim: "—")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(value != nil && !future ? color.opacity(0.09) : .clear,
                        in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
            .overlay {
                let isToday = date == today
                if selected || isToday {
                    RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(RhythmStyle.accent.opacity(selected ? 1 : 0.45), lineWidth: selected ? 1.4 : 1)
                        .allowsHitTesting(false)
                }
            }
        }
        .buttonStyle(PressableStyle())
        .disabled(future)
        .accessibilityLabel(Text(date, format: .dateTime.weekday(.wide).month(.wide).day()))
        .accessibilityValue(dayValue(value, rawHRV: rawHRV, dailyScore: dailyScore, future: future))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func dayValue(
        _ value: Double?, rawHRV: Double?, dailyScore: HRVDailyScore?, future: Bool
    ) -> Text {
        if future { return Text("Future Date") }
        if metric == .hrvScore {
            if dailyScore?.score != nil, let dailyScore {
                return Text(dailyScore.assessment.description(in: locale))
            }
            if let rawHRV {
                let reading = rawHRV.formatted(.number.precision(.fractionLength(0...1)))
                let reason = dailyScore?.assessment.description(in: locale)
                    ?? LocalizedStringResource("Daily score unavailable").localized(in: locale)
                return Text("Average HRV: \(reading) ms. \(reason)")
            }
            return Text("No HRV readings available for this date.")
        }
        guard let value else { return Text("No Data Available") }
        let reading = Text(value, format: .number.precision(.fractionLength(0...1))) + Text(verbatim: " ") + Text(metric.unit)
        guard metric == .hrv else { return reading }
        let detail = Text((dailyScore?.assessment ?? .unavailable).description(in: locale))
        return reading + Text(verbatim: " · ") + detail
    }
}

/// Lets a workout page send the app to a day: it pops or dismisses itself, then the root opens that day.
private struct OpenWorkoutDayKey: EnvironmentKey {
    static let defaultValue: (Date) -> Void = { _ in }
}

extension EnvironmentValues {
    var openWorkoutDay: (Date) -> Void {
        get { self[OpenWorkoutDayKey.self] }
        set { self[OpenWorkoutDayKey.self] = newValue }
    }
}

extension TrainingSport {
    /// Same colors as the training volume bars.
    var color: Color {
        switch self {
        case .running: RhythmStyle.activity
        case .strength: RhythmStyle.sleep
        case .walking: RhythmStyle.sage
        case .cycling: RhythmStyle.readingBlue
        case .swimming: RhythmStyle.rem
        case .other: .gray
        }
    }
}

/// Month grid of workouts. Each day shows its main workout's icon and total minutes;
/// tapping a day opens that day at its workouts.
private struct TrainingCalendar: View {
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    let month: DateInterval
    let workouts: [TrainingWorkout]
    let selectedDate: Date
    let openDay: (Date) -> Void

    var body: some View {
        let start = month.start
        let today = calendar.startOfDay(for: Date())
        let inMonth = workouts.filter { month.contains($0.interval.start) }
        let byDay = Dictionary(grouping: inMonth) { calendar.startOfDay(for: $0.interval.start) }
        let total = inMonth.reduce(0) { $0 + $1.minutes }
        let sports = TrainingSport.allCases.filter { sport in inMonth.contains { $0.sport == sport } }
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        let offset = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
        let days = calendar.range(of: .day, in: .month, for: start)?.count ?? 0

        TimelineCard(title: "Training Calendar", icon: "figure.run", tint: RhythmStyle.activity, unitLabel: Text("min")) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(total, format: .number.precision(.fractionLength(0)))
                    .font(RhythmStyle.display(34))
                    .contentTransition(.numericText())
                Text("min").font(.footnote).foregroundStyle(.secondary)
                Spacer()
                Text("\(inMonth.count) workouts").font(.caption).foregroundStyle(.secondary)
            }

            LazyVGrid(columns: columns, spacing: 5) {
                ForEach(weekdayLabels.indices, id: \.self) { index in
                    Text(verbatim: weekdayLabels[index])
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                ForEach(0..<offset, id: \.self) { _ in
                    Color.clear.frame(height: 44).accessibilityHidden(true)
                }
                ForEach(0..<days, id: \.self) { index in
                    if let date = calendar.date(byAdding: .day, value: index, to: start) {
                        let day = calendar.startOfDay(for: date)
                        dayCell(day, workouts: byDay[day] ?? [], today: today)
                    }
                }
            }

            if !sports.isEmpty {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { legend(sports) }
                    VStack(alignment: .leading, spacing: 6) { legend(sports) }
                }
            }
            Text("Tap a date to open it.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func legend(_ sports: [TrainingSport]) -> some View {
        ForEach(sports, id: \.self) { sport in
            ColorKeyItem(color: sport.color, title: sport.title)
        }
    }

    private var weekdayLabels: [String] {
        var localizedCalendar = calendar
        localizedCalendar.locale = locale
        let symbols = localizedCalendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    private func dayCell(_ date: Date, workouts: [TrainingWorkout], today: Date) -> some View {
        let future = date > today
        let main = workouts.max { $0.minutes < $1.minutes }
        let minutes = workouts.reduce(0) { $0 + $1.minutes }
        let color = main?.sport.color ?? .gray
        let selected = calendar.isDate(date, inSameDayAs: selectedDate)
        return Button {
            openDay(date)
        } label: {
            VStack(spacing: 2) {
                Text(calendar.component(.day, from: date), format: .number)
                    .font(.caption.weight(selected ? .bold : .semibold))
                    .foregroundStyle(future ? .secondary : .primary)
                if let main {
                    Image(systemName: main.interval.workoutSymbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(color)
                    Text(minutes, format: .number.precision(.fractionLength(0)))
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                        + Text(verbatim: workouts.count > 1 ? " +" : "")
                        .font(.caption2.weight(.bold))
                } else if !future {
                    Text(verbatim: "—").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(main != nil ? color.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
            .overlay {
                let isToday = date == today
                if selected || isToday {
                    RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(RhythmStyle.accent.opacity(selected ? 1 : 0.45), lineWidth: selected ? 1.4 : 1)
                        .allowsHitTesting(false)
                }
            }
        }
        .buttonStyle(PressableStyle())
        .disabled(future)
        .accessibilityLabel(Text(date, format: .dateTime.weekday(.wide).month(.wide).day()))
        .accessibilityValue(main.map { Text($0.interval.title) + Text(verbatim: " · ") + Text("\(minutes.formatted(.number.precision(.fractionLength(0)))) min") }
                            ?? Text("No Workouts"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct ReadingSummary: View {
    let values: [Double]
    let unit: LocalizedStringKey
    private let format = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...1))

    var body: some View {
        if let low = values.min(), let high = values.max() {
            let delta = (values.last ?? high) - (values.first ?? low)
            VStack(alignment: .leading, spacing: 3) {
                if values.count == 1 {
                    Text("One recorded value: \(low.formatted(format))") + Text(verbatim: " ") + Text(unit)
                } else {
                    Text("Recorded range: \(low.formatted(format))–\(high.formatted(format))") + Text(verbatim: " ") + Text(unit)
                    if abs(delta) < 0.05 {
                        Text("Little or no change from the first value to the latest.")
                    } else {
                        changeDescription(delta)
                    }
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    private func changeDescription(_ delta: Double) -> Text {
        let amount = abs(delta).formatted(format)
        return delta > 0 ? Text("First to latest: up \(amount)") + Text(verbatim: " ") + Text(unit)
            : Text("First to latest: down \(amount)") + Text(verbatim: " ") + Text(unit)
    }
}

private enum ChartPresentation: String, CaseIterable {
    case raw, coded

    var title: LocalizedStringKey {
        switch self {
        case .raw: "Raw"
        case .coded: "Color-coded"
        }
    }
}

private struct ChartPresentationPicker: View {
    @Binding var selection: ChartPresentation

    var body: some View {
        Picker("Chart Display", selection: $selection.animation(RhythmMotion.select)) {
            ForEach(ChartPresentation.allCases, id: \.self) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .sensoryFeedback(.selection, trigger: selection)
    }
}

private struct BucketChart: View {
    @Environment(\.locale) private var locale
    let title: LocalizedStringKey
    let unit: LocalizedStringKey
    let color: Color
    let buckets: [MetricBucket]
    let interval: DateInterval
    let period: TimelinePeriod
    var dailyScores: [Date: HRVDailyScore]?
    var hrvDayColors: [Date: HRVDailyScore]?
    var rawOnly = false
    var openDay: ((Date) -> Void)? = nil
    @State private var selectedTime: Date?

    private var selected: MetricBucket? {
        guard let selectedTime else { return nil }
        return buckets.first { $0.interval.start <= selectedTime && selectedTime < $0.interval.end }
    }

    private var useCoding: Bool { !rawOnly }

    private var comparison: ReadingComparison { ReadingComparison(buckets.map(\.value)) }

    private var dateFormat: Date.FormatStyle {
        switch period {
        case .day: .dateTime.hour().minute()
        case .week, .month: .dateTime.month(.abbreviated).day()
        case .year: .dateTime.month(.abbreviated).year()
        }
    }

    var body: some View {
        TimelineCard(title: title, icon: period == .day ? "figure.walk" : "chart.bar.xaxis",
                     tint: dailyScores == nil ? color : RhythmStyle.accent,
                     unitLabel: dailyScores == nil ? Text(unit) : nil) {
            if dailyScores != nil {
                HRVLegend(daily: true, showsTitle: false)
            }
            if buckets.isEmpty {
                Text("No Data Available").font(.footnote).foregroundStyle(.secondary)
            } else {
                if period == .day {
                    chart.dayAxis(interval)
                } else {
                    chart
                        .chartXScale(domain: interval.start...interval.end)
                        .chartXAxis {
                            AxisMarks(values: .automatic(desiredCount: 4)) {
                                AxisValueLabel(format: period == .year ? .dateTime.month(.abbreviated) : .dateTime.day())
                            }
                        }
                }

                if useCoding {
                    if hrvDayColors != nil {
                        PressureColorKey(context: .daily)
                    } else if dailyScores == nil {
                        ComparisonColorKey(comparison: comparison)
                    }
                }

                if period != .day && dailyScores == nil {
                    if comparison.middleHalf != nil && (rawOnly || hrvDayColors != nil) {
                        Text("Shaded band: the middle 50% of this view.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ReadingSummary(values: buckets.map(\.value), unit: unit)
                }

                if let selectedTime, let dailyScores,
                   let summary = dailyScores.values.first(where: { $0.day.start <= selectedTime && selectedTime < $0.day.end }) {
                    Text(summary.day.start, format: dateFormat).font(.subheadline.weight(.semibold))
                    DailyHRVDetails(summary: summary)
                } else if let selected {
                    LabeledContent {
                        HStack(spacing: 4) {
                            Circle().fill(barColor(selected, comparison: comparison))
                                .frame(width: 7, height: 7).accessibilityHidden(true)
                            Text(selected.value, format: .number.precision(.fractionLength(0...1)))
                            Text(unit)
                        }
                    } label: {
                        Text(selected.interval.start, format: dateFormat)
                    }
                    .font(.subheadline)
                    if useCoding {
                        bucketContext(selected, comparison: comparison)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if selectedTime != nil {
                    Text("No Data Available").font(.footnote).foregroundStyle(.secondary)
                }
                if let selectedTime, let openDay, period == .week || period == .month {
                    Button {
                        openDay(selectedTime)
                    } label: {
                        Label("Open This Day", systemImage: "arrow.up.right")
                            .font(.footnote.weight(.semibold))
                            .frame(minHeight: 32)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .sensoryFeedback(.selection, trigger: selected?.id)
    }

    @ViewBuilder private var chart: some View {
        let comparison = comparison
        let marks = Chart {
            if usesLine, let middle = comparison.middleHalf {
                RectangleMark(
                    xStart: .value(Text("Start"), interval.start),
                    xEnd: .value(Text("End"), interval.end),
                    yStart: .value(Text(unit), middle.lowerBound),
                    yEnd: .value(Text(unit), middle.upperBound)
                )
                .foregroundStyle(color.opacity(0.10))
                .accessibilityHidden(true)
            }
            ForEach(buckets) { bucket in
                mark(bucket, comparison: comparison)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { tick in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.65)).foregroundStyle(RhythmStyle.grid)
                AxisValueLabel {
                    if let value = tick.as(Double.self) {
                        Text(value, format: .number.notation(.compactName).precision(.fractionLength(0...1)))
                            .frame(width: RhythmStyle.axisLabelWidth, alignment: .trailing)
                    }
                }
            }
        }
        .chartXSelection(value: $selectedTime)
        .frame(height: 164)
        .accessibilityLabel(Text(title))

        if dailyScores != nil {
            marks.chartYScale(domain: 0.0...100.0)
        } else {
            if usesLine {
                marks.chartYScale(domain: readingDomain(
                    buckets.map(\.value) + (comparison.middleHalf.map { [$0.lowerBound, $0.upperBound] } ?? [])
                ))
            } else {
                marks.chartYScale(domain: .automatic(includesZero: true))
            }
        }
    }

    /// Averages over days or months read as a line against the usual range; counts and scores stay bars.
    private var usesLine: Bool { period != .day && dailyScores == nil }

    @ChartContentBuilder private func mark(_ bucket: MetricBucket, comparison: ReadingComparison) -> some ChartContent {
        let tint = barColor(bucket, comparison: comparison)
        let dimmed = selected != nil && selected?.id != bucket.id
        if usesLine {
            LineMark(x: .value(Text("Time"), bucket.midpoint), y: .value(Text(unit), bucket.value))
                .lineStyle(StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                .foregroundStyle(color.opacity(0.35))
                .accessibilityHidden(true)
            PointMark(x: .value(Text("Time"), bucket.midpoint), y: .value(Text(unit), bucket.value))
                .foregroundStyle(tint.opacity(dimmed ? 0.35 : 1))
                .symbolSize(period == .week ? 70 : 34)
                .accessibilityLabel(Text(bucket.interval.start, format: dateFormat))
                .accessibilityValue(Text(bucket.value, format: .number.precision(.fractionLength(0...1)))
                    + (useCoding ? Text(verbatim: " · ") + bucketContext(bucket, comparison: comparison) : Text(verbatim: "")))
        } else {
            BarMark(
                x: .value(Text("Time"), bucket.midpoint),
                y: .value(Text(unit), bucket.value),
                width: .fixed(period == .week ? 10 : 5)
            )
            .foregroundStyle(tint.opacity(dimmed ? 0.30 : 0.9))
            .cornerRadius(3)
            .accessibilityLabel(Text(bucket.interval.start, format: dateFormat))
            .accessibilityValue(Text(bucket.value, format: .number.precision(.fractionLength(0...1)))
                + (useCoding ? Text(verbatim: " · ") + bucketContext(bucket, comparison: comparison) : Text(verbatim: "")))
        }
    }

    private func barColor(_ bucket: MetricBucket, comparison: ReadingComparison) -> Color {
        guard useCoding else { return color }
        if let pressure = dailyScores ?? hrvDayColors {
            return PressureBand.color(for: pressure[bucket.id]?.score)
        }
        return comparison.band(for: bucket.value).color
    }

    private func bucketContext(_ bucket: MetricBucket, comparison: ReadingComparison) -> Text {
        if let pressure = dailyScores ?? hrvDayColors {
            let assessment = pressure[bucket.id]?.assessment ?? .unavailable
            return Text(assessment.description(in: locale))
        }
        return Text(comparison.band(for: bucket.value).title)
    }
}

private extension SleepStage {
    var color: Color {
        switch self {
        case .inBed: .gray
        case .awake: RhythmStyle.ochre
        case .core: RhythmStyle.readingBlue
        case .deep: RhythmStyle.sleep
        case .rem: RhythmStyle.rem
        case .asleep: RhythmStyle.hrvTone
        case .other: .gray
        }
    }
}

private extension ReadingComparison.Band {
    var color: Color {
        switch self {
        case .below: RhythmStyle.sleep
        case .middle: RhythmStyle.hrvTone
        case .above: RhythmStyle.ochre
        case .unavailable: .gray
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .below: "Below middle half"
        case .middle: "Middle half"
        case .above: "Above middle half"
        case .unavailable: "Too few readings to compare"
        }
    }
}

private struct ColorKeyItem: View {
    let color: Color
    let title: Text

    init(color: Color, title: LocalizedStringResource) {
        self.init(color: color, text: Text(title))
    }

    init(color: Color, text: Text) {
        self.color = color
        title = text
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7).accessibilityHidden(true)
            title
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }
}

private struct ComparisonColorKey: View {
    @Environment(\.locale) private var locale
    let comparison: ReadingComparison

    var body: some View {
        if let middle = comparison.middleHalf {
            let format = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...1)).locale(locale)
            VStack(alignment: .leading, spacing: 5) {
                Text("Middle 50% in this view: \(middle.lowerBound.formatted(format))–\(middle.upperBound.formatted(format)).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 98), alignment: .leading)], spacing: 5) {
                    ForEach(ReadingComparison.Band.allCases.filter { $0 != .unavailable }, id: \.self) { band in
                        ColorKeyItem(color: band.color, title: band.title)
                    }
                }
            }
        } else {
            ColorKeyItem(color: .gray, title: "Too few readings to compare")
        }
    }
}

private struct PressureColorKey: View {
    enum Context { case scoreOnly, readings, daily }
    var context = Context.scoreOnly

    var body: some View {
        HStack(spacing: 12) {
            ForEach(PressureBand.allCases, id: \.self) { band in
                ColorKeyItem(color: band.color, title: band.title)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

enum PressureBand: CaseIterable {
    case low, usual, elevated, high

    init(score: Int) {
        switch score {
        case ...20: self = .low
        case ...60: self = .usual
        case ...80: self = .elevated
        default: self = .high
        }
    }

    static func color(for score: Int?) -> Color {
        score.map { PressureBand(score: $0).color } ?? .gray
    }

    static func percent(_ score: Int) -> String {
        (Double(score) / 100).formatted(.percent.precision(.fractionLength(0)))
    }

    var color: Color {
        switch self {
        case .low: RhythmStyle.sage
        case .usual: RhythmStyle.readingBlue
        case .elevated: RhythmStyle.ochre
        case .high: RhythmStyle.terracotta
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .low: "Low"
        case .usual: "Usual"
        case .elevated: "Elevated"
        case .high: "High"
        }
    }

    var range: String {
        switch self {
        case .low: "1–20%"
        case .usual: "21–60%"
        case .elevated: "61–80%"
        case .high: "81–100%"
        }
    }
}

extension LocalizedStringResource {
    func localized(in locale: Locale) -> String {
        var resource = self
        resource.locale = locale
        return String(localized: resource)
    }
}

private extension HRVAssessment {
    func description(in locale: Locale) -> String {
        let message: LocalizedStringResource
        switch self {
        case let .score(score, days):
            let percent = PressureBand.percent(score)
            let title = PressureBand(score: score).title.localized(in: locale)
            message = "\(title) · \(percent) · \(days) reference days"
        case let .insufficientHistory(days):
            message = "Reference days: \(days) of 7 needed"
        case .outsideDaytime:
            message = "Outside daytime hours"
        case .duringSleepOrWorkout:
            message = "During recorded sleep or a workout"
        case .unavailable:
            message = "Pressure estimate unavailable"
        }
        return message.localized(in: locale)
    }
}

private struct ScoreEvidence: View {
    let summary: HRVDailyScore

    var body: some View {
        if case let .score(_, days) = summary.assessment {
            DisclosureGroup {
                DailyHRVDetails(summary: summary, showsScore: false)
                    .padding(.top, 5)
            } label: {
                Text("Reference days: \(days)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .tint(.secondary)
        }
    }
}

private struct DailyHRVDetails: View {
    @Environment(\.locale) private var locale
    let summary: HRVDailyScore
    var showsScore = true

    var body: some View {
        let median = summary.samples.median.formatted(.number.precision(.fractionLength(0...1)))
        VStack(alignment: .leading, spacing: 4) {
            if showsScore, let score = summary.score {
                let band = PressureBand(score: score)
                Label {
                    Text(summary.assessment.description(in: locale))
                } icon: {
                    Image(systemName: "circle.fill").foregroundStyle(band.color)
                }
                .font(.subheadline.weight(.semibold))
            } else if showsScore {
                Text(summary.assessment.description(in: locale)).font(.subheadline)
            }
            Text("Daytime median: \(median) ms · Readings used: \(summary.samples.count)")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(summary.samples.source)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct HRVLegend: View {
    var daily = false
    var showsTitle = true

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if showsTitle {
                Text(daily ? "Daily HRV Score" : "HRV-based pressure estimate").fontWeight(.medium)
            }
            PressureColorKey()
            DisclosureGroup("How this estimate works") {
                VStack(alignment: .leading, spacing: 5) {
                    if daily {
                        Text("Each score compares that day’s median daytime SDNN with the same source’s daily medians over the prior 30 days. Lower relative HRV gives a higher score.")
                        Text("Scoring uses daytime readings from 6 AM to 10 PM outside recorded sleep and workouts, with at least 7 reference days.")
                    } else {
                        Text("The estimate ranks your daytime SDNN against daily medians from the same source over the previous 30 days. Lower HRV ranks as higher relative pressure.")
                        Text("Gray points have no estimate. Daytime is 6 AM to 10 PM local time. Recorded sleep and workouts are excluded, and at least 7 reference days are required.")
                    }
                }
                .padding(.top, 5)
            }
            .foregroundStyle(.secondary)
        }
        .font(.footnote)
    }
}

private extension WorkoutHeartRateZones.Zone {
    var color: Color {
        switch id {
        case 1: RhythmStyle.readingBlue
        case 2: RhythmStyle.sage
        case 3: RhythmStyle.straw
        case 4: RhythmStyle.ochre
        default: RhythmStyle.terracotta
        }
    }

    var title: LocalizedStringResource { "Zone \(id)" }
}

private struct WorkoutZonesKey: View {
    @Environment(\.locale) private var locale
    let configuration: WorkoutHeartRateZones

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Heart Rate Zones").font(.subheadline.weight(.semibold))
            Text(sourceDescription)
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(configuration.zones) { zone in
                HStack(spacing: 8) {
                    ColorKeyItem(color: zone.color, title: zone.title)
                    Text(boundaries(zone))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    if let duration = zone.duration, duration.isFinite, duration >= 0 {
                        Text(Duration.seconds(duration), format: .time(pattern: .minuteSecond))
                            .font(.caption.monospacedDigit().weight(.medium))
                            .accessibilityLabel(Text(Duration.seconds(duration), format: .units(allowed: [.minutes, .seconds])))
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var sourceDescription: LocalizedStringKey {
        switch configuration.source {
        case .recorded: "Zones recorded with this workout. Times are for the full workout."
        case .preferred: "Uses your current Apple Health zones. Recorded time in zone is unavailable."
        case .manual: "Uses the manual limits you entered. Recorded time in zone is unavailable."
        }
    }

    private func boundaries(_ zone: WorkoutHeartRateZones.Zone) -> LocalizedStringKey {
        let format = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...1)).locale(locale)
        switch (zone.minimum, zone.maximum) {
        case let (low?, high?): return "\(low.formatted(format))–<\(high.formatted(format)) BPM"
        case let (nil, high?): return "Below \(high.formatted(format)) BPM"
        case let (low?, nil): return "\(low.formatted(format))+ BPM"
        default: return "Any heart rate"
        }
    }
}

private struct ReadingChart: View {
    @Environment(\.locale) private var locale
    @Environment(\.calendar) private var calendar
    let title: LocalizedStringKey
    let unit: String
    let color: Color
    let readings: [HealthReading]
    let range: DateInterval
    var workouts: [HealthInterval] = []
    var rawOnly = false
    var zoomsToRange = false
    var workoutZones: WorkoutHeartRateZones?
    var hrvAssessments: [HealthReading.ID: HRVAssessment]?
    var baseline: ClosedRange<Double>?
    var onInfo: (() -> Void)?
    var onHistory: (() -> Void)?
    /// The workout page shows time in zones itself, so it hides the chart's zone list.
    var showsZoneKey = true
    @AppStorage("rhythmHeartChartMode") private var heartMode = ChartPresentation.coded
    @State private var selectedTime: Date?
    @State private var showingRecords = false

    private var showsModes: Bool { unit == "BPM" && !rawOnly && (!zoomsToRange || workoutZones != nil) }
    private var useCoding: Bool {
        !rawOnly && (!zoomsToRange || workoutZones != nil) && (!showsModes || heartMode == .coded)
    }

    private var comparison: ReadingComparison { ReadingComparison(readings.map(\.value)) }

    /// Dense all-day heart rate reads better as a low–high bar per half hour than as hundreds of dots.
    private var showsRanges: Bool {
        unit == "BPM" && !zoomsToRange && onHistory == nil && readings.count > 48
    }

    private var selected: HealthReading? {
        guard let selectedTime else { return nil }
        return readings.min { abs($0.time.timeIntervalSince(selectedTime)) < abs($1.time.timeIntervalSince(selectedTime)) }
    }

    private var displayRange: DateInterval {
        let now = Date()
        guard onHistory != nil, range.start <= now, now < range.end,
              let hourEnd = calendar.dateInterval(of: .hour, for: now)?.end else { return range }
        let latestReading = readings.last?.time ?? now
        return DateInterval(start: range.start, end: min(range.end, max(hourEnd, latestReading)))
    }

    var body: some View {
        TimelineCard(title: title, icon: unit == "BPM" ? "heart" : "waveform.path",
                     tint: color, unitLabel: Text(unit), onInfo: onInfo) {
            if showsModes {
                ChartPresentationPicker(selection: $heartMode)
            }
            if let summary {
                ValueHeader(value: summary.value, unit: unit, caption: summary.caption)
            }

            if !readings.isEmpty || !workouts.isEmpty {
                chart
            }
            if let workoutZones {
                if showsZoneKey { WorkoutZonesKey(configuration: workoutZones) }
            } else {
                if zoomsToRange {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Heart Rate Zones").font(.subheadline.weight(.semibold))
                        Text("Apple Health workout zones are unavailable for this workout.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        NavigationLink("Set Manual Zones") {
                            ManualWorkoutZonesSettings()
                        }
                        .font(.subheadline.weight(.medium))
                    }
                }
                if useCoding && !readings.isEmpty {
                    if hrvAssessments != nil {
                        PressureColorKey(context: .readings)
                        if baseline != nil {
                            Text("Shaded band: your usual daytime range.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ComparisonColorKey(comparison: comparison)
                    }
                }
            }
            if !workouts.isEmpty {
                Label {
                    Text("Orange bands mark workout times.")
                } icon: {
                    Image(systemName: "square.fill").foregroundStyle(RhythmStyle.activity)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            if hrvAssessments != nil && !readings.isEmpty {
                Divider().padding(.vertical, 4)
                PressureTimeline(readings: readings, assessments: hrvAssessments ?? [:],
                                 day: displayRange, selectedTime: $selectedTime)
            }

            if readings.isEmpty {
                Text(zoomsToRange ? "No Heart Rate Readings" : "No Data Available")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                if let selected {
                    ReadingRow(reading: selected, unit: unit, assessment: assessment(for: selected),
                               comparisonBand: comparisonBand(for: selected, comparison: comparison),
                               workoutZone: useCoding ? workoutZones?.zone(for: selected.value) : nil)
                        .padding(.vertical, 4)
                } else if zoomsToRange && useCoding {
                    Text("Each bar shows the measured range for one part of the workout.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Divider()
                Button {
                    showingRecords = true
                } label: {
                    HStack {
                        Label("View All Readings", systemImage: "list.bullet")
                            .font(.subheadline.weight(.medium))
                        Spacer(minLength: 6)
                        Text(readings.count, format: .number)
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.forward").font(.caption.weight(.semibold))
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: 36)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
            }
            if let onHistory {
                Button(action: onHistory) {
                    Label("30-Day Trend", systemImage: "chart.xyaxis.line")
                        .font(.subheadline.weight(.medium))
                        .frame(minHeight: 36)
                }
                .buttonStyle(.borderless)
            }
        }
        // A tick each time scrubbing lands on a different reading.
        .sensoryFeedback(.selection, trigger: selected?.id)
        .sensoryFeedback(.impact(weight: .light), trigger: showingRecords)
        .sheet(isPresented: $showingRecords) {
            NavigationStack {
                let comparison = comparison
                List(readings) { reading in
                    ReadingRow(reading: reading, unit: unit, assessment: assessment(for: reading),
                               comparisonBand: comparisonBand(for: reading, comparison: comparison),
                               workoutZone: useCoding ? workoutZones?.zone(for: reading.value) : nil)
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(RhythmBackdrop().ignoresSafeArea())
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showingRecords = false }
                    }
                }
            }
        }
    }

    private var summary: (value: String, caption: Text)? {
        guard let latest = readings.last else { return nil }
        let format = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0)).locale(locale)
        if hrvAssessments == nil, let low = readings.map(\.value).min(), let high = readings.map(\.value).max(), low != high {
            return ("\(low.formatted(format))–\(high.formatted(format))", Text("Range"))
        }
        let time = Text(latest.time, format: .dateTime.hour().minute())
        return (latest.value.formatted(format), Text("Latest") + Text(verbatim: " · ") + time)
    }

    private var hrvSegments: [[HealthReading]] {
        var groups: [[HealthReading]] = []
        for reading in readings {
            if let previous = groups.last?.last, previous.sourceID == reading.sourceID,
               reading.time > previous.time, reading.time.timeIntervalSince(previous.time) <= 3 * 3600 {
                groups[groups.count - 1].append(reading)
            } else {
                groups.append([reading])
            }
        }
        return groups
    }

    private var chart: some View {
        let comparison = comparison
        let marks = Chart {
            ForEach(workouts) { workout in
                if let window = workout.clipped(to: range) {
                    RectangleMark(
                        xStart: .value(Text("Start"), window.start),
                        xEnd: .value(Text("End"), window.end)
                    )
                    .foregroundStyle(RhythmStyle.activity.opacity(0.2))
                    .annotation(position: .overlay, alignment: .top, spacing: 2) {
                        Image(systemName: workout.workoutSymbol)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(RhythmStyle.activity)
                            .padding(.top, 2)
                            .accessibilityHidden(true)
                    }
                    .accessibilityLabel(Text(workout.title))
                    .accessibilityValue(Text(window.start..<window.end, format: .interval.hour().minute()))
                }
            }
            if let baseline {
                RectangleMark(
                    xStart: .value(Text("Start"), displayRange.start),
                    xEnd: .value(Text("End"), displayRange.end),
                    yStart: .value(unit, baseline.lowerBound),
                    yEnd: .value(unit, baseline.upperBound)
                )
                .foregroundStyle(color.opacity(0.10))
                .accessibilityHidden(true)
            }
            if zoomsToRange && useCoding, let workoutZones {
                ForEach(WorkoutHeartRateRange.make(from: readings, within: range)) { bin in
                    zoneMarks(bin, configuration: workoutZones)
                }
            } else {
                if hrvAssessments != nil {
                    ForEach(Array(hrvSegments.enumerated()), id: \.offset) { group in
                        ForEach(group.element) { reading in
                            LineMark(x: .value(Text("Time"), reading.time), y: .value(unit, reading.value),
                                     series: .value("Segment", group.offset))
                                .lineStyle(StrokeStyle(lineWidth: 1.4))
                                .foregroundStyle(color.opacity(0.22))
                                .accessibilityHidden(true)
                        }
                    }
                }
                if showsRanges {
                    ForEach(WorkoutHeartRateRange.make(from: readings, within: range, bucketCount: 48)) { bin in
                        BarMark(x: .value(Text("Time"), bin.time),
                                yStart: .value(unit, bin.low),
                                yEnd: .value(unit, max(bin.high, bin.low + 1)),
                                width: .fixed(4))
                            .foregroundStyle(color)
                            .cornerRadius(2)
                            .accessibilityLabel(Text(bin.time, format: .dateTime.hour().minute()))
                            .accessibilityValue(Text(verbatim: "\(Int(bin.low))–\(Int(bin.high)) \(unit)"))
                    }
                } else {
                    ForEach(readings) { reading in
                        PointMark(x: .value(Text("Time"), reading.time), y: .value(unit, reading.value))
                            .foregroundStyle(readingColor(reading, comparison: comparison))
                            .symbolSize(onHistory != nil ? 23 : 20)
                            .accessibilityValue(Text(readingAccessibilityValue(reading, comparison: comparison)))
                    }
                }
            }
            if let selected {
                RuleMark(x: .value(Text("Selected Time"), selected.time))
                    .foregroundStyle(RhythmStyle.accent.opacity(0.38))
                PointMark(x: .value(Text("Time"), selected.time), y: .value(unit, selected.value))
                    .foregroundStyle(readingColor(selected, comparison: comparison))
                    .symbolSize(70)
                    .annotation(position: .top, spacing: 4,
                                overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                        ChartValueBadge(value: readingAccessibilityValue(selected, includesAssessment: false))
                    }
                    .accessibilityHidden(true)
            }
        }
        .chartYScale(domain: readingDomain(readings.map(\.value) + (baseline.map { [$0.lowerBound, $0.upperBound] } ?? [])))
        .chartYAxis {
            if !readings.isEmpty {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { mark in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.65)).foregroundStyle(RhythmStyle.grid)
                    AxisValueLabel {
                        if let value = mark.as(Double.self) {
                            Text(value, format: .number.precision(.fractionLength(0...1)))
                                .frame(width: RhythmStyle.axisLabelWidth, alignment: .trailing)
                        }
                    }
                }
            }
        }
        .chartXSelection(value: $selectedTime)
        .frame(height: zoomsToRange ? 184 : hrvAssessments != nil ? 166 : 148)
        .accessibilityLabel(Text(title))

        return Group {
            if zoomsToRange {
                marks.chartXScale(domain: range.start...range.end)
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) {
                            AxisValueLabel(format: .dateTime.hour().minute())
                        }
                    }
            } else {
                marks.dayAxis(displayRange, hourStride: displayRange.duration <= 18 * 3600 ? 3 : 6)
            }
        }
    }

    @ChartContentBuilder private func zoneMarks(
        _ bin: WorkoutHeartRateRange, configuration: WorkoutHeartRateZones
    ) -> some ChartContent {
        if bin.low == bin.high, let zone = configuration.zone(for: bin.low) {
            PointMark(x: .value(Text("Time"), bin.time), y: .value(unit, bin.low))
                .foregroundStyle(zone.color)
                .symbolSize(42)
                .accessibilityLabel(Text(bin.time, format: .dateTime.hour().minute()))
                .accessibilityValue(Text(bin.low, format: .number) + Text(verbatim: " BPM · ") + Text(zone.title))
        } else {
            let segments = configuration.segments(low: bin.low, high: bin.high)
            ForEach(segments) { segment in
                RuleMark(x: .value(Text("Time"), bin.time),
                         yStart: .value(unit, segment.low), yEnd: .value(unit, segment.high))
                    .lineStyle(StrokeStyle(lineWidth: 7, lineCap: segments.count == 1 ? .round : .butt))
                    .foregroundStyle(segment.zone.color)
                    .accessibilityLabel(Text(bin.time, format: .dateTime.hour().minute()))
                    .accessibilityValue(
                        Text(segment.low, format: .number.precision(.fractionLength(0...1)))
                        + Text(verbatim: "–")
                        + Text(segment.high, format: .number.precision(.fractionLength(0...1)))
                        + Text(verbatim: " BPM · ") + Text(segment.zone.title)
                    )
            }
        }
    }

    private func comparisonBand(for reading: HealthReading, comparison: ReadingComparison) -> ReadingComparison.Band? {
        guard useCoding, hrvAssessments == nil, workoutZones == nil else { return nil }
        return comparison.band(for: reading.value)
    }

    private func assessment(for reading: HealthReading) -> HRVAssessment? {
        hrvAssessments.map { $0[reading.id, default: .unavailable] }
    }

    private func readingColor(_ reading: HealthReading, comparison: ReadingComparison) -> Color {
        guard useCoding else { return color }
        if let workoutZones { return workoutZones.zone(for: reading.value)?.color ?? .gray }
        if let assessment = assessment(for: reading) {
            if case let .score(score, _) = assessment { return PressureBand(score: score).color }
            return .gray
        }
        return comparison.band(for: reading.value).color
    }

    private func readingAccessibilityValue(
        _ reading: HealthReading, comparison: ReadingComparison? = nil, includesAssessment: Bool = true
    ) -> String {
        let format = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...2)).locale(locale)
        let value = "\(reading.value.formatted(format)) \(unit)"
        guard includesAssessment, useCoding else { return value }
        if let zone = workoutZones?.zone(for: reading.value) {
            return "\(value). \(zone.title.localized(in: locale))"
        }
        if let result = assessment(for: reading) {
            return "\(value). \(result.description(in: locale))"
        }
        guard let comparison else { return value }
        return "\(value). \(comparison.band(for: reading.value).title.localized(in: locale))"
    }


}

private func readingDomain(_ values: [Double]) -> ClosedRange<Double> {
    let finiteValues = values.filter(\.isFinite)
    guard let low = finiteValues.min(), let high = finiteValues.max() else { return 0...1 }
    let padding = max((high - low) * 0.12, 3)
    return (low - padding)...(high + padding)
}

private struct DotLattice: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 7.5
            let radius: CGFloat = 1.5
            var dots = Path()
            for x in stride(from: spacing / 2, to: size.width, by: spacing) {
                for y in stride(from: spacing / 2, to: size.height, by: spacing) {
                    dots.addEllipse(in: CGRect(x: x - radius, y: y - radius,
                                               width: radius * 2, height: radius * 2))
                }
            }
            context.fill(dots, with: .color(.primary.opacity(0.09)))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private extension HeartHistoryMetric {
    var title: LocalizedStringKey {
        switch self {
        case .hrv: "Heart Rate Variability (SDNN)"
        case .restingHeartRate: "Resting Heart Rate"
        }
    }

    var unit: String { self == .hrv ? "ms" : "BPM" }
}

private struct HeartHistorySheet: View {
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss

    let metric: HeartHistoryMetric
    let endingOn: Date
    let health: HealthStore
    @State private var buckets: [MetricBucket]?
    @State private var dailyHRV: [Date: HRVDailyScore] = [:]
    @State private var failed = false
    @State private var selection: Date?

    private var interval: DateInterval? {
        let date = calendar.startOfDay(for: endingOn)
        guard let start = calendar.date(byAdding: .day, value: -29, to: date),
              let end = calendar.date(byAdding: .day, value: 1, to: date) else { return nil }
        return DateInterval(start: start, end: end)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    if let buckets, let interval, !buckets.isEmpty {
                        historyContent(buckets, interval: interval)
                    } else if failed {
                        Text("Couldn’t load the 30-day trend.").foregroundStyle(.secondary)
                    } else if buckets != nil {
                        Text("No readings in this 30-day window.").foregroundStyle(.secondary)
                    } else {
                        ProgressView("Loading Health Data")
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 28)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
            .background(RhythmBackdrop().ignoresSafeArea())
            .navigationTitle(metric.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close")
                }
            }
            .task { await load() }
        }
        .tint(RhythmStyle.accent)
    }

    private func load() async {
        guard let interval else {
            failed = true
            return
        }
        do {
            let result = try await health.readHistory(metric, in: interval, calendar: calendar)
            guard !Task.isCancelled else { return }
            dailyHRV = result.dailyHRV
            buckets = result.buckets.filter { $0.value.isFinite }.sorted { $0.id < $1.id }
        } catch {
            if !Task.isCancelled { failed = true }
        }
    }

    @ViewBuilder private func historyContent(_ buckets: [MetricBucket], interval: DateInterval) -> some View {
        let selected = selection.flatMap { date in
            buckets.first { $0.interval.start <= date && date < $0.interval.end }
        }
        let headline = selection == nil ? buckets.last : selected
        let format = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...1)).locale(locale)
        VStack(spacing: 8) {
            Text("Apple Health · 30 days").font(.subheadline).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(headline.map { $0.value.formatted(format) } ?? "—")
                    .font(RhythmStyle.display(52))
                    .monospacedDigit()
                Text(metric.unit).font(.title3).foregroundStyle(.secondary)
            }
            if let date = headline?.interval.start ?? selection {
                HStack(spacing: 5) {
                    if headline != nil {
                        metric == .hrv ? Text("Daytime median") : Text("Daily average")
                        Text(verbatim: "·")
                    }
                    Text(date, format: .dateTime.month(.abbreviated).day().year())
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)

        let values = buckets.map(\.value)
        historyChart(buckets, interval: interval, selected: selected)

        if metric == .hrv {
            PressureColorKey(context: .daily)
        }

        let average = values.reduce(0, +) / Double(values.count)
        VStack(alignment: .leading, spacing: 8) {
            Text("Average: \(average.formatted(format)) \(metric.unit) across \(buckets.count) days with readings.")
                .font(.headline)
            if let low = values.min(), let high = values.max(), low != high {
                Text("Daily values ranged from \(low.formatted(format)) to \(high.formatted(format)) \(metric.unit).")
                    .foregroundStyle(.secondary)
            }
            if selection != nil && selected == nil {
                Text("No reading for the selected day.").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func historyChart(
        _ buckets: [MetricBucket], interval: DateInterval, selected: MetricBucket?
    ) -> some View {
        var groups: [[MetricBucket]] = []
        for bucket in buckets {
            if groups.last?.last?.interval.end == bucket.interval.start {
                groups[groups.count - 1].append(bucket)
            } else {
                groups.append([bucket])
            }
        }
        let domain = readingDomain(buckets.map(\.value))
        let dateTicks = [0, 9, 19, 29].compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: interval.start)
                .flatMap { calendar.dateInterval(of: .day, for: $0) }
                .map { $0.start.addingTimeInterval($0.duration / 2) }
        }
        return Chart {
            if metric == .hrv {
                ForEach(Array(groups.enumerated()), id: \.offset) { group in
                    ForEach(group.element) { bucket in
                        LineMark(x: .value(Text("Date"), bucket.midpoint),
                                 y: .value(metric.unit, bucket.value),
                                 series: .value("Segment", group.offset))
                            .lineStyle(StrokeStyle(lineWidth: 1.6))
                            .foregroundStyle(RhythmStyle.readingBlue.opacity(0.23))
                            .accessibilityHidden(true)
                    }
                }
            }
            ForEach(buckets) { bucket in
                PointMark(x: .value(Text("Date"), bucket.midpoint), y: .value(metric.unit, bucket.value))
                    .symbol {
                        let size: CGFloat = selected?.id == bucket.id ? 11 : metric == .hrv ? 8 : 5.5
                        Circle()
                            .fill(metric == .hrv ? PressureBand.color(for: dailyHRV[bucket.id]?.score) : RhythmStyle.readingBlue)
                            .overlay { Circle().strokeBorder(RhythmStyle.surface, lineWidth: 1.15) }
                            .frame(width: size, height: size)
                    }
                    .accessibilityLabel(Text(bucket.interval.start, format: .dateTime.month(.wide).day()))
                    .accessibilityValue(
                        Text(bucket.value, format: .number.precision(.fractionLength(0...1))) + Text(verbatim: " " + metric.unit)
                        + (metric == .hrv
                           ? Text(verbatim: " · ") + Text((dailyHRV[bucket.id]?.assessment ?? .unavailable).description(in: locale))
                           : Text(verbatim: ""))
                    )
            }
            if let selection {
                RuleMark(x: .value(Text("Selected Time"), selected?.midpoint ?? selection))
                    .foregroundStyle(RhythmStyle.readingBlue.opacity(0.4))
                    .accessibilityHidden(true)
            }
        }
        .chartXScale(domain: interval.start...interval.end)
        .chartYScale(domain: domain)
        .chartPlotStyle { plot in plot.background { DotLattice() } }
        .chartXAxis {
            AxisMarks(values: dateTicks) { tick in
                if let date = tick.as(Date.self) {
                    AxisValueLabel(anchor: date == dateTicks.first ? .leading : date == dateTicks.last ? .trailing : .center) {
                        Text(date, format: .dateTime.month(.abbreviated).day().locale(locale))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { tick in
                AxisValueLabel {
                    if let number = tick.as(Double.self) {
                        Text(number, format: .number.precision(.fractionLength(0...1)))
                    }
                }
            }
        }
        .chartXSelection(value: $selection)
        .sensoryFeedback(.selection, trigger: selected?.id)
        .frame(height: 220)
        .accessibilityLabel(Text(metric.title))
    }
}

private struct ValueHeader: View {
    let value: String
    let unit: String
    let caption: Text

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            caption
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(verbatim: value)
                    .font(RhythmStyle.display(30))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                if !unit.isEmpty {
                    Text(verbatim: unit)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ChartValueBadge: View {
    let value: String

    var body: some View {
        Text(value)
            .font(.caption.weight(.semibold).monospacedDigit())
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(RhythmStyle.surface, in: RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7).strokeBorder(RhythmStyle.divider)
            }
    }
}

private struct PressureTimeline: View {
    @Environment(\.locale) private var locale

    struct Estimate: Identifiable {
        let reading: HealthReading
        let value: Int

        var id: HealthReading.ID { reading.id }
    }

    let readings: [HealthReading]
    let assessments: [HealthReading.ID: HRVAssessment]
    let day: DateInterval
    @Binding var selectedTime: Date?

    private var estimates: [Estimate] {
        readings.compactMap { reading in
            guard case let .score(value, _)? = assessments[reading.id] else { return nil }
            return Estimate(reading: reading, value: value)
        }
    }

    struct Bin: Identifiable {
        let id: Int
        let time: Date
        let value: Int
        let count: Int
    }

    /// Half-hour slots. Each bar is the mean estimate in its slot, so dense days don't pile bars on top of each other.
    private static let binLength: TimeInterval = 30 * 60

    private func binIndex(_ time: Date) -> Int {
        Int(time.timeIntervalSince(day.start) / Self.binLength)
    }

    private func bins(_ estimates: [Estimate]) -> [Bin] {
        Dictionary(grouping: estimates) { binIndex($0.reading.time) }
            .map { index, items in
                let mean = Double(items.map(\.value).reduce(0, +)) / Double(items.count)
                return Bin(id: index,
                           time: day.start.addingTimeInterval((Double(index) + 0.5) * Self.binLength),
                           value: max(Int(mean.rounded()), 1), count: items.count)
            }
            .sorted { $0.id < $1.id }
    }

    var body: some View {
        let estimates = estimates
        let selected = selectedTime.flatMap { time in
            readings.min { abs($0.time.timeIntervalSince(time)) < abs($1.time.timeIntervalSince(time)) }
        }
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Pressure Through the Day").font(RhythmStyle.sectionTitle).textCase(.uppercase).tracking(0.8)
                Spacer(minLength: 6)
                Text(verbatim: "%").font(.caption.weight(.medium)).foregroundStyle(.secondary)
            }

            if let latest = estimates.last {
                let activeBin = selected.map { binIndex($0.time) }
                Chart {
                    ForEach(bins(estimates)) { bin in
                        let on = activeBin == nil || activeBin == bin.id
                        BarMark(x: .value(Text("Time"), bin.time),
                                y: .value(Text("Pressure Estimate"), bin.value),
                                width: .fixed(3.5))
                            .foregroundStyle(PressureBand(score: bin.value).color.opacity(on ? 0.95 : 0.3))
                            .cornerRadius(1.75)
                            .accessibilityLabel(Text(bin.time, format: .dateTime.hour().minute()))
                            .accessibilityValue(Text(PressureBand.percent(bin.value)))
                    }
                    if let selected {
                        RuleMark(x: .value(Text("Selected Time"), selected.time))
                            .foregroundStyle(RhythmStyle.accent.opacity(0.38))
                    }
                }
                .dayAxis(day, hourStride: day.duration <= 18 * 3600 ? 3 : 6)
                .chartYScale(domain: 0...100)
                .chartYAxis {
                    AxisMarks(position: .leading, values: [0, 50, 100]) { tick in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.65))
                            .foregroundStyle(RhythmStyle.grid)
                        AxisValueLabel {
                            if let value = tick.as(Int.self) {
                                Text(value, format: .number)
                                    .frame(width: RhythmStyle.axisLabelWidth, alignment: .trailing)
                            }
                        }
                    }
                }
                .chartXSelection(value: $selectedTime)
                .frame(height: 144)
                .accessibilityLabel(Text("Pressure Through the Day"))

                estimateCaption(latest: latest, selected: selected)
            } else {
                Text("There are no eligible pressure estimates for this date.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func estimateCaption(latest: Estimate, selected: HealthReading?) -> some View {
        let time = (selected ?? latest.reading).time.formatted(.dateTime.hour().minute().locale(locale))
        let value: Int?
        if let selected {
            if case let .score(score, _)? = assessments[selected.id] { value = score } else { value = nil }
        } else {
            value = latest.value
        }

        return HStack(spacing: 6) {
            if let value {
                let percent = PressureBand.percent(value)
                Circle().fill(PressureBand(score: value).color)
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)
                Text(selected == nil ? "Latest estimate: \(percent) at \(time)." : "Selected estimate: \(percent) at \(time).")
            } else {
                Text("No pressure estimate at \(time).")
            }
        }
        .font(.subheadline.weight(.semibold))
    }

}

private struct PressureGuide: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    TimelineCard(title: "What the score compares", icon: "waveform.path") {
                        Text("The daily score compares your daytime HRV median with daily medians from the same source over the previous 30 days. Lower HRV relative to that history gives a higher pressure estimate.")
                            .foregroundStyle(.secondary)
                    }
                    TimelineCard(title: "Overnight HRV", icon: "moon.stars", tint: RhythmStyle.sleep) {
                        Text("The overnight score uses the median HRV recorded during sleep and compares it with the same source’s previous 30 nights, on the same color scale. Overnight readings are often the steadiest baseline.")
                            .foregroundStyle(.secondary)
                    }
                    TimelineCard(title: "How to read the colors", icon: "chart.bar.xaxis") {
                        ForEach(PressureBand.allCases, id: \.self) { band in
                            HStack(spacing: 10) {
                                Circle().fill(band.color).frame(width: 9, height: 9).accessibilityHidden(true)
                                Text(band.title)
                                Spacer(minLength: 6)
                                Text(verbatim: band.range).monospacedDigit().foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    TimelineCard(title: "Why some readings have no score", icon: "info.circle") {
                        Text("Individual estimates use readings between 6 AM and 10 PM, outside recorded sleep and workouts. They require at least 7 reference days.")
                            .foregroundStyle(.secondary)
                        Text("The timeline shows estimates at actual HRV measurement times. Gaps show where an estimate was unavailable.")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(16)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Understanding Pressure")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(RhythmStyle.accent)
    }
}

private struct ReadingRow: View {
    @Environment(\.locale) private var locale
    let reading: HealthReading
    let unit: String
    var assessment: HRVAssessment?
    var comparisonBand: ReadingComparison.Band?
    var workoutZone: WorkoutHeartRateZones.Zone?

    var body: some View {
        LabeledContent {
            Text("\(reading.value.formatted(.number.precision(.fractionLength(0...2)))) \(unit)")
                .monospacedDigit()
                .foregroundStyle(.primary)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(reading.time, format: .dateTime.hour().minute().second())
                Text(reading.source)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let assessment {
                    let score: Int? = if case let .score(value, _) = assessment { value } else { nil }
                    ColorKeyItem(color: PressureBand.color(for: score), text: Text(assessment.description(in: locale)))
                } else if let workoutZone {
                    ColorKeyItem(color: workoutZone.color, title: workoutZone.title)
                } else if let comparisonBand {
                    ColorKeyItem(color: comparisonBand.color, title: comparisonBand.title)
                }
            }
        }
    }
}

private struct SectionCaption: View {
    let title: LocalizedStringKey

    init(_ title: LocalizedStringKey) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.footnote.weight(.bold))
            .textCase(.uppercase)
            .tracking(1.6)
            .foregroundStyle(.secondary)
            .padding(.top, 14)
            .padding(.horizontal, 18)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct PressureScale: View {
    let score: Int

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let span = max(0, width - 9)
            let marker = min(max(width * CGFloat(score) / 100, 6), max(width - 6, 6))
            HStack(spacing: 3) {
                Capsule().fill(PressureBand.low.color.opacity(0.72)).frame(width: span * 0.2)
                Capsule().fill(PressureBand.usual.color.opacity(0.72)).frame(width: span * 0.4)
                Capsule().fill(PressureBand.elevated.color.opacity(0.72)).frame(width: span * 0.2)
                Capsule().fill(PressureBand.high.color.opacity(0.72)).frame(width: span * 0.2)
            }
            .frame(height: 6)
            .frame(maxHeight: .infinity)
            .overlay(alignment: .leading) {
                Circle().fill(.primary)
                    .overlay { Circle().strokeBorder(RhythmStyle.surface, lineWidth: 2) }
                    .frame(width: 12, height: 12)
                    .offset(x: marker - 6)
            }
        }
        .frame(height: 14)
        .accessibilityHidden(true)
    }
}

struct TimelineCard<Content: View>: View {
    let title: LocalizedStringKey
    var icon: String? = nil
    var tint = RhythmStyle.accent
    var unitLabel: Text? = nil
    var onInfo: (() -> Void)? = nil
    /// A control on the right of the title, such as a metric menu.
    var accessory: AnyView? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                if icon != nil {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(tint)
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(RhythmStyle.sectionTitle)
                    .textCase(.uppercase)
                    .tracking(0.8)
                    .accessibilityAddTraits(.isHeader)
                if unitLabel != nil || onInfo != nil || accessory != nil {
                    Spacer(minLength: 6)
                }
                if let accessory {
                    accessory
                }
                if let unitLabel {
                    unitLabel
                        .font(.caption)
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                }
                if let onInfo {
                    Button(action: onInfo) {
                        Image(systemName: "info.circle")
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Understanding Pressure")
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .rhythmCard()
    }
}

private extension View {
    /// Rounded, lightly tinted block used for every section.
    func rhythmCard() -> some View {
        padding(18).modifier(CardSurface())
    }

    @ViewBuilder func rhythmGlassButton() -> some View {
        if #available(iOS 26.0, *) {
            buttonStyle(.glass).buttonBorderShape(.circle)
        } else {
            buttonStyle(.borderless)
        }
    }

    @ViewBuilder func rhythmProminentButton() -> some View {
        if #available(iOS 26.0, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
    }

    func dayAxis(_ day: DateInterval, hourStride: Int = 6) -> some View {
        chartXScale(domain: day.start...day.end)
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: hourStride)) { tick in
                    if let date = tick.as(Date.self), date < day.end {
                        AxisValueLabel {
                            let hour = Calendar.autoupdatingCurrent.component(.hour, from: date)
                            Text(hour, format: .number.precision(.integerLength(2)))
                        }
                    }
                }
            }
    }
}

struct TrainingWorkoutDetail: View {
    let workout: TrainingWorkout
    let health: HealthStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            WorkoutDetailView(workout: workout.interval, health: health, recovery: workout.recovery)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

// MARK: - Workout page

/// Activity icon on a rounded tile: filled for the highlighted workout type, tinted otherwise.
private struct WorkoutBadge: View {
    let symbol: String
    var size: CGFloat = 40
    var filled = false

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(filled ? RhythmStyle.activity : RhythmStyle.activity.opacity(0.14))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .foregroundStyle(filled ? Color.white : RhythmStyle.activity)
            }
            .accessibilityHidden(true)
    }
}

/// "105 min · 06:55–08:40", or "Wed · 105 min · 06:55–08:40" with `showsDay`.
private struct WorkoutTimeText: View {
    let workout: HealthInterval
    var showsDay = false

    var body: some View {
        let minutes = (workout.workoutDuration ?? workout.end.timeIntervalSince(workout.start)) / 60
        (showsDay ? Text(workout.start, format: .dateTime.weekday(.abbreviated)) + Text(verbatim: " · ") : Text(verbatim: ""))
            + Text("\(minutes.formatted(.number.precision(.fractionLength(0)))) min")
            + Text(verbatim: " · ")
            + Text(workout.start, format: .dateTime.hour().minute())
            + Text(verbatim: "–")
            + Text(workout.end, format: .dateTime.hour().minute())
    }
}

struct WorkoutRow: View {
    let workout: HealthInterval
    /// Adds the weekday, for lists that span several days.
    var showsDay = false

    var body: some View {
        HStack(spacing: 12) {
            WorkoutBadge(symbol: workout.workoutSymbol)
            VStack(alignment: .leading, spacing: 3) {
                Text(workout.title).font(.subheadline.weight(.semibold))
                WorkoutTimeText(workout: workout, showsDay: showsDay)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let energy = workout.activeEnergy, energy > 0 {
                Text("\(energy.formatted(.number.precision(.fractionLength(0)))) kcal")
                    .font(.footnote.weight(.medium).monospacedDigit())
            }
            Image(systemName: "chevron.forward")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct WorkoutStat: View {
    let title: Text
    let value: String?
    var unit: LocalizedStringKey? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            title
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(verbatim: value ?? "—")
                    .font(RhythmStyle.display(24, weight: .bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let unit, value != nil {
                    Text(unit).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// One horizontal bar per zone: share of the workout, time, and the zone's BPM range.
private struct ZoneBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grown = false
    let zone: WorkoutHeartRateZones.Zone
    let seconds: TimeInterval
    let total: TimeInterval
    let range: String
    /// Position from the top, so the bars grow in one after another.
    var order = 0

    private var fraction: Double { total > 0 ? seconds / total : 0 }

    var body: some View {
        HStack(spacing: 12) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(RhythmStyle.track)
                    if seconds > 0 {
                        Capsule().fill(zone.color)
                            .frame(width: max(30, geometry.size.width * fraction * (grown || reduceMotion ? 1 : 0)))
                    }
                    Text(verbatim: "\(zone.id)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(seconds > 0 ? (zone.id == 3 ? Color.black.opacity(0.7) : .white) : .secondary)
                        .padding(.leading, 11)
                }
            }
            .frame(height: 26)
            .onAppear {
                withAnimation(RhythmMotion.grow.delay(0.15 + 0.06 * Double(order))) { grown = true }
            }
            VStack(alignment: .trailing, spacing: 1) {
                Text(verbatim: "\(percent) · \(clock)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                Text(verbatim: "\(range) BPM")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(width: 108, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(zone.title))
        .accessibilityValue(Text(Duration.seconds(seconds), format: .units(allowed: [.hours, .minutes, .seconds]))
            + Text(verbatim: ", \(percent)"))
    }

    private var percent: String {
        fraction > 0 && fraction < 0.01 ? "<1%" : fraction.formatted(.percent.precision(.fractionLength(0)))
    }

    private var clock: String {
        Duration.seconds(seconds).formatted(.time(pattern: seconds >= 3600 ? .hourMinuteSecond : .minuteSecond))
    }
}

/// The month around a workout: days with this workout type filled, other workouts tinted.
private struct MonthWorkoutGrid: View {
    @Environment(\.calendar) private var calendar
    let current: HealthInterval
    let log: [WorkoutLogEntry]
    /// Called with a day that has workouts.
    var onSelect: (Date) -> Void = { _ in }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    var body: some View {
        VStack(spacing: 8) {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(verbatim: symbol)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityHidden(true)
            if let month = calendar.dateInterval(of: .month, for: current.start) {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(Array(days(in: month).enumerated()), id: \.offset) { _, day in
                        if let day {
                            let hasWorkouts = log.contains { calendar.isDate($0.start, inSameDayAs: day) }
                            Button { onSelect(day) } label: { cell(day) }
                                .buttonStyle(PressableStyle())
                                .disabled(!hasWorkouts)
                        } else {
                            Color.clear.frame(height: 1)
                        }
                    }
                }
            }
        }
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = max(0, min(symbols.count - 1, calendar.firstWeekday - 1))
        return Array(symbols[first...] + symbols[..<first])
    }

    private func days(in month: DateInterval) -> [Date?] {
        let lead = (calendar.component(.weekday, from: month.start) - calendar.firstWeekday + 7) % 7
        var result: [Date?] = Array(repeating: nil, count: lead)
        var day = month.start
        while day < month.end {
            result.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }

    private func cell(_ day: Date) -> some View {
        let entries = log.filter { calendar.isDate($0.start, inSameDayAs: day) }
        let same = entries.contains { $0.activity == current.workoutActivity }
        let isCurrent = calendar.isDate(day, inSameDayAs: current.start)
        let future = day > Date()
        let fill: Color = same ? RhythmStyle.activity
            : entries.isEmpty ? RhythmStyle.track.opacity(future ? 0.45 : 1)
            : RhythmStyle.activity.opacity(0.16)
        let symbol = same ? current.workoutSymbol : entries.first?.symbol
        return VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(fill)
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if let symbol {
                        Image(systemName: symbol)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(same ? Color.white : RhythmStyle.activity)
                    }
                }
                .overlay {
                    if isCurrent {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(RhythmStyle.activity, lineWidth: 1.5)
                            .padding(-3)
                    }
                }
            Text(day, format: .dateTime.day())
                .font(.caption2.monospacedDigit().weight(isCurrent ? .bold : .regular))
                .foregroundStyle(isCurrent ? RhythmStyle.activity : .secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(day, format: .dateTime.month().day()))
        .accessibilityValue(same ? Text(current.title) : entries.isEmpty ? Text("No Workouts") : Text("Other Workouts"))
    }
}

/// One workout: header, key numbers, time in zones, heart rate, and the month of training around it.
private struct WorkoutDetailView: View {
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @AppStorage("rhythmManualWorkoutZones") private var manualZones = ""
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWorkoutDay) private var openWorkoutDay
    let workout: HealthInterval
    let health: HealthStore
    /// Heart rate the day view already loaded; loaded here when nil.
    var readings: [HealthReading]? = nil
    var preferredZones: WorkoutHeartRateZones? = nil
    var recovery: Double? = nil
    @State private var heart: [HealthReading]?
    @State private var loadedZones: WorkoutHeartRateZones?
    @State private var log: [WorkoutLogEntry]?
    @State private var logLoaded = false

    private var window: DateInterval {
        DateInterval(start: workout.start, end: max(workout.end, workout.start))
    }

    private var zones: WorkoutHeartRateZones? {
        workout.workoutZones ?? preferredZones ?? loadedZones ?? WorkoutHeartRateZones(manualBoundaries: manualZones)
    }

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                stats
                if let zones {
                    zoneCard(zones)
                }
                heartCard
                monthCard.id("workoutMonth")
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 28)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        #if DEBUG
        .onChange(of: logLoaded) { _, loaded in
            // `-rhythmDebugScroll workoutMonth` shows the month calendar, for simulator screenshots.
            guard loaded, UserDefaults.standard.string(forKey: "rhythmDebugScroll") == "workoutMonth" else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { proxy.scrollTo("workoutMonth", anchor: .bottom) }
        }
        #endif
        }
        .background(RhythmBackdrop().ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        let year = calendar.dateInterval(of: .year, for: workout.start) ?? window
        async let entries = health.readWorkoutLog(year, calendar: calendar)
        if let readings {
            heart = readings
        } else {
            let result = await health.readWorkoutHeart(workout)
            heart = result.0
            loadedZones = result.1
        }
        log = await entries
        logLoaded = true
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    kicker
                    Text(workout.title)
                        .font(RhythmStyle.display(30, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                }
                Spacer(minLength: 8)
                WorkoutBadge(symbol: workout.workoutSymbol, size: 56)
            }
            VStack(alignment: .leading, spacing: 5) {
                Label {
                    Text(workout.start, format: .dateTime.year().month().day())
                        + Text(verbatim: "  ")
                        + Text(workout.start, format: .dateTime.hour().minute())
                        + Text(verbatim: "–")
                        + Text(workout.end, format: .dateTime.hour().minute())
                } icon: {
                    Image(systemName: "clock")
                }
                Label {
                    Text("Recorded by \(workout.source)")
                } icon: {
                    Image(systemName: "applewatch")
                }
            }
            .font(.footnote.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)
    }

    private var kicker: some View {
        HStack(spacing: 6) {
            Text(workout.start, format: .dateTime.month(.abbreviated))
            if let rank = rank(in: .month) {
                Text(verbatim: "·")
                Text("#\(rank) this month").foregroundStyle(RhythmStyle.activity)
            }
        }
        .font(RhythmStyle.kicker)
        .textCase(.uppercase)
        .tracking(1.2)
        .foregroundStyle(.secondary)
    }

    /// How many workouts of this type started in the month or year up to and including this one.
    private func rank(in component: Calendar.Component) -> Int? {
        guard let log, let activity = workout.workoutActivity,
              let period = calendar.dateInterval(of: component, for: workout.start) else { return nil }
        let count = log.filter {
            $0.activity == activity && $0.start >= period.start && $0.start <= workout.start
        }.count
        return count > 0 ? count : nil
    }

    // MARK: Numbers

    private var stats: some View {
        let values = (heart ?? []).map(\.value).filter(\.isFinite)
        let average = values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        let duration = workout.workoutDuration ?? window.duration
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)],
                         alignment: .leading, spacing: 18) {
            WorkoutStat(title: Text("Duration"),
                        value: Duration.seconds(duration).formatted(.time(pattern: .hourMinuteSecond)))
            WorkoutStat(title: Text("Active Energy"), value: workout.activeEnergy.map(whole), unit: "kcal")
            WorkoutStat(title: Text("Average Heart Rate"), value: average.map(whole), unit: "BPM")
            WorkoutStat(title: Text("Maximum Heart Rate"), value: values.max().map(whole), unit: "BPM")
            if let recovery {
                WorkoutStat(title: Text("1-Minute Recovery"), value: whole(recovery), unit: "BPM")
            }
        }
        .rhythmCard()
    }

    private func whole(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)).locale(locale))
    }

    // MARK: Zones

    private var hasRecordedTimes: Bool {
        guard let zones, zones.source == .recorded else { return false }
        return zones.zones.allSatisfy { $0.duration != nil }
    }

    /// Recorded time in each zone when Health has it; otherwise the time between consecutive readings,
    /// capped at two minutes so a gap in the data isn't credited to one zone.
    private func zoneTimes(_ zones: WorkoutHeartRateZones) -> [Int: TimeInterval]? {
        if hasRecordedTimes {
            return Dictionary(uniqueKeysWithValues: zones.zones.map { ($0.id, max(0, $0.duration ?? 0)) })
        }
        guard let heart else { return nil }
        let sorted = heart.filter { $0.value.isFinite }.sorted { $0.time < $1.time }
        var times: [Int: TimeInterval] = [:]
        for (reading, next) in zip(sorted, sorted.dropFirst()) {
            guard let zone = zones.zone(for: reading.value) else { continue }
            times[zone.id, default: 0] += min(next.time.timeIntervalSince(reading.time), 120)
        }
        return times
    }

    private func zoneCard(_ zones: WorkoutHeartRateZones) -> some View {
        let times = zoneTimes(zones)
        let total = times?.values.reduce(0, +) ?? 0
        return TimelineCard(title: "Time in Zones", icon: "heart", tint: RhythmStyle.heart) {
            if let times, total > 0 {
                VStack(spacing: 10) {
                    ForEach(Array(zones.zones.reversed().enumerated()), id: \.element.id) { index, zone in
                        ZoneBar(zone: zone, seconds: times[zone.id] ?? 0, total: total, range: zoneRange(zone),
                                order: index)
                    }
                }
                Group {
                    if hasRecordedTimes {
                        Text("Recorded with this workout.")
                    } else {
                        Text("Estimated from heart rate readings.")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else if heart == nil {
                ProgressView().frame(maxWidth: .infinity)
            } else {
                Text("No heart rate samples for this workout.").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func zoneRange(_ zone: WorkoutHeartRateZones.Zone) -> String {
        let format = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0)).locale(locale)
        switch (zone.minimum, zone.maximum) {
        case let (low?, high?): return "\(low.formatted(format))–\(high.formatted(format))"
        case let (nil, high?): return "<\(high.formatted(format))"
        case let (low?, nil): return "\(low.formatted(format))+"
        default: return ""
        }
    }

    // MARK: Heart rate

    @ViewBuilder private var heartCard: some View {
        if let heart {
            if heart.isEmpty {
                TimelineCard(title: "Workout Heart Rate", icon: "heart", tint: RhythmStyle.heart) {
                    Text("No heart rate samples for this workout.").font(.footnote).foregroundStyle(.secondary)
                }
            } else {
                ReadingChart(title: "Workout Heart Rate", unit: "BPM", color: RhythmStyle.heart,
                             readings: heart, range: window, zoomsToRange: true,
                             workoutZones: zones, showsZoneKey: false)
            }
        } else {
            ProgressView("Loading Workout Heart Rate")
                .frame(maxWidth: .infinity, minHeight: 80)
        }
    }

    // MARK: Month

    private var monthCard: some View {
        TimelineCard(title: "This Month", icon: "calendar", tint: RhythmStyle.activity,
                     unitLabel: Text(workout.title)) {
            if let log {
                HStack(spacing: 16) {
                    WorkoutStat(title: Text(workout.start, format: .dateTime.month(.wide)),
                                value: rank(in: .month).map { "#\($0)" })
                    WorkoutStat(title: Text(workout.start, format: .dateTime.year()),
                                value: rank(in: .year).map { "#\($0)" })
                }
                MonthWorkoutGrid(current: workout, log: log) { day in
                    dismiss()
                    openWorkoutDay(day)
                }
                HStack(spacing: 14) {
                    ColorKeyItem(color: RhythmStyle.activity, text: Text(workout.title))
                    ColorKeyItem(color: RhythmStyle.activity.opacity(0.3), title: "Other Workouts")
                }
                Text("Tap a date to open its workouts.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if logLoaded {
                Text("Workout history is unavailable.").font(.footnote).foregroundStyle(.secondary)
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
    }
}
