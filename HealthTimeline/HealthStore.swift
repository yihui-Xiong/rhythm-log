import Foundation
import HealthKit

/// Per-day HRV medians for finished days, kept for the app session.
private actor HRVHistoryCache {
    private var entries: [Date: [String: HRVDailySamples]] = [:]

    func days(_ dates: [Date]) -> [Date: [String: HRVDailySamples]] {
        var found: [Date: [String: HRVDailySamples]] = [:]
        for date in dates { if let entry = entries[date] { found[date] = entry } }
        return found
    }

    func store(_ new: [Date: [String: HRVDailySamples]]) {
        entries.merge(new) { _, latest in latest }
    }

    func clear() { entries = [:] }
}

final class HealthStore {
    private let store = HKHealthStore()
    private let historyCache = HRVHistoryCache()
    private let heartType = HKQuantityType(.heartRate)
    private let hrvType = HKQuantityType(.heartRateVariabilitySDNN)
    private let restingType = HKQuantityType(.restingHeartRate)
    private let stepsType = HKQuantityType(.stepCount)
    private let sleepType = HKCategoryType(.sleepAnalysis)
    private let bpm = HKUnit.count().unitDivided(by: .minute())

    var isAvailable: Bool {
        #if DEBUG
        if DemoData.enabled { return true }
        #endif
        return HKHealthStore.isHealthDataAvailable()
    }

    func requestReadAccess() async throws {
        #if DEBUG
        if DemoData.enabled { return }
        #endif
        let types: Set<HKObjectType> = [
            heartType, hrvType, restingType, stepsType, sleepType, HKObjectType.workoutType(),
            HKQuantityType(.respiratoryRate), HKQuantityType(.oxygenSaturation),
            HKQuantityType(.appleSleepingWristTemperature), HKQuantityType(.heartRateRecoveryOneMinute),
            HKQuantityType(.activeEnergyBurned)
        ]
        try await store.requestAuthorization(toShare: [], read: types)
    }

    func readDay(_ day: DateInterval, calendar: Calendar) async -> DayReport {
        #if DEBUG
        if DemoData.enabled { return DemoData.day(day, calendar: calendar) }
        #endif
        async let heart = read {
            try await self.readQuantities(self.heartType, unit: self.bpm, day: day)
        }
        async let hrv = read {
            try await self.readQuantities(self.hrvType, unit: .secondUnit(with: .milli), day: day)
        }
        async let resting = read {
            try await self.readQuantities(self.restingType, unit: self.bpm, day: day)
        }
        async let sleep = read { try await self.readSleep(day) }
        async let workouts = read { try await self.readWorkouts(day) }
        async let steps = read { try await self.readSteps(day) }
        async let overnight = read { try await self.readOvernightHRV(for: day, calendar: calendar) }

        let (heartResult, hrvResult, restingResult, sleepResult, workoutResult, stepsResult) =
            await (heart, hrv, resting, sleep, workouts, steps)

        let hrvReadings = (try? hrvResult.get()) ?? []
        let sleepIntervals = (try? sleepResult.get()) ?? []
        let workoutIntervals = (try? workoutResult.get()) ?? []
        async let preferredZones = readPreferredWorkoutZones(
            needed: workoutIntervals.contains { $0.workoutZones == nil }
        )
        let assessment: (points: [HealthReading.ID: HRVAssessment], day: HRVDailyScore?, baseline: ClosedRange<Double>?)
        if (try? workoutResult.get()) != nil {
            let excluded = sleepIntervals.filter(\.isAsleep) + workoutIntervals
            assessment = await assessHRV(hrvReadings, day: day, calendar: calendar, excluding: excluded)
        } else {
            assessment = ([:], nil, nil)
        }
        let overnightScore = try? await overnight.get()

        return DayReport(
            day: day,
            heartRate: (try? heartResult.get()) ?? [],
            hrv: hrvReadings,
            hrvAssessments: assessment.points,
            dailyHRV: assessment.day,
            restingHeartRate: (try? restingResult.get()) ?? [],
            sleep: sleepIntervals,
            workouts: workoutIntervals,
            preferredWorkoutZones: await preferredZones,
            overnightHRV: overnightScore,
            hrvBaseline: assessment.baseline,
            steps: (try? stepsResult.get()) ?? [],
            unavailable: [
                failed(heartResult, "Heart Rate"),
                failed(hrvResult, "HRV"),
                failed(restingResult, "Resting Heart Rate"),
                failed(sleepResult, "Sleep"),
                failed(workoutResult, "Workout"),
                failed(stepsResult, "Steps")
            ].compactMap { $0 }
        )
    }

    private func assessHRV(
        _ readings: [HealthReading], day: DateInterval, calendar: Calendar, excluding intervals: [HealthInterval]
    ) async -> (points: [HealthReading.ID: HRVAssessment], day: HRVDailyScore?, baseline: ClosedRange<Double>?) {
        var assessments: [HealthReading.ID: HRVAssessment] = [:]
        let now = Date()
        let excluded = IntervalIndex(intervals)
        let candidates = readings.filter { reading in
            if excluded.overlaps(reading) {
                assessments[reading.id] = .duringSleepOrWorkout
                return false
            }
            if !HRVAssessment.canScore(reading, calendar: calendar) {
                assessments[reading.id] = .outsideDaytime
                return false
            }
            return reading.time <= now && reading.value.isFinite && reading.value > 0
        }
        guard !candidates.isEmpty,
              let start = calendar.date(byAdding: .day, value: -HRVHistory.referenceLength, to: day.start),
              let history = try? await readHRVHistory(DateInterval(start: start, end: day.start), calendar: calendar)
        else { return (assessments, nil, nil) }

        let grouped = Dictionary(grouping: candidates, by: \.sourceID)
        for (source, readings) in grouped {
            let reference = history.readingReference(for: source, on: day.start, calendar: calendar)
            for reading in readings {
                assessments[reading.id] = HRVAssessment.compare(
                    reading.value, toReadings: reference.values, days: reference.days
                )
            }
        }

        let current = grouped.compactMapValues { HRVDailySamples(readings: $0) }
        let daily = history.dailyScore(for: day, current: current, calendar: calendar)
        let primary = grouped.max { $0.value.count < $1.value.count }?.key
        let baseline = primary.flatMap { source in
            ReadingComparison(history.reference(for: source, on: day.start, calendar: calendar)).middleHalf
        }
        return (assessments, daily, baseline)
    }

