import Foundation

struct HealthReading: Identifiable {
    struct ID: Hashable {
        let sample: UUID
        let start: Date
        let end: Date
        let value: Double
        let occurrence: Int
    }

    let id: ID
    let source: String
    let sourceID: String

    var time: Date { id.start }
    var value: Double { id.value }
}

struct HealthInterval: Identifiable {
    let id: UUID
    let start: Date
    let end: Date
    let title: LocalizedStringResource
    let source: String
    var workoutDuration: TimeInterval? = nil
    var workoutZones: WorkoutHeartRateZones? = nil
    var sleepStage: SleepStage? = nil
    /// `HKWorkoutActivityType` raw value, for workouts.
    var workoutActivity: UInt? = nil
    /// Active energy in kilocalories, for workouts.
    var activeEnergy: Double? = nil

    func clipped(to range: DateInterval) -> DateInterval? {
        let clippedStart = max(start, range.start)
        let clippedEnd = min(end, range.end)
        guard clippedStart < clippedEnd else { return nil }
        return DateInterval(start: clippedStart, end: clippedEnd)
    }
}

struct DayReport {
    let day: DateInterval
    let heartRate: [HealthReading]
    let hrv: [HealthReading]
    let hrvAssessments: [HealthReading.ID: HRVAssessment]
    let dailyHRV: HRVDailyScore?
    let restingHeartRate: [HealthReading]
    let sleep: [HealthInterval]
    let workouts: [HealthInterval]
    var preferredWorkoutZones: WorkoutHeartRateZones? = nil
    var overnightHRV: HRVDailyScore? = nil
    /// Middle half of the scoring source's daily medians over the reference window.
    var hrvBaseline: ClosedRange<Double>? = nil
    let steps: [MetricBucket]
    let unavailable: [LocalizedStringResource]
}

struct MetricBucket: Identifiable {
    let interval: DateInterval
    let value: Double

    var id: Date { interval.start }
    var midpoint: Date { interval.start.addingTimeInterval(interval.duration / 2) }
}

struct TrendReport {
    let interval: DateInterval
    let heartRate: [MetricBucket]
    let hrv: [MetricBucket]
    let restingHeartRate: [MetricBucket]
    let dailyHRV: [Date: HRVDailyScore]
    let unavailable: [LocalizedStringResource]
}

enum HRVAssessment {
    case score(Int, referenceDays: Int)
    case insufficientHistory(Int)
    case outsideDaytime
    case duringSleepOrWorkout
    case unavailable

    static func canScore(_ reading: HealthReading, calendar: Calendar) -> Bool {
        (6..<22).contains(calendar.component(.hour, from: reading.time))
    }

    static func overlaps(_ reading: HealthReading, intervals: [HealthInterval]) -> Bool {
        intervals.contains { interval in
            reading.time < interval.end &&
                (reading.time >= interval.start || reading.id.end > interval.start)
        }
    }

    static func compare(_ value: Double, to dailyMedians: [Double]) -> Self {
        guard value.isFinite, value > 0 else { return .unavailable }
        guard dailyMedians.count >= 7 else { return .insufficientHistory(dailyMedians.count) }
        let above = dailyMedians.filter { $0 > value }.count
        let equal = dailyMedians.filter { $0 == value }.count
        let rank = (Double(above) + 0.5 * Double(equal)) / Double(dailyMedians.count)
        return .score(1 + Int((99 * rank).rounded()), referenceDays: dailyMedians.count)
    }

    /// Ranks one reading against individual readings, not daily medians. A single reading varies far more
    /// than a day's median, so ranking it against medians pushed most readings to the extremes.
    static func compare(_ value: Double, toReadings pool: [Double], days: Int) -> Self {
        guard value.isFinite, value > 0 else { return .unavailable }
        guard days >= 7, !pool.isEmpty else { return .insufficientHistory(days) }
        let above = pool.filter { $0 > value }.count
        let equal = pool.filter { $0 == value }.count
        let rank = (Double(above) + 0.5 * Double(equal)) / Double(pool.count)
        return .score(1 + Int((99 * rank).rounded()), referenceDays: days)
    }
}

struct HRVDailySamples {
    let median: Double
    let count: Int
    let source: String
    let values: [Double]

