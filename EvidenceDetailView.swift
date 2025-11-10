import SwiftUI
import MapKit
import CoreLocation
import AVKit

struct LocationPin: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}

struct EvidenceDetailView: View {
    @State var record: AccidentRecord
    @Environment(\.dismiss) private var dismiss
    
    @State private var showDeleteAlert = false
    @State private var isDownloading = false
    @State private var isProcessing = false
    @State private var statusMessage = ""
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    
    @State private var videoPlayer: AVPlayer?
    @State private var processedPlateImage: UIImage?

    private var coordinate: CLLocationCoordinate2D? {
        let components = record.location.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard components.count == 2,
              let lat = Double(components[0]),
              let lon = Double(components[1]) else {
            return nil
        }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.setLocalizedDateFormatFromTemplate("dd MMMM yyyy")
        return formatter
    }
    
    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.setLocalizedDateFormatFromTemplate("HH:mm")
        return formatter
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                
                if let coord = coordinate {
                    Map(
                        coordinateRegion: .constant(MKCoordinateRegion(
                            center: coord,
                            span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
                        )),
                        annotationItems: [LocationPin(coordinate: coord)]
                    ) { pin in
                        MapMarker(coordinate: pin.coordinate, tint: .blue)
                    }
                    .frame(height: 120)
                    .cornerRadius(12)
                }
                
                VStack(alignment: .leading) {
                    Text("EVIDÊNCIA DE VÍDEO")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 4)
                    