    /// Scores the main sleep session on its wake date against the same source's prior 30 nights.
    private func readOvernightHRV(for day: DateInterval, calendar: Calendar) async throws -> HRVDailyScore? {
        guard let start = calendar.date(byAdding: .day, value: -HRVHistory.referenceLength - 2, to: day.start) else {
            return nil
        }
        let now = Date()
        guard start < min(day.end, now) else { return nil }
        let window = DateInterval(start: start, end: min(day.end, now))
        let sleep = try await readSleep(window)
        let nights = RecoveryNight.sessions(from: sleep, calendar: calendar, now: now)
        guard nights.contains(where: { $0.date == day.start }) else { return nil }
        let readings = try await readQuantities(hrvType, unit: .secondUnit(with: .milli), day: window)
        return Self.overnightScores(nights, readings: readings, calendar: calendar)[day.start]
    }

    /// Daily HRV medians for each day in `interval`. Finished days never change, so they're kept for the
    /// session and only days not seen yet are read from Health.
    private func readHRVHistory(_ interval: DateInterval, calendar: Calendar) async throws -> HRVHistory {
        let today = calendar.startOfDay(for: Date())
        var dates: [Date] = []
        var cursor = calendar.startOfDay(for: interval.start)
        while cursor < interval.end {
            dates.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        var byDay = await historyCache.days(dates)
        let missing = dates.filter { byDay[$0] == nil }
        if let first = missing.first, let last = missing.last,
           let lastEnd = calendar.date(byAdding: .day, value: 1, to: last) {
            let window = DateInterval(start: max(first, interval.start), end: max(first, min(lastEnd, interval.end)))
            let fetched = try await fetchHRVHistory(window, calendar: calendar)
            var fresh: [Date: [String: HRVDailySamples]] = [:]
            for date in missing { fresh[date] = [:] }
            for (source, days) in fetched {
                for (day, entry) in days where fresh[day] != nil { fresh[day]?[source] = entry }
            }
            await historyCache.store(fresh.filter { $0.key < today })
            byDay.merge(fresh) { _, new in new }
        }
        var samples: [String: [Date: HRVDailySamples]] = [:]
        for (day, sources) in byDay {
            for (source, entry) in sources { samples[source, default: [:]][day] = entry }
        }
        return HRVHistory(samples: samples)
    }

    private func fetchHRVHistory(
        _ interval: DateInterval, calendar: Calendar
    ) async throws -> [String: [Date: HRVDailySamples]] {
        async let hrv = readQuantities(hrvType, unit: .secondUnit(with: .milli), day: interval)
        async let sleep = read { try await self.readSleep(interval) }
        async let workouts = readWorkouts(interval)
        let (readings, sleepResult, workoutIntervals) = try await (hrv, sleep, workouts)
        let excluded = IntervalIndex(((try? sleepResult.get()) ?? []).filter(\.isAsleep) + workoutIntervals)
        let now = Date()

        var grouped: [String: [Date: [HealthReading]]] = [:]
        for reading in readings {
            try Task.checkCancellation()
            guard reading.time <= now, reading.value.isFinite, reading.value > 0,
                  HRVAssessment.canScore(reading, calendar: calendar),
                  !excluded.overlaps(reading) else { continue }
            let day = calendar.startOfDay(for: reading.time)
            grouped[reading.sourceID, default: [:]][day, default: []].append(reading)
        }
        return grouped.mapValues { days in
            days.compactMapValues { HRVDailySamples(readings: $0) }
        }
    }

    /// Forgets cached history, for pull-to-refresh.
    func clearCache() async {
        await historyCache.clear()
    }

    private func readDailyScores(
        _ interval: DateInterval, by bucketSize: DateComponents, calendar: Calendar
    ) async throws -> [Date: HRVDailyScore] {
        guard bucketSize.day == 1,
              let start = calendar.date(byAdding: .day, value: -HRVHistory.referenceLength, to: interval.start)
        else { return [:] }

        let history = try await readHRVHistory(DateInterval(start: start, end: interval.end), calendar: calendar)
        var days: [Date: [String: HRVDailySamples]] = [:]
        for (source, entries) in history.samples {
            for (day, entry) in entries where day >= interval.start && day < interval.end {
                days[day, default: [:]][source] = entry
            }
        }

        var results: [Date: HRVDailyScore] = [:]
        for (date, entries) in days {
            try Task.checkCancellation()
            if let day = calendar.dateInterval(of: .day, for: date) {
                results[date] = history.dailyScore(for: day, current: entries, calendar: calendar)
            }
        }
        return results
    }

    private func read<T>(_ operation: () async throws -> T) async -> Result<T, Error> {
        do {
            return .success(try await operation())
        } catch {
            return .failure(error)
        }
    }

    private func failed<T>(_ result: Result<T, Error>, _ name: LocalizedStringResource) -> LocalizedStringResource? {
        if case .failure = result { return name }
        return nil
    }

    private func readQuantities(
        _ type: HKQuantityType, unit: HKUnit, day: DateInterval
    ) async throws -> [HealthReading] {
        let query = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type, predicate: overlap(day))],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let samples = try await query.result(for: store)
        var readings: [HealthReading] = []
        var seriesIDs: Set<UUID> = []

        for sample in samples {
            if sample.count > 1 {
                seriesIDs.insert(sample.uuid)
            } else if sample.startDate >= day.start && sample.startDate < day.end {
                readings.append(makeReading(sample, quantity: sample.quantity, start: sample.startDate,
                                            end: sample.endDate, unit: unit))
            }
        }