    init?(readings: [HealthReading]) {
        guard let first = readings.first else { return nil }
        let values = readings.map(\.value).sorted()
        self.values = values
        let middle = values.count / 2
        median = values.count.isMultiple(of: 2)
            ? values[middle - 1] / 2 + values[middle] / 2
            : values[middle]
        count = readings.count
        source = first.source
    }
}

struct HRVDailyScore {
    let day: DateInterval
    let samples: HRVDailySamples
    let assessment: HRVAssessment

    var score: Int? {
        if case let .score(value, _) = assessment { return value }
        return nil
    }

    var bucket: MetricBucket? {
        score.map { MetricBucket(interval: day, value: Double($0)) }
    }

    static func daytimeMedians(_ daily: [Date: HRVDailyScore]) -> [MetricBucket] {
        daily.values.filter { $0.samples.count >= 2 }
            .map { MetricBucket(interval: $0.day, value: $0.samples.median) }
            .sorted { $0.id < $1.id }
    }
}

struct HRVHistory {
    static let referenceLength = 30
    let samples: [String: [Date: HRVDailySamples]]

    func reference(for source: String, on day: Date, calendar: Calendar) -> [Double] {
        guard let start = calendar.date(byAdding: .day, value: -Self.referenceLength, to: day),
              let days = samples[source] else { return [] }
        return days.compactMap { date, entry in
            date >= start && date < day ? entry.median : nil
        }
    }

    /// Every eligible reading from the reference window, and how many days they span.
    func readingReference(for source: String, on day: Date, calendar: Calendar) -> (values: [Double], days: Int) {
        guard let start = calendar.date(byAdding: .day, value: -Self.referenceLength, to: day),
              let days = samples[source] else { return ([], 0) }
        let entries = days.filter { $0.key >= start && $0.key < day }.values
        return (entries.flatMap(\.values), entries.count)
    }

    func dailyScore(
        for day: DateInterval, current: [String: HRVDailySamples], calendar: Calendar
    ) -> HRVDailyScore? {
        let candidates = current.sorted { lhs, rhs in
            if lhs.value.count == rhs.value.count { return lhs.key < rhs.key }
            return lhs.value.count > rhs.value.count
        }
        var mostReadings: HRVDailyScore?
        for (source, entry) in candidates {
            let result = HRVDailyScore(day: day, samples: entry, assessment: HRVAssessment.compare(
                entry.median, to: reference(for: source, on: day.start, calendar: calendar)
            ))
            if result.score != nil { return result }
            if mostReadings == nil { mostReadings = result }
        }
        return mostReadings
    }
}

struct WorkoutHeartRateRange: Identifiable {
    let id: Int
    let time: Date
    let low: Double
    let high: Double

    static func make(
        from readings: [HealthReading], within interval: DateInterval, bucketCount: Int = 18
    ) -> [Self] {
        guard interval.duration > 0, bucketCount > 0 else { return [] }
        let bucketDuration = interval.duration / Double(bucketCount)
        let included = readings.filter {
            $0.time >= interval.start && $0.time < interval.end && $0.value.isFinite
        }
        let bins = Dictionary(grouping: included) { reading in
            min(bucketCount - 1, Int(reading.time.timeIntervalSince(interval.start) / bucketDuration))
        }
        return bins.keys.sorted().compactMap { index in
            guard let readings = bins[index],
                  let low = readings.map(\.value).min(), let high = readings.map(\.value).max()
            else { return nil }
            let midpoint = interval.start.addingTimeInterval((Double(index) + 0.5) * bucketDuration)
            return Self(id: index, time: midpoint, low: low, high: high)
        }
    }
}


enum HeartHistoryMetric: String, Identifiable {
    case hrv, restingHeartRate

    var id: String { rawValue }
}


enum SleepStage: CaseIterable {
    case inBed, awake, core, deep, rem, asleep, other

    var title: LocalizedStringResource {
        switch self {
        case .inBed: "In Bed"
        case .awake: "Awake"
        case .core: "Core Sleep"
        case .deep: "Deep Sleep"
        case .rem: "REM Sleep"
        case .asleep: "Sleep"
        case .other: "Sleep Record"
        }
    }
}

struct ReadingComparison {
    enum Band: CaseIterable {
        case below, middle, above, unavailable
    }

    let middleHalf: ClosedRange<Double>?