                    if record.isProcessed {
                        if let player = videoPlayer {
                            VideoPlayer(player: player)
                                .frame(height: 240)
                                .cornerRadius(12)
                                .onAppear { player.play() }
                        } else {
                            ProgressView().frame(height: 240)
                            Text("Carregando vídeo...")
                        }
                        
                        if let plateImg = processedPlateImage {
                            Text("PLACA IDENTIFICADA")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.top, 16)
                            Image(uiImage: plateImg)
                                .resizable()
                                .scaledToFit()
                                .cornerRadius(8)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray, lineWidth: 1))
                        }
                        
                    } else {
                        // --- ESTADO NÃO PROCESSADO ---
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Processar Evidência da Nuvem")
                                .font(.headline)
                            
                            Button(action: {
                                Task { await downloadAndProcessVideo() }
                            }) {
                                Label("Baixar e Processar Vídeo", systemImage: "cloud.download.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isDownloading || isProcessing)
                            
                            if isDownloading {
                                ProgressView(statusMessage)
                                    .padding(.top, 8)
                            }
                            if isProcessing {
                                ProgressView(statusMessage)
                                    .padding(.top, 8)
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                    }
                }
                
                VStack(alignment: .leading) {
                    Text("DETALHES DO EVENTO")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 8)
                    
                    VStack(alignment: .leading, spacing: 16) {
                        InfoRow(icon: "calendar", label: "Data", value: dateFormatter.string(from: record.timestamp))
                        InfoRow(icon: "clock.fill", label: "Hora", value: timeFormatter.string(from: record.timestamp))
                        InfoRow(icon: "mappin.and.ellipse", label: "Localização", value: record.address ?? "Buscando endereço...")
                        if let speed = record.speedAtTimeOfEvent {
                            InfoRow(icon: "speedometer", label: "Velocidade no Evento", value: String(format: "%.0f km/h", speed))
                        }
                        InfoRow(icon: "car.fill", label: "Placa Reconhecida", value: record.recognizedPlate)
                        
                        // --- CORREÇÃO: Botão Re-analisar ---
                        if record.isProcessed && (record.recognizedPlate == "Não identificada" || record.recognizedPlate == "Erro: Vídeo inválido") {
                            Button(action: {
                                // Força o re-processamento
                                Task { await downloadAndProcessVideo() }
                            }) {
                                Label("Tentar Análise Novamente", systemImage: "arrow.clockwise.circle.fill")
                            }
                            .buttonStyle(.bordered)
                            .tint(.orange)
                            .padding(.top, 8)
                        }
                    }
                }
                
            }.padding()
        }
        .background(Color.white)
        .navigationTitle("Detalhe da Evidência")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    showDeleteAlert = true
                }) {
                    Label("Apagar", systemImage: "trash")
                }
                .tint(.red)
                .disabled(isProcessing || isDownloading)
            }
        }
        .onAppear {
            if !record.isProcessed && !record.hasBeenViewed {
                print("[APP] Marcando evento como 'visto' para remover o realce.")
                record.hasBeenViewed = true
                PersistenceManager.shared.updateAccidentRecord(record)
            }
            loadInitialData()
        }
        .alert("Erro", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .alert("Apagar Evento", isPresented: $showDeleteAlert) {
            Button("Apagar", role: .destructive, action: deleteEvent)
            Button("Cancelar", role: .cancel) { }
        }
    }
    
    private func loadInitialData() {
        if record.isProcessed {
            let localVideoName = record.localVideoPath ?? (record.videoFileName.split(separator: "/").last.map(String.init) ?? record.videoFileName)
            
            if let url = PersistenceManager.shared.getVideoURL(named: localVideoName) {
                self.videoPlayer = AVPlayer(url: url)
            }
            if let plateImageName = record.processedPlateImageName {
                self.processedPlateImage = PersistenceManager.shared.loadImage(named: plateImageName)
            }
        }
        
        if record.address == nil || record.address == "Buscando endereço..." || record.address == "Endereço não disponível" {
            guard let coord = coordinate else { return }
            
            Task {
                let location = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                if let fetchedAddress = await fetchAddress(for: location) {
                    var updatedRecord = self.record
                    updatedRecord.address = fetchedAddress
                    PersistenceManager.shared.updateAccidentRecord(updatedRecord)
                    
                    await MainActor.run {
                        self.record = updatedRecord
                    }
                }
            }
        }
    }
    
    private func downloadAndProcessVideo() async {
        isDownloading = true
        isProcessing = true // Mostra o spinner
        statusMessage = "Baixando \(record.videoFileName.split(separator: "/").last.map(String.init) ?? "")..."
        print("[APP] 💾 Iniciando download do Supabase: \(record.videoFileName)")

        var videoData: Data?
        do {
            videoData = try await SupabaseManager.shared.downloadVideo(fileName: record.videoFileName)
        } catch {
            print("[APP] ❌ Erro no download do Supabase: \(error.localizedDescription)")
            errorMessage = "Falha no download. Verifique sua conexão com a internet."
            showErrorAlert = true
            isDownloading = false
            isProcessing = false
            return
        }
        
        isDownloading = false
        
        guard let data = videoData else {
            errorMessage = "Falha no download. O arquivo estava vazio."
            showErrorAlert = true
            isProcessing = false
            return
        }
        
        print("[APP] ✅ Download do Supabase concluído: \(data.count) bytes")
        
        statusMessage = "Salvando vídeo localmente..."
        
        let localVideoName = (record.videoFileName.split(separator: "/").last.map(String.init) ?? record.videoFileName)
        
        guard let localURL = PersistenceManager.shared.saveVideo(data: data, named: localVideoName) else {
            errorMessage = "Falha ao salvar vídeo no dispositivo."
            showErrorAlert = true
            isProcessing = false
            return
        }
        
        print("[APP] 💾 Vídeo salvo localmente: \(localVideoName)")
        
        var updatedRecord = self.record
        updatedRecord.localVideoPath = localVideoName
        statusMessage = "Analisando vídeo para identificar placas..."
        
        print("[APP] 🔍 Iniciando análise de vídeo...")
        let result = await VideoProcessor.shared.processVideo(at: localURL)
        
        if result.bestPlateText == "Erro: Vídeo inválido" {
             print("[APP] ❌ O VideoProcessor falhou em ler o MP4.")
             statusMessage = "Erro ao processar vídeo."
             updatedRecord.recognizedPlate = "Erro: Vídeo inválido"
             updatedRecord.isProcessed = false // Permite tentar de novo
        } else {
            statusMessage = "Finalizando processamento..."
            updatedRecord.recognizedPlate = result.bestPlateText
            print("[APP] 🚗 Placa identificada: \(result.bestPlateText)")
            
            if let plateImage = result.bestPlateImage, let jpgData = plateImage.jpegData(compressionQuality: 0.8) {
                let plateImageName = "\(record.id)_plate.jpg"
                _ = PersistenceManager.shared.saveImage(imageData: jpgData, named: plateImageName)
                updatedRecord.processedPlateImageName = plateImageName
                print("[APP] 📸 Imagem da placa salva: \(plateImageName)")
                
                await MainActor.run {
                    self.processedPlateImage = plateImage
                }
            }
            
            updatedRecord.isProcessed = true
        }

        PersistenceManager.shared.updateAccidentRecord(updatedRecord)
        
        await MainActor.run {
            self.record = updatedRecord
            if updatedRecord.isProcessed {
                self.videoPlayer = AVPlayer(url: localURL)
            }
            self.isProcessing = false
            print("[APP] ✅ Processamento concluído!")
        }
        
        // Apaga da nuvem SÓ SE foi processado com sucesso
        if updatedRecord.isProcessed {
            Task {
                do {
                    try await SupabaseManager.shared.deleteVideo(fileName: record.videoFileName)
                } catch {
                    print("[APP] ⚠️ Falha ao apagar o vídeo da nuvem (não crítico): \(error.localizedDescription)")
                }
            }
        }
    }

    private func deleteEvent() {
        print("[APP] 🗑️ Apagando evento com ID: \(record.id)")
        PersistenceManager.shared.deleteAccidentRecord(record: record)
        Task {
            do {
                try await SupabaseManager.shared.deleteVideo(fileName: record.videoFileName)
                print("[APP] 🗑️ Vídeo de backup apagado da nuvem (se existia).")
            } catch {
                 print("[APP] ⚠️ Falha ao apagar vídeo da nuvem (não crítico): \(error.localizedDescription)")
            }
        }
        dismiss()
    }
    
    private func fetchAddress(for location: CLLocation) async -> String? {
        let geocoder = CLGeocoder()
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            if let placemark = placemarks.first {
                return [
                    placemark.thoroughfare,
                    placemark.subThoroughfare,
                    placemark.subLocality,
                    placemark.locality,
                    placemark.administrativeArea
                ]
                .compactMap { $0 }
                .joined(separator: ", ")
            }
            return "Endereço não encontrado"
        } catch {
            print("[APP] ❌ Erro no reverse geocoding: \(error.localizedDescription)")
            return "Falha ao obter endereço"
        }
    }
}

struct InfoRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.headline)
                .frame(width: 20, alignment: .center)
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading) {
                Text(label.uppercased())
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.body)
                    .fontWeight(label == "Placa Reconhecida" || label == "Velocidade no Evento" ? .bold : .regular)
                    .foregroundColor(label == "Placa Reconhecida" ? .blue : .primary)
            }
        }
    }
}