        if !seriesIDs.isEmpty {
            let series = HKQuantitySeriesSampleQueryDescriptor(
                predicate: .quantitySample(type: type, predicate: HKQuery.predicateForObjects(with: seriesIDs)),
                options: .includeSample
            )
            // A quantity series can include distinct entries with identical timestamps and values.
            var occurrences: [HealthReading.ID: Int] = [:]
            for try await entry in series.results(for: store) {
                try Task.checkCancellation()
                let interval = entry.dateInterval
                guard let sample = entry.sample,
                      interval.start >= day.start, interval.start < day.end else { continue }
                let base = makeReading(sample, quantity: entry.quantity, start: interval.start,
                                       end: interval.end, unit: unit)
                let occurrence = occurrences[base.id, default: 0]
                occurrences[base.id] = occurrence + 1
                readings.append(makeReading(sample, quantity: entry.quantity, start: interval.start,
                                            end: interval.end, unit: unit, occurrence: occurrence))
            }
        }

        return readings.sorted { $0.time < $1.time }
    }

    private func makeReading(
        _ sample: HKQuantitySample, quantity: HKQuantity, start: Date, end: Date, unit: HKUnit,
        occurrence: Int = 0
    ) -> HealthReading {
        HealthReading(
            id: .init(sample: sample.uuid, start: start, end: end,
                      value: quantity.doubleValue(for: unit), occurrence: occurrence),
            source: sourceName(sample),
            sourceID: sample.sourceRevision.source.bundleIdentifier
        )
    }

    private func readSleep(_ day: DateInterval) async throws -> [HealthInterval] {
        let query = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: sleepType, predicate: overlap(day))],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        return try await query.result(for: store).compactMap { sample in
            guard sample.startDate < day.end, sample.endDate > day.start else { return nil }
            let stage: SleepStage
            switch HKCategoryValueSleepAnalysis(rawValue: sample.value) {
            case .inBed: stage = .inBed
            case .awake: stage = .awake
            case .asleepCore: stage = .core
            case .asleepDeep: stage = .deep
            case .asleepREM: stage = .rem
            case .asleepUnspecified: stage = .asleep
            default: stage = .other
            }
            return HealthInterval(id: sample.uuid, start: sample.startDate, end: sample.endDate,
                                  title: stage.title, source: sourceName(sample), sleepStage: stage)
        }
    }

    private func readWorkouts(_ day: DateInterval) async throws -> [HealthInterval] {
        let query = HKSampleQueryDescriptor(
            predicates: [.workout(overlap(day))],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        return try await query.result(for: store).compactMap { workout in
            guard workout.startDate < day.end, workout.endDate > day.start else { return nil }
            return makeWorkoutInterval(workout)
        }
    }

    private func makeWorkoutInterval(_ workout: HKWorkout) -> HealthInterval {
        HealthInterval(
            id: workout.uuid, start: workout.startDate, end: workout.endDate,
            title: workoutName(workout.workoutActivityType), source: sourceName(workout),
            workoutDuration: workout.duration, workoutZones: recordedWorkoutZones(for: workout),
            workoutActivity: workout.workoutActivityType.rawValue,
            activeEnergy: workout.statistics(for: HKQuantityType(.activeEnergyBurned))?
                .sumQuantity()?.doubleValue(for: .kilocalorie())
        )
    }

    private func recordedWorkoutZones(for workout: HKWorkout) -> WorkoutHeartRateZones? {
        guard #available(iOS 27.0, *), let group = workout.zoneGroup(for: heartType) else { return nil }
        return workoutZones(from: group.configuration, durations: group.zoneDurations, source: .recorded)
    }

    private func readPreferredWorkoutZones(needed: Bool) async -> WorkoutHeartRateZones? {
        guard needed, #available(iOS 27.0, *),
              let configuration = try? await store.preferredWorkoutZoneConfiguration(for: heartType)
        else { return nil }
        return workoutZones(from: configuration, durations: [], source: .preferred)
    }

    @available(iOS 27.0, *)
    private func workoutZones(
        from configuration: HKWorkoutZoneConfiguration, durations: [HKWorkoutZoneDuration],
        source: WorkoutHeartRateZones.Source
    ) -> WorkoutHeartRateZones? {
        let ordered = configuration.zones
        let boundaries = ordered.dropFirst().compactMap { $0.minimum?.doubleValue(for: bpm) }
        guard boundaries.count == ordered.count - 1 else { return nil }
        let seconds = Dictionary(durations.map { ($0.zone.index, $0.duration) }, uniquingKeysWith: { first, _ in first })
        return WorkoutHeartRateZones(boundaries: boundaries, durations: ordered.map { seconds[$0.index] }, source: source)
    }

    func readTrends(_ interval: DateInterval, by bucketSize: DateComponents, calendar: Calendar) async -> TrendReport {
        #if DEBUG
        if DemoData.enabled { return DemoData.trends(interval, by: bucketSize, calendar: calendar) }
        #endif
        async let heart = read {
            try await self.readBuckets(self.heartType, unit: self.bpm, in: interval, by: bucketSize, options: .discreteAverage)
        }
        async let hrv = read { () -> [MetricBucket] in
            guard bucketSize.day != 1 else { return [] }
            return try await self.readBuckets(self.hrvType, unit: .secondUnit(with: .milli), in: interval,
                                              by: bucketSize, options: .discreteAverage)
        }
        async let resting = read {
            try await self.readBuckets(self.restingType, unit: self.bpm, in: interval, by: bucketSize, options: .discreteAverage)
        }
        async let scores = read { try await self.readDailyScores(interval, by: bucketSize, calendar: calendar) }
        let (heartResult, hrvResult, restingResult, scoreResult) = await (heart, hrv, resting, scores)
        let daily = (try? scoreResult.get()) ?? [:]
        return TrendReport(
            interval: interval,
            heartRate: (try? heartResult.get()) ?? [],
            hrv: bucketSize.day == 1 ? HRVDailyScore.daytimeMedians(daily) : (try? hrvResult.get()) ?? [],
            restingHeartRate: (try? restingResult.get()) ?? [],
            dailyHRV: daily,
            unavailable: [
                failed(heartResult, "Heart Rate"),
                failed(hrvResult, "HRV"),
                failed(restingResult, "Resting Heart Rate"),
                failed(scoreResult, "Daily HRV Score")
            ].compactMap { $0 }
        )
    }

    func readHistory(
        _ metric: HeartHistoryMetric, in interval: DateInterval, calendar: Calendar
    ) async throws -> (buckets: [MetricBucket], dailyHRV: [Date: HRVDailyScore]) {
        let day = DateComponents(day: 1)
        #if DEBUG
        if DemoData.enabled {
            let report = DemoData.trends(interval, by: day, calendar: calendar)
            return (metric == .hrv ? report.hrv : report.restingHeartRate, metric == .hrv ? report.dailyHRV : [:])
        }
        #endif
        switch metric {
        case .hrv:
            let daily = try await readDailyScores(interval, by: day, calendar: calendar)
            return (HRVDailyScore.daytimeMedians(daily), daily)
        case .restingHeartRate:
            let buckets = try await readBuckets(restingType, unit: bpm, in: interval,
                                               by: day, options: .discreteAverage)
            return (buckets, [:])
        }
    }

    private func readSteps(_ day: DateInterval) async throws -> [MetricBucket] {
        try await readBuckets(stepsType, unit: .count(), in: day, by: DateComponents(hour: 1), options: .cumulativeSum)
    }

    private func readBuckets(
        _ type: HKQuantityType, unit: HKUnit, in interval: DateInterval, by bucketSize: DateComponents,
        options: HKStatisticsOptions
    ) async throws -> [MetricBucket] {
        let query = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: overlap(interval)),
            options: options,
            anchorDate: interval.start,
            intervalComponents: bucketSize
        )
        let collection = try await query.result(for: store)
        var buckets: [MetricBucket] = []
        collection.enumerateStatistics(from: interval.start, to: interval.end) { statistics, _ in
            guard statistics.startDate < interval.end else { return }
            let quantity = options == .cumulativeSum ? statistics.sumQuantity() : statistics.averageQuantity()
            guard let quantity else { return }
            buckets.append(MetricBucket(
                interval: DateInterval(start: statistics.startDate, end: min(statistics.endDate, interval.end)),
                value: quantity.doubleValue(for: unit)
            ))
        }
        return buckets
    }

    private func overlap(_ day: DateInterval) -> NSPredicate {
        HKQuery.predicateForSamples(withStart: day.start, end: day.end, options: [])
    }

    private func sourceName(_ sample: HKSample) -> String {
        sample.device?.name ?? sample.sourceRevision.source.name
    }

    private func workoutName(_ type: HKWorkoutActivityType) -> LocalizedStringResource {
        switch type {
        case .walking: return "Walking"
        case .running: return "Running"
        case .cycling: return "Cycling"
        case .hiking: return "Hiking"
        case .swimming: return "Swimming"
        case .yoga: return "Yoga"
        case .pilates: return "Pilates"
        case .traditionalStrengthTraining: return "Traditional Strength Training"
        case .functionalStrengthTraining: return "Functional Strength Training"
        case .highIntensityIntervalTraining: return "High-Intensity Interval Training"
        case .elliptical: return "Elliptical"
        case .rowing: return "Rowing"
        case .stairClimbing, .stairs: return "Stair Climbing"
        case .dance, .cardioDance, .socialDance: return "Dance"
        case .coreTraining: return "Core Training"
        case .cooldown: return "Cooldown"
        default: return "Workout"
        }
    }
}

