import Charts
import SwiftUI

struct SleepRecoveryView: View {
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    let report: RecoveryReport
    let openDay: (Date) -> Void
    @State private var selectedNight: Date?
    @State private var selectedHRV: Date?
    @State private var overnight = false
    @State private var showVitals = false

    private var dates: [Date] {
        let count = calendar.dateComponents([.day], from: report.interval.start, to: report.interval.end).day ?? 0
        return (0..<max(0, count)).compactMap {
            calendar.date(byAdding: .day, value: $0, to: report.interval.start)
        }
    }

    private var night: RecoveryNight? {
        if let selectedNight {
            return report.visible.first { $0.date == calendar.startOfDay(for: selectedNight) }
        }
        return report.visible.last
    }

    private var hasOvernightHRV: Bool { report.visible.contains { $0.hrv != nil } }
    private var showsOvernightHRV: Bool { overnight && hasOvernightHRV }

    private var hrvValues: [Date: Double] {
        showsOvernightHRV ? Dictionary(uniqueKeysWithValues: report.nights.compactMap { night in
            night.hrv.map { (night.date, $0) }
        }) : report.daytime
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            UnavailableMetrics(names: report.unavailable)
            if !report.visible.isEmpty {
                sleepTiming
            }
            hrvCard
            dailyContext(title: "Resting Heart Rate", unit: "BPM", values: report.resting, color: RhythmStyle.readingBlue)
            dailyContext(title: "Daily Steps", unit: "steps", values: report.steps, color: RhythmStyle.activity)
            if !report.visible.isEmpty {
                TimelineCard(title: "Overnight Vitals", icon: "moon", tint: RhythmStyle.sleep) {
                    DisclosureGroup("Show overnight measurements", isExpanded: $showVitals) {
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(OvernightMetric.allCases) { metric in
                                vitalChart(metric)
                            }
                            Text("Shading shows the 10th–90th percentiles from the prior 30 nights, using at least 7 nights with readings.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 12)
                    }
                }
            }
        }
        .sensoryFeedback(.selection, trigger: selectedNight)
    }

    private var sleepTiming: some View {
        TimelineCard(title: "Sleep & Recovery", icon: "bed.double", tint: RhythmStyle.sleep) {
            Text("\(report.visible.count) nights recorded")
                .font(.subheadline.weight(.semibold))
            Text("Sleep timing · by wake date")
                .font(.caption)
                .foregroundStyle(.secondary)
            VStack(spacing: 0) {
                HStack {
                    Text("18:00")
                    Spacer()
                    Text("00:00")
                    Spacer()
                    Text("06:00")
                    Spacer()
                    Text("12:00")
                    Spacer()
                    Text("18:00")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.leading, 48)
                let nightsByDate = Dictionary(uniqueKeysWithValues: report.visible.map { ($0.date, $0) })
                ForEach(dates.filter { $0 <= Date() }, id: \.self) { date in
                    sleepRow(date, entry: nightsByDate[date])
                }
            }
            if let night {
                selectedNightDetails(night)
            } else if let selectedNight {
                Text("No sleep recorded")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Open Day Timeline") { openDay(selectedNight) }
                    .font(.footnote.weight(.semibold))
            }
            sleepChange
        }
    }

