import Foundation

enum OvernightMetric: String, CaseIterable, Identifiable {
    case heart, respiration, oxygen, temperature

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .heart: "Sleep Heart Rate"
        case .respiration: "Respiratory Rate"
        case .oxygen: "Blood Oxygen"
        case .temperature: "Wrist Temperature"
        }
    }

    var unit: String {
        switch self {
        case .heart: "BPM"
        case .respiration: "br/min"
        case .oxygen: "%"
        case .temperature: "°C"
        }
    }
}

struct RecoveryNight: Identifiable {
    let date: Date
    let sleep: [DateInterval]
    var hrv: Double?
    var hrvPressure: Int?
    var resting: Double?
    var vitals: [OvernightMetric: Double] = [:]

    var id: Date { date }
    var start: Date { sleep[0].start }
    var end: Date { sleep[sleep.count - 1].end }
    var hours: Double { sleep.reduce(0) { $0 + $1.duration } / 3600 }

    static func sessions(from intervals: [HealthInterval], calendar: Calendar, now: Date) -> [Self] {
        var sessions: [[DateInterval]] = []
        for interval in intervals.sorted(by: { $0.start < $1.start }) where interval.isAsleep && interval.start < interval.end {
            let segment = DateInterval(start: interval.start, end: interval.end)
            if let previous = sessions.last?.last,
               segment.start.timeIntervalSince(previous.end) <= 90 * 60 {
                if segment.start <= previous.end {
                    sessions[sessions.count - 1][sessions[sessions.count - 1].count - 1] =
                        DateInterval(start: previous.start, end: max(previous.end, segment.end))
                } else {
                    sessions[sessions.count - 1].append(segment)
                }
            } else {
                sessions.append([segment])
            }
        }
        let nights: [Self] = sessions.compactMap { segments in
            guard let end = segments.last?.end, end <= now else { return nil }
            return Self(date: calendar.startOfDay(for: end), sleep: segments)
        }
        return Dictionary(grouping: nights, by: \.date).values
            .compactMap { $0.max { $0.hours < $1.hours } }
            .sorted { $0.date < $1.date }
    }
}

struct RecoveryReport {
    let interval: DateInterval
    let previous: DateInterval
    let nights: [RecoveryNight]
    let daytime: [Date: Double]
    var resting: [Date: Double] = [:]
    var steps: [Date: Double] = [:]
    var workoutMinutes: [Date: Double] = [:]
    var unavailable: [LocalizedStringResource] = []

    var visible: [RecoveryNight] { nights.filter { $0.date >= interval.start && $0.date < interval.end } }

    func reference(for date: Date, calendar: Calendar, value: (RecoveryNight) -> Double?) -> ClosedRange<Double>? {
        let start = calendar.date(byAdding: .day, value: -30, to: date) ?? date
        return Self.reference(nights.filter { $0.date >= start && $0.date < date }.compactMap(value))
    }

    static func reference(_ values: [Double]) -> ClosedRange<Double>? {
        guard values.count >= 7 else { return nil }
        let sorted = values.sorted()
        return quantile(sorted, 0.1)...quantile(sorted, 0.9)
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return quantile(values.sorted(), 0.5)
    }

    private static func quantile(_ sorted: [Double], _ fraction: Double) -> Double {
        let index = Double(sorted.count - 1) * fraction
        let lower = Int(index.rounded(.down))
        let upper = Int(index.rounded(.up))
        return sorted[lower] + (sorted[upper] - sorted[lower]) * (index - Double(lower))
    }
}

extension HealthInterval {
    var isAsleep: Bool {
        switch sleepStage {
        case .asleep, .core, .deep, .rem: true
        default: false
        }
    }
}