#if DEBUG
/// Sample data for simulator screenshots. Enabled with the `-rhythmDemo` launch argument; never used in release builds.
enum DemoData {
    static let withoutSleep = ProcessInfo.processInfo.arguments.contains("-rhythmDemoNoSleep")
    static let enabled = withoutSleep || ProcessInfo.processInfo.arguments.contains("-rhythmDemo")
    private static let source = "Apple Watch"
    private static let sourceID = "com.apple.health.demo"

    private struct Generator {
        var state: UInt64
        /// A value in 0..<1.
        mutating func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 33) / Double(UInt64(1) << 31)
        }
        mutating func around(_ center: Double, _ spread: Double) -> Double {
            center + (next() - 0.5) * 2 * spread
        }
    }

    private static func seed(_ date: Date) -> UInt64 {
        UInt64(abs(date.timeIntervalSinceReferenceDate / 86400)) &+ 17
    }

    private static func reading(_ time: Date, _ value: Double) -> HealthReading {
        HealthReading(id: .init(sample: UUID(), start: time, end: time, value: value, occurrence: 0),
                      source: source, sourceID: sourceID)
    }

    static func day(_ day: DateInterval, calendar: Calendar) -> DayReport {
        var random = Generator(state: seed(day.start))
        let end = min(day.end, Date())
        func at(_ hours: Double) -> Date { day.start.addingTimeInterval(hours * 3600) }

        let stages: [(Double, Double, SleepStage)] = [
            (0, 0.6, .core), (0.6, 1.5, .deep), (1.5, 2.4, .core), (2.4, 3.1, .rem), (3.1, 3.2, .awake),
            (3.2, 4.4, .core), (4.4, 5.0, .deep), (5.0, 6.0, .rem), (6.0, 6.9, .core)
        ]
        let sleep = stages.filter { !withoutSleep && at($0.0) < end }.map {
            HealthInterval(id: UUID(), start: at($0.0), end: at($0.1), title: $0.2.title, source: source, sleepStage: $0.2)
        }
        let workouts = training(day, calendar: calendar).map(\.interval).filter { $0.end <= end }

        var heart: [HealthReading] = []
        for step in 0..<240 {
            let hours = Double(step) / 10
            guard at(hours) < end else { break }
            if withoutSleep && hours < 6.9 { continue }
            let value: Double
            if hours < 6.9 {
                value = random.around(53, 5)
            } else if workouts.contains(where: { $0.start <= at(hours) && at(hours) < $0.end }) {
                value = random.around(146, 18)
            } else {
                value = random.around(72 + 8 * sin(hours / 3), 12)
            }
            heart.append(reading(at(hours), value.rounded()))
        }

        let pool = (0..<240).map { _ in random.around(44, 14) }
        let medians = (0..<30).map { _ in random.around(44, 14) }
        let nightMedians = (0..<30).map { _ in random.around(60, 7) }
        var hrv: [HealthReading] = []
        var assessments: [HealthReading.ID: HRVAssessment] = [:]
        for hours in [1.0, 2.5, 4, 5.5] + Array(stride(from: 6.5, through: 21.5, by: 0.17)) + [23] where at(hours) < end {
            let night = !withoutSleep && hours < 6.9
            let item = reading(at(hours), night ? random.around(62, 9) : random.around(43, 13))
            hrv.append(item)
            if night || workouts.contains(where: { $0.start <= at(hours) && at(hours) < $0.end }) {
                assessments[item.id] = .duringSleepOrWorkout
            } else if hours < 6 || hours >= 22 {
                assessments[item.id] = .outsideDaytime
            } else {
                assessments[item.id] = HRVAssessment.compare(item.value, toReadings: pool, days: 30)
            }
        }
        let daytime = hrv.filter { if case .score = assessments[$0.id] { true } else { false } }
        let nighttime = hrv.filter { HRVAssessment.overlaps($0, intervals: sleep.filter(\.isAsleep)) }
        let daily = HRVDailySamples(readings: daytime).map {
            HRVDailyScore(day: day, samples: $0, assessment: HRVAssessment.compare($0.median, to: medians))
        }
        let overnight = HRVDailySamples(readings: nighttime).map {
            HRVDailyScore(day: day, samples: $0, assessment: HRVAssessment.compare($0.median, to: nightMedians))
        }

        var steps: [MetricBucket] = []
        for hour in 7..<22 where at(Double(hour)) < end {
            let busy = hour == 8 || hour == 12 || hour == 18
            steps.append(MetricBucket(interval: DateInterval(start: at(Double(hour)), duration: 3600),
                                      value: (random.around(busy ? 1900 : 420, busy ? 600 : 300)).rounded()))
        }

        return DayReport(
            day: day, heartRate: heart, hrv: hrv, hrvAssessments: assessments, dailyHRV: daily,
            restingHeartRate: at(7) < end ? [reading(at(7), random.around(55, 3).rounded())] : [],
            sleep: sleep, workouts: workouts, overnightHRV: overnight, hrvBaseline: 38...50,
            steps: steps, unavailable: []
        )
    }

    static func recovery(
        _ interval: DateInterval, previous: DateInterval, from start: Date, calendar: Calendar, now: Date
    ) -> RecoveryReport {
        var nights: [RecoveryNight] = []
        var daytime: [Date: Double] = [:]
        var resting: [Date: Double] = [:]
        var steps: [Date: Double] = [:]
        var workoutMinutes: [Date: Double] = [:]
        var date = start
        while date < min(interval.end, now),
              let day = calendar.dateInterval(of: .day, for: date) {
            var random = Generator(state: seed(date))
            let sequence = Int(date.timeIntervalSinceReferenceDate / 86400)
            let sample = Self.day(day, calendar: calendar)
            resting[date] = sample.restingHeartRate.first?.value
            if !sample.workouts.isEmpty {
                workoutMinutes[date] = sample.workouts.compactMap(\.workoutDuration).reduce(0, +) / 60
            }
            if !sample.steps.isEmpty { steps[date] = sample.steps.reduce(0) { $0 + $1.value } }
            daytime[date] = sequence.isMultiple(of: 13) ? nil : sample.dailyHRV?.samples.median
            let bedtime = calendar.date(byAdding: .minute, value: Int(random.around(-40, 52)), to: date) ?? date
            let wake = calendar.date(byAdding: .minute, value: Int(random.around(414, 28)), to: date) ?? date
            if !withoutSleep, bedtime < wake, wake < now, !sequence.isMultiple(of: 17) {
                var night = RecoveryNight(date: date, sleep: [DateInterval(start: bedtime, end: wake)])
                if !sequence.isMultiple(of: 11) {
                    night.hrv = sample.overnightHRV?.samples.median
                    night.hrvPressure = sample.overnightHRV?.score
                }
                night.resting = sample.restingHeartRate.first?.value
                let unusual = sequence.isMultiple(of: 11)
                night.vitals[.heart] = random.around(unusual ? 61 : 53, 2)
                night.vitals[.respiration] = random.around(14.4, 0.9)
                night.vitals[.oxygen] = sequence.isMultiple(of: 5) ? nil : random.around(97, 1.5)
                night.vitals[.temperature] = random.around(unusual ? 36.6 : 35.9, 0.22)
                nights.append(night)
            }
            date = day.end
        }
        return RecoveryReport(interval: interval, previous: previous, nights: nights, daytime: daytime,
                              resting: resting, steps: steps, workoutMinutes: workoutMinutes)
    }

    static func trends(_ interval: DateInterval, by bucketSize: DateComponents, calendar: Calendar) -> TrendReport {
        var random = Generator(state: seed(interval.start))
        let end = min(interval.end, Date())
        var heart: [MetricBucket] = [], hrv: [MetricBucket] = [], resting: [MetricBucket] = []
        var scores: [Date: HRVDailyScore] = [:]
        var start = interval.start
        while start < end, let next = calendar.date(byAdding: bucketSize, to: start), next > start {
            let bucket = DateInterval(start: start, end: next)
            let value = random.around(44, 9)
            heart.append(MetricBucket(interval: bucket, value: random.around(72, 5)))
            if bucketSize.day == 1 {
                let sample = Self.day(bucket, calendar: calendar)
                if let score = sample.dailyHRV { scores[start] = score }
                if let value = sample.restingHeartRate.first?.value {
                    resting.append(MetricBucket(interval: bucket, value: value))
                }
            } else {
                hrv.append(MetricBucket(interval: bucket, value: value))
                resting.append(MetricBucket(interval: bucket, value: random.around(55, 3)))
            }
            start = next
        }
        return TrendReport(interval: interval, heartRate: heart,
                           hrv: bucketSize.day == 1 ? HRVDailyScore.daytimeMedians(scores) : hrv,
                           restingHeartRate: resting, dailyHRV: scores, unavailable: [])
    }
}
#endif

