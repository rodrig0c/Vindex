import Foundation
import Combine

struct SpeedDataPoint: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let speed: Double

    init(id: UUID = UUID(), timestamp: Date = Date(), speed: Double) {
        self.id = id
        self.timestamp = timestamp
        self.speed = speed
    }
}

final class TelemetryManager: ObservableObject {
    static let shared = TelemetryManager()

    @Published private(set) var dataPoints: [SpeedDataPoint] = []

    private let persistence = PersistenceManager.shared
    private let queue = DispatchQueue(label: "com.vindex.telemetry", qos: .background)

    var maxSpeed: Double {
        dataPoints.map { $0.speed }.max() ?? 0.0
    }

    var averageSpeed: Double {
        guard !dataPoints.isEmpty else { return 0.0 }
        return dataPoints.reduce(0.0) { $0 + $1.speed } / Double(dataPoints.count)
    }

    private init() {
        // Carrega em background e injeta no main thread
        queue.async { [weak self] in
            guard let self = self else { return }
            let loaded = self.persistence.loadTelemetryData()
            DispatchQueue.main.async {
                self.dataPoints = loaded
            }
        }
    }

    func addSpeedReading(speed: Double) {
        guard speed >= 0 else { return }
        let newPoint = SpeedDataPoint(timestamp: Date(), speed: speed)
        DispatchQueue.main.async {
            self.dataPoints.append(newPoint)
            self.saveAsync()
        }
    }

    func clearData() {
        DispatchQueue.main.async {
            self.dataPoints.removeAll()
            self.saveAsync()
        }
    }

    private func saveAsync() {
        let snapshot = self.dataPoints
        queue.async { [weak self] in
            self?.persistence.saveTelemetryData(snapshot)
        }
    }

    // Expose load/save helpers if needed elsewhere
    func forceReloadFromDisk() {
        queue.async { [weak self] in
            guard let self = self else { return }
            let loaded = self.persistence.loadTelemetryData()
            DispatchQueue.main.async {
                self.dataPoints = loaded
            }
        }
    }
}

