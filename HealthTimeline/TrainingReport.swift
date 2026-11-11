import Foundation
import HealthKit

struct TrainingWorkout: Identifiable {
    let interval: HealthInterval
    let activity: HKWorkoutActivityType
    var indoor: Bool?
    var distance: Double?
    var averageHeartRate: Double?
    var recovery: Double?

    var id: UUID { interval.id }
    var minutes: Double { (interval.workoutDuration ?? 0) / 60 }
    var pace: Double? {
        guard let distance, distance.isFinite, distance > 0, minutes > 0 else { return nil }
        return minutes * 60 / distance
    }

    var sport: TrainingSport {
        switch activity {
        case .running: .running
        case .traditionalStrengthTraining, .functionalStrengthTraining: .strength
        case .walking, .hiking: .walking
        case .cycling: .cycling
        case .swimming: .swimming
        default: .other
        }
    }
}

enum TrainingSport: String, CaseIterable {
    case running, strength, cycling, walking, swimming, other

    var title: LocalizedStringResource {
        switch self {
        case .running: "Running"
        case .strength: "Strength Training"
        case .cycling: "Cycling"
        case .walking: "Walking & Hiking"
        case .swimming: "Swimming"
        case .other: "Other Workouts"
        }
    }
}

struct TrainingWeek: Identifiable {
    let range: DateInterval
    let workouts: [TrainingWorkout]

    var id: Date { range.start }
    var total: Double { workouts.reduce(0) { $0 + $1.minutes } }

    func minutes(for sport: TrainingSport) -> Double {
        workouts.filter { $0.sport == sport }.reduce(0) { $0 + $1.minutes }
    }
}

struct TrainingReport {
    let interval: DateInterval
    let weeks: [TrainingWeek]
    let available: Bool

    var workouts: [TrainingWorkout] { weeks.flatMap(\.workouts) }

    init(interval: DateInterval, end: Date, workouts: [TrainingWorkout]?, calendar: Calendar) {
        self.interval = interval
        available = workouts != nil
        weeks = (0..<8).reversed().compactMap { offset in
            guard let start = calendar.date(byAdding: .day, value: -7 * (offset + 1), to: end),
                  let finish = calendar.date(byAdding: .day, value: -7 * offset, to: end)
            else { return nil }
            let range = DateInterval(start: start, end: finish)
            return TrainingWeek(range: range, workouts: (workouts ?? []).filter {
                $0.interval.start >= start && $0.interval.start < finish
            })
        }
    }
}