extension HealthStore {
    private func overnightQuantity(_ metric: OvernightMetric) -> (HKQuantityType, HKUnit) {
        switch metric {
        case .heart: (heartType, bpm)
        case .respiration: (HKQuantityType(.respiratoryRate), bpm)
        case .oxygen: (HKQuantityType(.oxygenSaturation), .percent())
        case .temperature: (HKQuantityType(.appleSleepingWristTemperature), .degreeCelsius())
        }
    }

    func readRecovery(_ interval: DateInterval, calendar: Calendar) async -> RecoveryReport {
        let numberOfDays = calendar.dateComponents([.day], from: interval.start, to: interval.end).day ?? 7
        let previousStart = calendar.date(byAdding: .day, value: -numberOfDays, to: interval.start) ?? interval.start
        let previous = DateInterval(start: previousStart, end: interval.start)
        let now = Date()
        let historyStart = calendar.date(byAdding: .day, value: -30, to: min(previousStart, interval.start)) ?? previousStart
        let queryStart = calendar.date(byAdding: .day, value: -2, to: historyStart) ?? historyStart
        let window = DateInterval(start: queryStart, end: max(queryStart, min(interval.end, now)))

        #if DEBUG
        if DemoData.enabled {
            return DemoData.recovery(interval, previous: previous, from: historyStart, calendar: calendar, now: now)
        }
        #endif

        async let sleep = read { try await self.readSleep(window) }
        async let hrv = read { try await self.readQuantities(self.hrvType, unit: .secondUnit(with: .milli), day: window) }
        async let resting = read { try await self.readBuckets(self.restingType, unit: self.bpm, in: window,
                                                             by: DateComponents(day: 1), options: .discreteAverage) }
        async let workouts = read { try await self.readWorkouts(window) }
        async let steps = read {
            try await self.readBuckets(self.stepsType, unit: .count(), in: window,
                                       by: DateComponents(day: 1), options: .cumulativeSum)
        }
        let sleepResult = await sleep
        let sleepIntervals = (try? sleepResult.get()) ?? []
        let nights = RecoveryNight.sessions(from: sleepIntervals, calendar: calendar, now: now)
            .filter { $0.date >= historyStart && $0.date < interval.end }
        let (hrvResult, restingResult, workoutResult, stepResult) = await (hrv, resting, workouts, steps)
        let hrvReadings = ((try? hrvResult.get()) ?? []).filter { $0.value.isFinite && $0.value > 0 && $0.time <= now }
        let restingByDate = Dictionary(((try? restingResult.get()) ?? []).map { ($0.id, $0.value) },
                                       uniquingKeysWith: { first, _ in first })
        let stepsByDate = Dictionary(((try? stepResult.get()) ?? []).map { ($0.id, $0.value) },
                                     uniquingKeysWith: { first, _ in first })
        let scores = Self.overnightScores(nights, readings: hrvReadings, calendar: calendar)
        let recovery = nights.map { night in
            var entry = night
            entry.hrv = scores[night.date]?.samples.median
            entry.hrvPressure = scores[night.date]?.score
            entry.resting = restingByDate[night.date]
            return entry
        }

        var daytime: [Date: Double] = [:]
        var workoutMinutes: [Date: Double] = [:]
        if let workouts = try? workoutResult.get() {
            for workout in workouts where workout.end <= now {
                guard let duration = workout.workoutDuration, duration.isFinite, duration > 0 else { continue }
                let date = calendar.startOfDay(for: workout.start)
                workoutMinutes[date, default: 0] += duration / 60
            }
            let excluded = IntervalIndex(sleepIntervals.filter(\.isAsleep) + workouts)
            let eligible = hrvReadings.filter {
                HRVAssessment.canScore($0, calendar: calendar) && !excluded.overlaps($0)
            }
            daytime = Dictionary(grouping: eligible) { calendar.startOfDay(for: $0.time) }
                .compactMapValues { Self.recoveryMedian($0) }
        }
        let unavailable = [
            failed(sleepResult, "Sleep"), failed(hrvResult, "HRV"),
            failed(restingResult, "Resting Heart Rate"), failed(workoutResult, "Workout"), failed(stepResult, "Steps")
        ].compactMap { $0 }
        return RecoveryReport(interval: interval, previous: previous, nights: recovery, daytime: daytime,
                              resting: restingByDate, steps: stepsByDate, workoutMinutes: workoutMinutes,
                              unavailable: unavailable)
    }

