import Foundation
import AVFoundation
import UIKit

class VideoProcessor {
    static let shared = VideoProcessor()
    
    struct ProcessingResult {
        var bestPlateText: String
        var bestPlateImage: UIImage?
    }
    
    private init() {}
    
    func processVideo(at localURL: URL) async -> ProcessingResult {
        print("[VideoProcessor] Iniciando processamento de \(localURL.lastPathComponent)...")
        
        let asset = AVAsset(url: localURL)
        
        // --- CORREÇÃO 1: Obter a taxa de frames (FPS) real do vídeo ---
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let duration = try? await asset.load(.duration) else {
            print("[VideoProcessor] Erro: Não foi possível carregar as tracks ou a duração do vídeo.")
            return ProcessingResult(bestPlateText: "Erro: Vídeo inválido", bestPlateImage: nil)
        }
        
        let durationInSeconds = CMTimeGetSeconds(duration)
        
        if durationInSeconds == 0 {
            print("[VideoProcessor] Erro: Vídeo com duração de 0s.")
            return ProcessingResult(bestPlateText: "Erro: Vídeo inválido", bestPlateImage: nil)
        }
        
        // --- CORREÇÃO 2: Calcular o NÚMERO TOTAL DE FRAMES ---
        let frameRate = try? await track.load(.nominalFrameRate)
        let actualFPS = Double(frameRate ?? 25.0) // Assume 25fps se não conseguir ler
        let totalFramesToAnalyze = Int(durationInSeconds * actualFPS)
        
        print("[VideoProcessor] Duração: \(String(format: "%.2f", durationInSeconds))s. FPS: \(actualFPS). Total de frames para analisar: \(totalFramesToAnalyze)")
        
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        
        var bestPlateText = ""
        var bestPlateImage: UIImage? = nil
        
        // --- CORREÇÃO 3: Fazer o loop em TODOS OS FRAMES ---
        for i in 0..<totalFramesToAnalyze {
            // Calcula o tempo exato de cada frame
            let time = CMTime(seconds: Double(i) / actualFPS, preferredTimescale: 600)
            
            do {
                let cgImage = try await generator.image(at: time).image
                let uiImage = UIImage(cgImage: cgImage)
                
                // (Opcional: Adicionar um print a cada 10 frames para não poluir o log)
                if i % 10 == 0 {
                    print("[VideoProcessor] Analisando frame \(i)/\(totalFramesToAnalyze)...")
                }
                
                // 1. Deteta TODAS as caixas de placa no frame
                let plateBoxes = await YOLODetector.shared.detectPlates(in: uiImage)
                
                if plateBoxes.isEmpty {
                    continue // Próximo frame
                }
                
                var ocrResultsInFrame: [String] = []
                
                // 2. Faz o loop em CADA caixa de placa encontrada
                for plateBox in plateBoxes {
                    
                    guard let croppedImage = uiImage.crop(to: plateBox) else {
                        print("[VideoProcessor] Falha ao recortar frame.")
                        continue
                    }
                    
                    var imageForProcessing = croppedImage
                    if croppedImage.size.height > croppedImage.size.width {
                        imageForProcessing = croppedImage.rotated(by: 90) ?? croppedImage
                    }
                    
                    let fullBox = CGRect(origin: .zero, size: imageForProcessing.size)
                    
                    if let correctedImage = OpenCVWrapper.correctPerspective(for: imageForProcessing, withBoundingBox: fullBox) {
                        let ocrResult = LicensePlateOCR.shared.recognizeText(from: correctedImage)
                        if !ocrResult.isEmpty {
                            ocrResultsInFrame.append(ocrResult)
                        }
                    } else {
                         print("[VideoProcessor] Falha no OpenCV. Usando imagem recortada.")
                         let ocrResult = LicensePlateOCR.shared.recognizeText(from: imageForProcessing)
                         if !ocrResult.isEmpty {
                            ocrResultsInFrame.append(ocrResult)
                        }
                    }
                } // --- Fim do loop for plateBox ---
                
                // 3. Combina os resultados do frame
                let combinedText = ocrResultsInFrame.joined(separator: ", ")
                
                if !combinedText.isEmpty && combinedText.count >= bestPlateText.count {
                    print("[VideoProcessor] 🏆 Novo(s) melhor(es) placa(s) encontrada(s): '\(combinedText)'")
                    bestPlateText = combinedText
                    
                    // 4. Salva a imagem com as CAIXAS DESENHADAS
                    bestPlateImage = uiImage.drawRects(boxes: plateBoxes)
                }
                
            } catch {
                print("[VideoProcessor] Falha ao extrair frame \(i): \(error)")
            }
        }
        
        print("[VideoProcessor] Processamento de vídeo concluído.")
        
        if bestPlateText.isEmpty {
            bestPlateText = "Não identificada"
        }
        
        return ProcessingResult(bestPlateText: bestPlateText, bestPlateImage: bestPlateImage)
    }
}