    private func sleepRow(_ date: Date, entry: RecoveryNight?) -> some View {
        Button {
            withAnimation(RhythmMotion.select) { selectedNight = date }
        } label: {
            HStack(spacing: 8) {
                Text(date, format: .dateTime.month(.defaultDigits).day())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .leading)
                GeometryReader { geometry in
                    let width = geometry.size.width
                    ZStack(alignment: .leading) {
                        ForEach([0.25, 0.5, 0.75], id: \.self) { fraction in
                            Rectangle().fill(RhythmStyle.grid).frame(width: 1)
                                .offset(x: width * fraction)
                        }
                        if let entry {
                            ForEach(entry.sleep, id: \.start) { interval in
                                let start = sleepFraction(interval.start, relativeTo: date)
                                let end = sleepFraction(interval.end, relativeTo: date)
                                Capsule().fill(RhythmStyle.sleep.opacity(night?.date == date ? 1 : 0.62))
                                    .frame(width: max(0, (end - start) * width), height: 8)
                                    .offset(x: start * width)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                }
            }
            .frame(minHeight: report.interval.duration > 8 * 86400 ? 19 : 32)
            .padding(.horizontal, 4)
            .background(night?.date == date ? RhythmStyle.track : .clear, in: RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(date, format: .dateTime.month().day().weekday()))
        .accessibilityValue(entry.map { Text("\($0.hours.formatted(.number.precision(.fractionLength(1)))) h") } ?? Text("No sleep recorded"))
        .accessibilityAddTraits(night?.date == date ? .isSelected : [])
    }

    private func sleepFraction(_ time: Date, relativeTo date: Date) -> Double {
        let day = calendar.startOfDay(for: time)
        let offset = calendar.dateComponents([.day], from: date, to: day).day ?? 0
        let hour = calendar.component(.hour, from: time)
        let minute = calendar.component(.minute, from: time)
        return min(1, max(0, (Double(offset * 24 + hour + 6) + Double(minute) / 60) / 24))
    }

    private func selectedNightDetails(_ night: RecoveryNight) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                openDay(night.date)
            } label: {
                HStack {
                    Text(night.date, format: .dateTime.weekday(.abbreviated).month().day())
                    Spacer()
                    Text("Open Day Timeline")
                    Image(systemName: "chevron.right").font(.caption2)
                }
                .font(.footnote.weight(.semibold))
            }
            LabeledContent("Sleep") {
                Text(night.start, format: .dateTime.hour().minute())
                Text("–")
                Text(night.end, format: .dateTime.hour().minute())
                Text("· \(night.hours.formatted(.number.precision(.fractionLength(1)))) h")
            }
            LabeledContent("Overnight HRV") {
                metricValue(night.hrv, unit: "ms").foregroundStyle(PressureBand.color(for: night.hrvPressure))
            }
            LabeledContent("Resting Heart Rate") {
                metricValue(night.resting, unit: "BPM").foregroundStyle(RhythmStyle.readingBlue)
            }
        }
        .font(.footnote)
    }