    /// Overnight vitals, read after the rest of Recovery is on screen (they sit in a collapsed section).
    func readRecoveryVitals(_ report: RecoveryReport, calendar: Calendar) async -> RecoveryReport {
        #if DEBUG
        if DemoData.enabled { return report }
        #endif
        guard report.nights.contains(where: { $0.date >= report.interval.start }),
              let first = report.nights.first, let last = report.nights.last else { return report }
        let window = DateInterval(start: first.start.addingTimeInterval(-12 * 3600), end: max(first.start, last.end))
        let results = await withTaskGroup(of: (OvernightMetric, Result<[HealthReading], Error>).self) { group in
            for metric in OvernightMetric.allCases {
                group.addTask {
                    let (type, unit) = self.overnightQuantity(metric)
                    return (metric, await self.read { try await self.readQuantities(type, unit: unit, day: window) })
                }
            }
            var collected: [OvernightMetric: Result<[HealthReading], Error>] = [:]
            for await (metric, readings) in group { collected[metric] = readings }
            return collected
        }
        let readings = results.compactMapValues { try? $0.get() }
        let nights = report.nights.map { night in
            var entry = night
            for (metric, values) in readings {
                let matching = Self.readings(values, duringSleep: night).filter { $0.value.isFinite && $0.value > 0 }
                if let value = Self.recoveryMedian(matching, minimum: 1) {
                    entry.vitals[metric] = metric == .oxygen ? value * 100 : value
                }
            }
            return entry
        }
        let failures = OvernightMetric.allCases.compactMap { metric in
            results[metric].flatMap { failed($0, metric.title) }
        }
        return RecoveryReport(interval: report.interval, previous: report.previous, nights: nights,
                              daytime: report.daytime, resting: report.resting, steps: report.steps,
                              workoutMinutes: report.workoutMinutes, unavailable: report.unavailable + failures)
    }

