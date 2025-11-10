import Foundation
import UIKit

final class PersistenceManager {
    static let shared = PersistenceManager()
    
    // Nomes dos arquivos para o novo sistema de armazenamento
    private let recordsFileName = "accidentRecords.json"
    private let telemetryFileName = "telemetryData.json"
    
    // Chaves antigas do UserDefaults para a migração
    private let oldRecordsKey = "accidentRecords"
    private let oldTelemetryKey = "telemetryDataPoints"

    private init() {
        // A migração é chamada uma única vez quando o app é iniciado
        performOneTimeMigration()
    }

    private func getDocumentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    // --- LÓGICA DE MIGRAÇÃO ÚNICA ---
    private func performOneTimeMigration() {
        let recordsFileURL = getDocumentsDirectory().appendingPathComponent(recordsFileName)
        
        // Se o novo arquivo já existe, a migração não é necessária.
        if FileManager.default.fileExists(atPath: recordsFileURL.path) {
            print("[Persistence] Migração não necessária. Usando sistema de arquivos.")
            return
        }
        
        print("[Persistence] INICIANDO MIGRAÇÃO ÚNICA DE USERDEFAULTS PARA ARQUIVO...")
        
        // 1. Migrar Registros de Acidentes
        if let oldData = UserDefaults.standard.data(forKey: oldRecordsKey) {
            if let records = decode(data: oldData, as: [AccidentRecord].self) {
                save(object: records, to: recordsFileName)
                print("[Persistence] ✅ Sucesso: \(records.count) registros de acidentes migrados.")
                // Opcional: remover a chave antiga após a migração bem-sucedida
                // UserDefaults.standard.removeObject(forKey: oldRecordsKey)
            }
        }

        // 2. Migrar Dados de Telemetria
        if let oldData = UserDefaults.standard.data(forKey: oldTelemetryKey) {
            if let telemetry = decode(data: oldData, as: [SpeedDataPoint].self) {
                save(object: telemetry, to: telemetryFileName)
                print("[Persistence] ✅ Sucesso: \(telemetry.count) pontos de telemetria migrados.")
                // UserDefaults.standard.removeObject(forKey: oldTelemetryKey)
            }
        }
        
        print("[Persistence] MIGRAÇÃO CONCLUÍDA.")
    }


    // MARK: - Accident Records (usando o novo sistema de arquivos)

    // Modificado: Não salva mais 'imageData', apenas o registro
    func saveAccidentRecord(record: AccidentRecord) {
        var allRecords = loadAccidentRecords()
        if let index = allRecords.firstIndex(where: { $0.id == record.id }) {
            allRecords[index] = record
        } else {
            allRecords.insert(record, at: 0)
        }
        
        save(object: allRecords, to: recordsFileName)
    }

    func loadAccidentRecords() -> [AccidentRecord] {
        return load(from: recordsFileName, as: [AccidentRecord].self) ?? []
    }

    func deleteAccidentRecord(record: AccidentRecord) {
        // Deleta o vídeo local, se existir
        if let videoPath = record.localVideoPath {
            deleteFile(named: videoPath)
        }
        // Deleta a imagem da placa processada, se existir
        if let plateImage = record.processedPlateImageName {
            deleteFile(named: plateImage)
        }
        
        // Remove o registro do JSON
        var all = loadAccidentRecords()
        all.removeAll { $0.id == record.id }
        save(object: all, to: recordsFileName)
    }

    func updateAccidentRecord(_ updatedRecord: AccidentRecord) {
        var all = loadAccidentRecords()
        if let idx = all.firstIndex(where: { $0.id == updatedRecord.id }) {
            all[idx] = updatedRecord
        } else {
            all.insert(updatedRecord, at: 0) // Insere se for novo
        }
        save(object: all, to: recordsFileName)
    }
    
    // MARK: - Gerenciamento de Arquivos (Vídeo e Imagem)

    func saveImage(imageData: Data, named: String) -> URL? {
        let url = getDocumentsDirectory().appendingPathComponent(named)
        do {
            try imageData.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return url
        } catch {
            print("[Persistence] Falha ao salvar imagem \(named): \(error)")
            return nil
        }
    }
    
    func saveVideo(data: Data, named: String) -> URL? {
        let url = getDocumentsDirectory().appendingPathComponent(named)
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            print("[Persistence] Vídeo salvo em: \(url.path)")
            return url
        } catch {
            print("[Persistence] Falha ao salvar vídeo \(named): \(error)")
            return nil
        }
    }

    func loadImage(named imageName: String) -> UIImage? {
        let url = getDocumentsDirectory().appendingPathComponent(imageName)
        return UIImage(contentsOfFile: url.path)
    }
    
    func getVideoURL(named videoName: String) -> URL? {
        let url = getDocumentsDirectory().appendingPathComponent(videoName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
    
    func deleteFile(named fileName: String) {
         let url = getDocumentsDirectory().appendingPathComponent(fileName)
         if FileManager.default.fileExists(atPath: url.path) {
             try? FileManager.default.removeItem(at: url)
             print("[Persistence] Arquivo deletado: \(fileName)")
         }
    }

    // MARK: - Telemetria (usando o novo sistema de arquivos)

    func saveTelemetryData(_ dataPoints: [SpeedDataPoint]) {
        save(object: dataPoints, to: telemetryFileName)
    }

    func loadTelemetryData() -> [SpeedDataPoint] {
        return load(from: telemetryFileName, as: [SpeedDataPoint].self) ?? []
    }

    // MARK: - Funções de Salvar/Carregar JSON

    private func save<T: Encodable>(object: T, to fileName: String) {
        let url = getDocumentsDirectory().appendingPathComponent(fileName)
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(object)
            
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            
        } catch {
            print("[Persistence] Falha ao salvar \(fileName): \(error.localizedDescription)")
        }
    }

    private func load<T: Decodable>(from fileName: String, as type: T.Type) -> T? {
        let url = getDocumentsDirectory().appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return decode(data: data, as: type)
    }
    
    // Função helper para decodificar
    private func decode<T: Decodable>(data: Data, as type: T.Type) -> T? {
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(T.self, from: data)
        } catch {
            print("[Persistence] Falha ao decodificar dados: \(error.localizedDescription)")
            return nil
        }
    }
}
