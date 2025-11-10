import Foundation
import CoreGraphics

struct AccidentRecord: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    var recognizedPlate: String
    let location: String
    var address: String?

    let speedAtTimeOfEvent: Double?

    let videoFileName: String // Path do Supabase (ex: "public/video.mp4")
    var isProcessed: Bool
    var localVideoPath: String?
    var processedPlateImageName: String?

    // --- NOVO CAMPO (Para o Problema 3) ---
    var hasBeenViewed: Bool

    // Construtor completo que o Codable usará (adiciona hasBeenViewed)
    init(id: UUID, timestamp: Date, recognizedPlate: String, location: String, address: String?, speedAtTimeOfEvent: Double?, videoFileName: String, isProcessed: Bool, localVideoPath: String?, processedPlateImageName: String?, hasBeenViewed: Bool) {
        self.id = id
        self.timestamp = timestamp
        self.recognizedPlate = recognizedPlate
        self.location = location
        self.address = address
        self.speedAtTimeOfEvent = speedAtTimeOfEvent
        self.videoFileName = videoFileName
        self.isProcessed = isProcessed
        self.localVideoPath = localVideoPath
        self.processedPlateImageName = processedPlateImageName
        self.hasBeenViewed = hasBeenViewed
    }
}