    /// Readings (sorted by time) inside a night's sleep segments; only the hours around the night are checked.
    private static func readings(_ sorted: [HealthReading], duringSleep night: RecoveryNight) -> [HealthReading] {
        sorted.sortedSlice(from: night.start.addingTimeInterval(-12 * 3600), to: night.end)
            .filter { isDuringSleep($0, night: night) }
    }

    private static func overnightScores(
        _ nights: [RecoveryNight], readings: [HealthReading], calendar: Calendar
    ) -> [Date: HRVDailyScore] {
        let valid = readings.filter { $0.value.isFinite && $0.value > 0 }
        var bySource: [String: [Date: HRVDailySamples]] = [:]
        var byDate: [Date: [String: HRVDailySamples]] = [:]
        for night in nights {
            let matching = Self.readings(valid, duringSleep: night)
            let samples = Dictionary(grouping: matching, by: \.sourceID).compactMapValues {
                $0.count >= 2 ? HRVDailySamples(readings: $0) : nil
            }
            byDate[night.date] = samples
            for (source, daily) in samples {
                bySource[source, default: [:]][night.date] = daily
            }
        }
        let history = HRVHistory(samples: bySource)
        return Dictionary(uniqueKeysWithValues: nights.compactMap { night in
            guard let day = calendar.dateInterval(of: .day, for: night.date),
                  let score = history.dailyScore(for: day, current: byDate[night.date, default: [:]], calendar: calendar)
            else { return nil }
            return (night.date, score)
        })
    }

    private static func isDuringSleep(_ reading: HealthReading, night: RecoveryNight) -> Bool {
        night.sleep.contains { segment in
            reading.time < segment.end && (reading.time >= segment.start || reading.id.end > segment.start)
        }
    }

    private static func recoveryMedian(_ readings: [HealthReading], minimum: Int = 2) -> Double? {
        let groups = Dictionary(grouping: readings, by: \.sourceID)
        let primary = groups.keys.sorted().max { groups[$0, default: []].count < groups[$1, default: []].count }
        guard let primary, let selected = groups[primary], selected.count >= minimum else { return nil }
        return RecoveryReport.median(selected.map(\.value))
    }
}

extension HealthStore {
    func readTraining(_ interval: DateInterval, calendar: Calendar) async -> TrainingReport {
        let end = min(interval.end, calendar.startOfDay(for: Date()))
        let start = calendar.date(byAdding: .day, value: -56, to: end) ?? end
        let window = DateInterval(start: start, end: end)
        #if DEBUG
        if DemoData.enabled {
            return TrainingReport(interval: interval, end: end, workouts: DemoData.training(window, calendar: calendar), calendar: calendar)
        }
        #endif
        async let workoutQuery = HKSampleQueryDescriptor(predicates: [.workout(overlap(window))],
                                                         sortDescriptors: [SortDescriptor(\.startDate)]).result(for: store)
        async let recoveryQuery = readWorkoutRecovery(window)
        let (samples, recovery) = await ((try? workoutQuery), (try? recoveryQuery) ?? [])
        let workouts = samples?.filter {
            $0.startDate >= start && $0.endDate <= end && $0.duration.isFinite && $0.duration > 0
        }
        let recoveryMatches = workouts.map { Self.matchRecovery(recovery, to: $0) } ?? [:]
        let entries = workouts?.map { workout in
            let interval = makeWorkoutInterval(workout)
            let activity = workout.workoutActivityType
            let distanceType: HKQuantityTypeIdentifier
            switch activity {
            case .cycling: distanceType = .distanceCycling
            case .swimming: distanceType = .distanceSwimming
            case .wheelchairWalkPace, .wheelchairRunPace: distanceType = .distanceWheelchair
            default: distanceType = .distanceWalkingRunning
            }
            let distance = workout.statistics(for: HKQuantityType(distanceType))?.sumQuantity() ?? workout.totalDistance
            let heartRate = workout.statistics(for: heartType)?.averageQuantity()?.doubleValue(for: bpm)
            return TrainingWorkout(
                interval: interval,
                activity: activity,
                indoor: (workout.metadata?[HKMetadataKeyIndoorWorkout] as? NSNumber)?.boolValue,
                distance: distance?.doubleValue(for: .meterUnit(with: .kilo)),
                averageHeartRate: heartRate.flatMap { $0.isFinite && $0 > 0 ? $0 : nil },
                recovery: recoveryMatches[workout.uuid]
            )
        }
        return TrainingReport(interval: interval, end: end, workouts: entries, calendar: calendar)
    }