    @ViewBuilder private var sleepChange: some View {
        let elapsedDays = dates.filter { $0 <= Date() }.count
        let previousEnd = calendar.date(byAdding: .day, value: elapsedDays, to: report.previous.start) ?? report.previous.end
        let previous = report.nights.filter { $0.date >= report.previous.start && $0.date < previousEnd }
        if !report.visible.isEmpty, !previous.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Text("Median change vs. previous period · \(report.visible.count) / \(previous.count) nights")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                change("Sleep", current: report.visible.map(\.hours), previous: previous.map(\.hours), unit: "h")
                change("Overnight HRV", current: report.visible.compactMap(\.hrv), previous: previous.compactMap(\.hrv), unit: "ms")
                change("Resting Heart Rate", current: report.visible.compactMap(\.resting), previous: previous.compactMap(\.resting), unit: "BPM")
            }
            .font(.caption)
        }
    }

    @ViewBuilder private func change(_ title: LocalizedStringKey, current: [Double], previous: [Double], unit: String) -> some View {
        if let value = RecoveryReport.median(current), let base = RecoveryReport.median(previous) {
            LabeledContent(title) {
                Text("\((value - base).formatted(.number.sign(strategy: .always(includingZero: false)).precision(.fractionLength(0...1)).locale(locale))) \(unit)")
                Text("· \(current.count)/\(previous.count)")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func precedingDates(_ days: Int, before date: Date) -> Range<Date> {
        (calendar.date(byAdding: .day, value: -days, to: date) ?? date)..<date
    }

    private var hrvCard: some View {
        TimelineCard(title: "HRV Trend", icon: "waveform.path", tint: RhythmStyle.hrvTone, unitLabel: Text("ms")) {
            if hasOvernightHRV {
                Picker("HRV Period", selection: $overnight.animation(RhythmMotion.select)) {
                    Text("Daytime").tag(false)
                    Text("Overnight").tag(true)
                }
                .pickerStyle(.segmented)
                .sensoryFeedback(.selection, trigger: overnight)
                .onChange(of: overnight) { _, _ in selectedHRV = nil }
            } else {
                Text("Daytime").font(.subheadline.weight(.semibold))
            }
            let comparison = periodComparison(hrvValues)
            if let median = RecoveryReport.median(comparison.current) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(median, format: .number.precision(.fractionLength(0...1)))
                        .font(RhythmStyle.display(29))
                    Text("Median").font(.caption).foregroundStyle(.secondary)
                }
                change("Median vs. previous period", current: comparison.current,
                       previous: comparison.earlier, unit: "ms").font(.caption)
            }
            hrvChart(values: hrvValues)
        }
    }

    @ViewBuilder private func hrvChart(values: [Date: Double]) -> some View {
        let points = dates.filter { values[$0] != nil }
        let selected = selectedHRV.map { calendar.startOfDay(for: $0) } ?? points.last
        if points.isEmpty {
            Text("No daily HRV medians in this period.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            let ranges = Dictionary(uniqueKeysWithValues: points.compactMap { date in
                RecoveryReport.reference(values.filter { precedingDates(30, before: date).contains($0.key) }.map(\.value))
                    .map { (date, $0) }
            })
            Chart {
                ForEach(dates, id: \.self) { date in
                    if let range = ranges[date],
                       let end = calendar.date(byAdding: .day, value: 1, to: date) {
                        RectangleMark(xStart: .value("Day", date), xEnd: .value("Day", end),
                                      yStart: .value("Low", range.lowerBound), yEnd: .value("High", range.upperBound))
                            .foregroundStyle(RhythmStyle.readingBlue.opacity(0.12))
                    }
                }
                ForEach(points, id: \.self) { date in
                    if let value = values[date] {
                        PointMark(x: .value("Day", date, unit: .day), y: .value("HRV (ms)", value))
                            .foregroundStyle(RhythmStyle.readingBlue)
                    }
                    if let end = calendar.date(byAdding: .day, value: 1, to: date) {
                        let pool = values.filter { precedingDates(7, before: end).contains($0.key) }.map(\.value)
                        if pool.count >= 4, let median = RecoveryReport.median(pool) {
                            RectangleMark(xStart: .value("Day", date), xEnd: .value("Day", end),
                                          yStart: .value("Median", median - 0.2), yEnd: .value("Median", median + 0.2))
                                .foregroundStyle(RhythmStyle.sleep)
                                .accessibilityLabel("7-day median")
                                .accessibilityValue(Text("\(median.formatted(.number.precision(.fractionLength(0...1)))) ms"))
                        }
                    }
                }
                if let selected {
                    RuleMark(x: .value("Selected Day", selected, unit: .day))
                        .foregroundStyle(.secondary.opacity(0.4))
                }
            }
            .chartXScale(domain: report.interval.start...report.interval.end)
            .chartYScale(domain: .automatic(includesZero: false))
            .chartXSelection(value: $selectedHRV)
            .frame(height: 160)
            if let selected, selected < report.interval.end, selected <= Date() {
                Button {
                    openDay(selected)
                } label: {
                    HStack {
                        Text(selected, format: .dateTime.month().day())
                        metricValue(values[selected], unit: "ms")
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption2)
                    }
                }
                .font(.caption.weight(.semibold))
                .accessibilityHint("Opens the day timeline")
                if report.resting[selected] != nil || report.steps[selected] != nil || report.workoutMinutes[selected] != nil {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) { dayContext(selected) }
                        VStack(alignment: .leading, spacing: 4) { dayContext(selected) }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            Text("\(points.count) of \(dates.filter { $0 <= Date() }.count) days · Purple: 7-day median · Shading: prior 30-day range")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        Text(showsOvernightHRV ? "At least 2 readings during the main sleep session." :
             "At least 2 readings from 06:00–22:00, excluding recorded sleep and workouts.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder private func dayContext(_ date: Date) -> some View {
        let format = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0)).locale(locale)
        if let heart = report.resting[date] {
            Text("Resting \(heart.formatted(format)) BPM")
        }
        if let steps = report.steps[date] {
            Text("\(steps.formatted(format)) steps")
        }
        if let minutes = report.workoutMinutes[date] {
            Text("\(minutes.formatted(format)) min trained")
        }
    }

    private func periodComparison(_ values: [Date: Double]) -> (current: [Double], earlier: [Double]) {
        let today = calendar.startOfDay(for: Date())
        let completed = dates.filter { $0 < today }
        let previousEnd = calendar.date(byAdding: .day, value: completed.count, to: report.previous.start) ?? report.previous.start
        let earlier = values.filter { $0.key >= report.previous.start && $0.key < previousEnd }.map(\.value)
        return (completed.compactMap { values[$0] }, earlier)
    }

    private func dailyContext(
        title: LocalizedStringKey, unit: String, values: [Date: Double], color: Color
    ) -> some View {
        let today = calendar.startOfDay(for: Date())
        let observed = dates.filter { values[$0] != nil }
        let (current, earlier) = periodComparison(values)
        return TimelineCard(title: title, icon: "chart.bar", tint: color, unitLabel: Text(verbatim: unit)) {
            if observed.isEmpty {
                Text("No measurements in this period.").font(.footnote).foregroundStyle(.secondary)
            } else {
                if let median = RecoveryReport.median(current) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(median, format: .number.precision(.fractionLength(0)))
                            .font(RhythmStyle.display(29))
                        Text("Median").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Chart {
                    ForEach(observed, id: \.self) { day in
                        if let value = values[day] {
                            if unit == "steps" {
                                BarMark(x: .value("Day", day, unit: .day), y: .value("Steps", value))
                                    .foregroundStyle(color.opacity(day == today ? 0.4 : 0.86))
                            } else {
                                PointMark(x: .value("Day", day, unit: .day), y: .value("Resting Heart Rate", value))
                                    .foregroundStyle(color)
                            }
                        }
                    }
                }
                .chartXScale(domain: report.interval.start...report.interval.end)
                .chartYScale(domain: .automatic(includesZero: unit == "steps"))
                .frame(height: 116)
                change("Median vs. previous period", current: current, previous: earlier, unit: unit)
                    .font(.caption)
                if observed.contains(today) {
                    Text("\(observed.count) days recorded · Today so far").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("\(observed.count) days recorded").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func vitalChart(_ metric: OvernightMetric) -> some View {
        let values = report.visible.compactMap { night -> (RecoveryNight, Double, ClosedRange<Double>?)? in
            guard let value = night.vitals[metric] else { return nil }
            let range = report.reference(for: night.date, calendar: calendar) { $0.vitals[metric] }
            return (night, value, range)
        }
        let date = selectedNight.map { calendar.startOfDay(for: $0) } ?? night?.date
        let selected = values.first { $0.0.date == date }
        return VStack(alignment: .leading, spacing: 6) {
            LabeledContent {
                metricValue(selected?.1, unit: metric.unit)
            } label: {
                Text(metric.title)
            }
            .font(.footnote.weight(.semibold))
            if values.isEmpty {
                Text("No measurements in this period.").font(.caption).foregroundStyle(.secondary)
            } else {
                Chart {
                    ForEach(values, id: \.0.id) { entry in
                        let (night, value, range) = entry
                        if let range, let end = calendar.date(byAdding: .day, value: 1, to: night.date) {
                            RectangleMark(xStart: .value("Day", night.date), xEnd: .value("Day", end),
                                          yStart: .value("Low", range.lowerBound), yEnd: .value("High", range.upperBound))
                                .foregroundStyle(RhythmStyle.sleep.opacity(0.12))
                        }
                        let outside = range.map { !$0.contains(value) } ?? false
                        PointMark(x: .value("Day", night.date, unit: .day), y: .value("Measurement", value))
                            .symbol(outside ? .diamond : .circle)
                            .foregroundStyle(outside ? RhythmStyle.activity : RhythmStyle.sleep)
                    }
                    if let date {
                        RuleMark(x: .value("Selected Night", date, unit: .day))
                            .foregroundStyle(.secondary.opacity(0.4))
                    }
                }
                .chartXScale(domain: report.interval.start...report.interval.end)
                .chartYScale(domain: .automatic(includesZero: false))
                .chartXSelection(value: $selectedNight)
                .frame(height: 104)
                if let range = selected?.2, let value = selected?.1 {
                    let format = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...1))
                    LabeledContent {
                        Text("\(range.lowerBound.formatted(format))–\(range.upperBound.formatted(format)) \(metric.unit)")
                    } label: {
                        Text(value < range.lowerBound ? "Below personal range" :
                             value > range.upperBound ? "Above personal range" : "Within personal range")
                    }
                    .font(.caption)
                    .foregroundStyle(range.contains(value) ? Color.secondary : RhythmStyle.activity)
                } else if selected != nil {
                    Text("Building personal range").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func metricValue(_ value: Double?, unit: String) -> Text {
        guard let value else { return Text("—").foregroundStyle(.secondary) }
        return Text("\(value.formatted(.number.precision(.fractionLength(0...1)).locale(locale))) \(unit)")
    }
}