    init(_ values: [Double]) {
        let sorted = values.filter(\.isFinite).sorted()
        guard sorted.count >= 4 else {
            middleHalf = nil
            return
        }
        func percentile(_ fraction: Double) -> Double {
            let index = Double(sorted.count - 1) * fraction
            let lower = Int(index.rounded(.down))
            let upper = Int(index.rounded(.up))
            let weight = index - Double(lower)
            return sorted[lower] * (1 - weight) + sorted[upper] * weight
        }
        middleHalf = percentile(0.25)...percentile(0.75)
    }

    func band(for value: Double) -> Band {
        guard let middleHalf, value.isFinite else { return .unavailable }
        if value < middleHalf.lowerBound { return .below }
        if value > middleHalf.upperBound { return .above }
        return .middle
    }
}


struct WorkoutHeartRateZones {
    enum Source { case recorded, preferred, manual }

    struct Zone: Identifiable {
        let id: Int
        let minimum: Double?
        let maximum: Double?
        let duration: TimeInterval?
    }

    struct Segment: Identifiable {
        let zone: Zone
        let low: Double
        let high: Double

        var id: Int { zone.id }
    }

    let zones: [Zone]
    let source: Source

    init?(boundaries: [Double], durations: [TimeInterval?], source: Source) {
        guard !boundaries.isEmpty, boundaries.allSatisfy({ $0.isFinite && $0 > 0 }),
              zip(boundaries, boundaries.dropFirst()).allSatisfy({ $0 < $1 }),
              durations.count == boundaries.count + 1 else { return nil }
        zones = durations.enumerated().map { index, duration in
            Zone(id: index + 1,
                 minimum: index == 0 ? nil : boundaries[index - 1],
                 maximum: index == boundaries.count ? nil : boundaries[index],
                 duration: duration)
        }
        self.source = source
    }

    init?(manualBoundaries: String) {
        let parts = manualBoundaries.split(separator: ",", omittingEmptySubsequences: false)
        let values = parts.compactMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        guard parts.count == 4, values.count == 4 else { return nil }
        self.init(boundaries: values, durations: Array(repeating: nil, count: 5), source: .manual)
    }

    func zone(for value: Double) -> Zone? {
        guard value.isFinite, value > 0 else { return nil }
        return zones.first { $0.maximum.map { value < $0 } ?? true }
    }

    func segments(low: Double, high: Double) -> [Segment] {
        guard low.isFinite, high.isFinite, low > 0, low < high else { return [] }
        return zones.compactMap { zone in
            let start = max(low, zone.minimum ?? low)
            let end = min(high, zone.maximum ?? high)
            guard start < end else { return nil }
            return Segment(zone: zone, low: start, high: end)
        }
    }
}

/// Sleep and workout times merged into sorted, non-overlapping ranges, so "is this reading inside one?"
/// is a binary search instead of a scan over every interval.
struct IntervalIndex {
    private var ranges: [(start: Date, end: Date)] = []

    init(_ intervals: [HealthInterval]) {
        for item in intervals.sorted(by: { $0.start < $1.start }) {
            if let last = ranges.last, item.start <= last.end {
                ranges[ranges.count - 1].end = max(last.end, item.end)
            } else {
                ranges.append((item.start, item.end))
            }
        }
    }

    /// Same rule as `HRVAssessment.overlaps(_:intervals:)`.
    func overlaps(_ reading: HealthReading) -> Bool {
        var low = 0
        var high = ranges.count
        while low < high {
            let mid = (low + high) / 2
            if ranges[mid].end > reading.time { high = mid } else { low = mid + 1 }
        }
        guard low < ranges.count else { return false }
        let range = ranges[low]
        return reading.time >= range.start || reading.id.end > range.start
    }
}

extension Array where Element == HealthReading {
    /// For readings sorted by time: those starting in `start..<end`, found by binary search.
    func sortedSlice(from start: Date, to end: Date) -> ArraySlice<HealthReading> {
        func firstIndex(atOrAfter date: Date) -> Int {
            var low = 0
            var high = count
            while low < high {
                let mid = (low + high) / 2
                if self[mid].time < date { low = mid + 1 } else { high = mid }
            }
            return low
        }
        let lower = firstIndex(atOrAfter: start)
        let upper = Swift.max(lower, firstIndex(atOrAfter: end))
        return self[lower..<upper]
    }
}