    private func readWorkoutRecovery(_ window: DateInterval) async throws -> [HKQuantitySample] {
        let type = HKQuantityType(.heartRateRecoveryOneMinute)
        let query = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type, predicate: overlap(window))],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        return try await query.result(for: store)
    }

    private static func matchRecovery(_ samples: [HKQuantitySample], to workouts: [HKWorkout]) -> [UUID: Double] {
        var matched: [UUID: [Double]] = [:]
        for sample in samples {
            guard let activity = (sample.metadata?[HKMetadataKeyHeartRateRecoveryActivityType] as? NSNumber)?.uintValue else { continue }
            let value = sample.quantity.doubleValue(for: .count())
            guard value.isFinite, value > 0 else { continue }
            let duration = (sample.metadata?[HKMetadataKeyHeartRateRecoveryActivityDuration] as? HKQuantity)?
                .doubleValue(for: .second())
            let candidates = workouts.filter { workout in
                workout.workoutActivityType.rawValue == activity &&
                workout.sourceRevision.source.bundleIdentifier == sample.sourceRevision.source.bundleIdentifier &&
                abs(sample.startDate.timeIntervalSince(workout.endDate)) <= 120 &&
                (duration.map { abs($0 - workout.duration) <= 30 } ?? true)
            }
            guard candidates.count == 1, let workout = candidates.first else { continue }
            matched[workout.uuid, default: []].append(value)
        }
        return matched.compactMapValues { $0.count == 1 ? $0.first : nil }
    }

    func readWorkoutHeart(_ workout: HealthInterval) async -> ([HealthReading], WorkoutHeartRateZones?) {
        let window = DateInterval(start: workout.start, end: workout.end)
        #if DEBUG
        if DemoData.enabled { return (DemoData.trainingHeart(workout), nil) }
        #endif
        async let readings = read { try await self.readQuantities(self.heartType, unit: self.bpm, day: window) }
        async let preferred = readPreferredWorkoutZones(needed: workout.workoutZones == nil)
        return ((try? await readings.get()) ?? [], await preferred)
    }

    /// Start time and activity type of every workout that starts inside `interval`; nil if Health can't be read.
    func readWorkoutLog(_ interval: DateInterval, calendar: Calendar) async -> [WorkoutLogEntry]? {
        #if DEBUG
        if DemoData.enabled {
            return DemoData.training(interval, calendar: calendar).filter { $0.interval.end <= Date() }.map {
                WorkoutLogEntry(id: $0.id, start: $0.interval.start, activity: $0.activity.rawValue)
            }
        }
        #endif
        let query = HKSampleQueryDescriptor(predicates: [.workout(overlap(interval))],
                                            sortDescriptors: [SortDescriptor(\.startDate)])
        guard let workouts = try? await query.result(for: store) else { return nil }
        return workouts.filter { $0.startDate >= interval.start && $0.startDate < interval.end }.map {
            WorkoutLogEntry(id: $0.uuid, start: $0.startDate, activity: $0.workoutActivityType.rawValue)
        }
    }
}

#if DEBUG
extension DemoData {
    static func training(_ window: DateInterval, calendar: Calendar) -> [TrainingWorkout] {
        var workouts: [TrainingWorkout] = []
        var day = window.start
        while day < window.end, let next = calendar.date(byAdding: .day, value: 1, to: day) {
            let ordinal = Int(day.timeIntervalSinceReferenceDate / 86400)
            let weekday = calendar.component(.weekday, from: day)
            if weekday != 2, weekday != 6, !ordinal.isMultiple(of: 13),
               let start = calendar.date(byAdding: .hour, value: 17, to: day) {
                var random = Generator(state: seed(day))
                let running = [1, 3, 5].contains(weekday)
                let duration = random.around(running ? 45 : 36, 13) * 60
                let pace = random.around(345, 32)
                let heart = 151 + (345 - pace) * 0.22 + random.around(0, 4)
                let end = start.addingTimeInterval(duration)
                let zones = WorkoutHeartRateZones(boundaries: [115, 132, 147, 164],
                    durations: [duration * 0.08, duration * 0.15, duration * 0.35, duration * 0.36, duration * 0.06],
                    source: .recorded)
                let interval = HealthInterval(id: UUID(), start: start, end: end,
                                              title: running ? "Running" : "Traditional Strength Training", source: source,
                                              workoutDuration: duration, workoutZones: zones,
                                              workoutActivity: (running ? HKWorkoutActivityType.running
                                                                : .traditionalStrengthTraining).rawValue,
                                              activeEnergy: (duration / 60 * (running ? 10.5 : 4.6)).rounded())
                workouts.append(TrainingWorkout(
                    interval: interval, activity: running ? .running : .traditionalStrengthTraining,
                    indoor: !running, distance: running ? duration / pace : nil,
                    averageHeartRate: running ? heart : random.around(126, 10),
                    recovery: ordinal.isMultiple(of: 4) ? nil : random.around(running ? 34 : 27, 8)
                ))
            }
            day = next
        }
        return workouts
    }

    static func trainingHeart(_ workout: HealthInterval) -> [HealthReading] {
        var random = Generator(state: seed(workout.start))
        let interval = workout.end.timeIntervalSince(workout.start)
        return stride(from: 0.0, to: interval, by: 15).map { time in
            reading(workout.start.addingTimeInterval(time), 110 + min(38, time / 7) + random.around(0, 12))
        }
    }
}
#endif

struct WorkoutLogEntry: Identifiable {
    let id: UUID
    let start: Date
    let activity: UInt

    var symbol: String { WorkoutSymbol.name(for: activity) }
}

enum WorkoutSymbol {
    /// SF Symbol for an `HKWorkoutActivityType` raw value.
    static func name(for raw: UInt?) -> String {
        guard let raw, let type = HKWorkoutActivityType(rawValue: raw) else { return "figure.mixed.cardio" }
        switch type {
        case .walking: return "figure.walk"
        case .running: return "figure.run"
        case .cycling: return "figure.outdoor.cycle"
        case .hiking: return "figure.hiking"
        case .swimming: return "figure.pool.swim"
        case .yoga: return "figure.yoga"
        case .pilates: return "figure.pilates"
        case .traditionalStrengthTraining: return "figure.strengthtraining.traditional"
        case .functionalStrengthTraining: return "figure.strengthtraining.functional"
        case .highIntensityIntervalTraining: return "figure.highintensity.intervaltraining"
        case .elliptical: return "figure.elliptical"
        case .rowing: return "figure.rower"
        case .stairClimbing, .stairs: return "figure.stair.stepper"
        case .dance, .cardioDance, .socialDance: return "figure.dance"
        case .coreTraining: return "figure.core.training"
        case .cooldown: return "figure.cooldown"
        default: return "figure.mixed.cardio"
        }
    }
}

extension HealthInterval {
    var workoutSymbol: String { WorkoutSymbol.name(for: workoutActivity) }
}
