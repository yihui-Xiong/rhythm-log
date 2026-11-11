import Charts
import HealthKit
import SwiftUI

struct TrainingView: View {
    @Environment(\.locale) private var locale
    @Environment(\.calendar) private var calendar
    let report: TrainingReport
    let health: HealthStore
    @State private var selectedWeek: Date?
    @State private var selection: String?
    @State private var selectedWorkout: TrainingWorkout?
    @State private var showWorkouts = false
    @State private var barsGrown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var week: TrainingWeek? {
        report.weeks.first { $0.id == selectedWeek } ?? report.weeks.last
    }

    private var groups: [[TrainingWorkout]] {
        Dictionary(grouping: report.workouts, by: groupKey).values.map {
            $0.sorted { $0.interval.start < $1.interval.start }
        }
        .sorted { lhs, rhs in
            let left = lhs[0]
            let right = rhs[0]
            if left.activity == .running && right.activity != .running { return true }
            if right.activity == .running && left.activity != .running { return false }
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return groupKey(left) < groupKey(right)
        }
    }

    var body: some View {
        volume
        if !report.workouts.isEmpty {
            performance
        }
    }

    private var volume: some View {
        TimelineCard(title: "Training Volume", icon: "figure.run", tint: RhythmStyle.activity, unitLabel: Text("min")) {
            if report.available, let week, let latest = report.weeks.last {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(week.total, format: .number.precision(.fractionLength(0)))
                            .font(RhythmStyle.display(34))
                            .contentTransition(.numericText())
                        Text("min").font(.footnote).foregroundStyle(.secondary)
                        Spacer()
                        weekDates(week)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if week.id == latest.id {
                        Text("Last 7 completed days")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let index = report.weeks.firstIndex(where: { $0.id == week.id }), index > 0 {
                        comparison(week, previous: report.weeks[index - 1])
                    }
                }

                volumeChart(week)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { sportLegend }
                    VStack(alignment: .leading, spacing: 6) { sportLegend }
                }

                if week.workouts.isEmpty {
                    Text("No workouts recorded in these 7 days.").font(.footnote).foregroundStyle(.secondary)
                } else {
                    DisclosureGroup(isExpanded: $showWorkouts) {
                        VStack(spacing: 0) {
                            ForEach(week.workouts.reversed()) { workout in
                                Button {
                                    selectedWorkout = workout
                                } label: {
                                    WorkoutRow(workout: workout.interval, showsDay: true)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.top, 6)
                    } label: {
                        Text("\(week.workouts.count) workouts").font(.footnote.weight(.semibold))
                    }
                }
            } else {
                Text("Training records are unavailable.").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .sheet(item: $selectedWorkout) { workout in
            TrainingWorkoutDetail(workout: workout, health: health)
        }
        .sensoryFeedback(.selection, trigger: selectedWeek)
        .sensoryFeedback(.impact(weight: .light), trigger: selectedWorkout?.id)
        .onAppear {
            withAnimation(RhythmMotion.grow.delay(0.2)) { barsGrown = true }
        }
    }

    private func comparison(_ week: TrainingWeek, previous: TrainingWeek) -> some View {
        let changes = TrainingSport.allCases.map { ($0, week.minutes(for: $0) - previous.minutes(for: $0)) }
        let largest = changes.max { abs($0.1) < abs($1.1) }
        let earlier = report.weeks.filter { $0.id < week.id }
        let history = earlier.drop(while: { $0.workouts.isEmpty })
        let typical = history.count >= 3 ? RecoveryReport.median(history.map(\.total)) : nil
        return VStack(alignment: .leading, spacing: 4) {
            Text("\(signedMinutes(week.total - previous.total)) min vs. previous 7 days")
                .font(.footnote.weight(.semibold))
            if let (sport, minutes) = largest, abs(minutes) >= 0.5 {
                Text("Largest change: \(sport.title.localized(in: locale)) (\(signedMinutes(minutes)) min)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let typical {
                Text("\(signedMinutes(week.total - typical)) min vs. typical week · median of \(history.count) weeks")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func signedMinutes(_ value: Double) -> String {
        value.rounded().formatted(.number.sign(strategy: .always(includingZero: false)).precision(.fractionLength(0)).locale(locale))
    }

    private func weekDates(_ week: TrainingWeek) -> Text {
        let end = calendar.date(byAdding: .day, value: -1, to: week.range.end) ?? week.range.end
        return Text(week.range.start..<end, format: .interval.month(.abbreviated).day())
    }

    private func volumeChart(_ current: TrainingWeek) -> some View {
        let maximum = max(1, report.weeks.map(\.total).max() ?? 0)
        return HStack(alignment: .bottom, spacing: 6) {
            ForEach(report.weeks) { week in
                Button {
                    withAnimation(RhythmMotion.select) {
                        selectedWeek = week.id
                        showWorkouts = true
                    }
                } label: {
                    VStack(spacing: 6) {
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 5).fill(RhythmStyle.track)
                            VStack(spacing: 0) {
                                ForEach(TrainingSport.allCases.reversed(), id: \.self) { sport in
                                    if week.minutes(for: sport) > 0 {
                                        Rectangle().fill(sportColor(sport))
                                            .frame(height: 100 * week.minutes(for: sport) / maximum
                                                   * (barsGrown || reduceMotion ? 1 : 0))
                                    }
                                }
                            }
                            .clipShape(.rect(cornerRadius: 5))
                            .opacity(week.id == current.id ? 1 : 0.53)
                        }
                        .frame(height: 100)
                        Text(week.range.start, format: .dateTime.day())
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(week.id == current.id ? Color.primary : .secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(weekDates(week))
                .accessibilityValue(Text("\(week.total.formatted(.number.precision(.fractionLength(0)))) min"))
                .accessibilityAddTraits(week.id == current.id ? .isSelected : [])
                .accessibilityHint("Shows workouts in these 7 days")
            }
        }
        .accessibilityLabel("Eight weeks of training minutes by sport")
    }

    @ViewBuilder private var sportLegend: some View {
        ForEach(TrainingSport.allCases.filter { sport in report.workouts.contains { $0.sport == sport } }, id: \.self) { sport in
            Label {
                Text(sport.title)
            } icon: {
                Circle().fill(sportColor(sport)).frame(width: 7, height: 7)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func sportColor(_ sport: TrainingSport) -> Color {
        sport.color
    }

    private var performance: some View {
        let groups = groups
        let current = groups.first { $0.first.map(groupKey) == selection } ?? groups.first ?? []
        return TimelineCard(title: "Training Performance", icon: "chart.xyaxis.line", tint: RhythmStyle.activity) {
            if let first = current.first {
                Menu {
                    ForEach(groups.compactMap(\.first)) { sample in
                        Button { withAnimation(RhythmMotion.select) { selection = groupKey(sample) } } label: {
                            groupLabel(sample)
                        }
                    }
                } label: {
                    HStack {
                        groupLabel(first)
                        Spacer()
                        Image(systemName: "chevron.down")
                    }
                    .font(.footnote.weight(.semibold))
                }
                paceChart(current)
                Divider()
                recoveryChart(current)
            }
        }
    }

    private func groupKey(_ workout: TrainingWorkout) -> String {
        let setting = workout.indoor.map { $0 ? "indoor" : "outdoor" } ?? "unknown"
        return "\(workout.activity.rawValue)-\(setting)"
    }

    private func groupLabel(_ workout: TrainingWorkout) -> Text {
        let title = Text(workout.interval.title)
        if workout.indoor == true { return title + Text(" · Indoor") }
        if workout.indoor == false { return title + Text(" · Outdoor") }
        return title
    }

    @ViewBuilder private func paceChart(_ workouts: [TrainingWorkout]) -> some View {
        Text("Pace and Average Heart Rate").font(.subheadline.weight(.semibold))
        let points = workouts.filter { $0.pace != nil && $0.averageHeartRate != nil }
        if points.isEmpty {
            Text("No workouts with both distance and average heart rate.").font(.caption).foregroundStyle(.secondary)
        } else {
            Chart(points) { workout in
                if let pace = workout.pace, let heart = workout.averageHeartRate {
                    PointMark(x: .value("Pace", pace), y: .value("Average Heart Rate", heart))
                        .foregroundStyle(workout.id == points.last?.id ? RhythmStyle.activity : RhythmStyle.readingBlue)
                        .symbolSize(workout.id == points.last?.id ? 74 : 36)
                        .accessibilityLabel(Text(workout.interval.start, format: .dateTime.month().day().hour().minute()))
                        .accessibilityValue(Text("\(paceLabel(pace)) min/km · \(heart.formatted(.number.precision(.fractionLength(0)))) BPM"))
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let pace = value.as(Double.self) { Text(paceLabel(pace)) }
                    }
                }
            }
            .chartXAxisLabel("Pace (min/km)")
            .chartYAxisLabel("BPM")
            .chartXScale(domain: .automatic(includesZero: false))
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(height: 155)
            Text("\(points.count) of \(workouts.count) workouts · Orange: latest with pace and heart rate")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let latest = points.last, let pace = latest.pace, let heart = latest.averageHeartRate {
                let comparable = points.dropLast().filter { abs(($0.pace ?? .infinity) - pace) <= 15 }
                if let typical = RecoveryReport.median(comparable.compactMap(\.averageHeartRate)) {
                    Text("Latest: \(signedMinutes(heart - typical)) BPM vs. median of \(comparable.count) earlier workouts within 15 sec/km.")
                        .font(.footnote)
                } else {
                    Text("No earlier workout within 15 sec/km of the latest pace.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func paceLabel(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0, seconds < Double(Int.max / 2) else { return "—" }
        let rounded = Int(seconds.rounded())
        return Duration.seconds(rounded).formatted(.time(pattern: .minuteSecond))
    }

    @ViewBuilder private func recoveryChart(_ workouts: [TrainingWorkout]) -> some View {
        Text("1-Minute Heart Rate Recovery").font(.subheadline.weight(.semibold))
        let points = workouts.filter { $0.recovery != nil }
        if points.isEmpty {
            Text("No Apple Health recovery samples matched these workouts.").font(.caption).foregroundStyle(.secondary)
        } else {
            Chart {
                ForEach(points) { workout in
                    if let recovery = workout.recovery {
                        PointMark(x: .value("Date", workout.interval.start), y: .value("Heart Rate Drop", recovery))
                            .foregroundStyle(RhythmStyle.sleep)
                    }
                }
            }
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
            .chartYAxisLabel("BPM drop")
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(height: 130)
            Text("\(points.count) of \(workouts.count) workouts · Recorded by Apple Health")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let latest = points.last?.recovery, let typical = RecoveryReport.median(points.dropLast().compactMap(\.recovery)) {
                Text("Latest: \(signedMinutes(latest - typical)) BPM vs. median of \(points.count - 1) earlier workouts.")
                    .font(.footnote)
            }
        }
    }
}
