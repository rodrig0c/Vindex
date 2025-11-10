import Vision
import UIKit

class LicensePlateOCR {
    
    static let shared = LicensePlateOCR()
    private init() {}
    
    // Enum para os formatos
    private enum PlateFormat { case mercosul, old }
    
    // --- DICIONÁRIOS DE CORREÇÃO (AGRESSIVOS) ---
    // Baseado nas suas capturas de tela (E->6, T->1, C->G, Q->0 etc)
    private let letterToNumber: [Character: Character] = [
        "O": "0", "I": "1", "Z": "2", "S": "5", "B": "8", "G": "6",
        "A": "4", "Q": "0", "J": "1", "E": "6", "D": "0", "T": "1", "C": "G"
    ]
    
    private let numberToLetter: [Character: Character] = [
        "0": "O", "1": "I", "2": "Z", "5": "S", "8": "B",
        "6": "G", "4": "A", "7": "Z"
    ]
    
    private let letters = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    private let numbers = Set("0123456789")

    // Estrutura para armazenar um resultado de correção
    private struct CorrectionResult {
        let plate: String
        let format: PlateFormat
    }

    /// Ponto de entrada principal.
    func recognizeText(from croppedPlateImage: UIImage) -> String {
        // Tenta a imagem original
        if let plate = processImage(croppedPlateImage) {
            return plate
        }
        
        // Fallback: tenta a imagem rotacionada 180 graus
        if let rotatedImage = croppedPlateImage.rotated(by: 180),
           let plate = processImage(rotatedImage) {
            print("[OCR] Placa encontrada em imagem rotacionada 180 graus.")
            return plate
        }
        
        return "" // Retorna vazio se nenhuma orientação funcionar.
    }

    /// Processa uma única imagem (uma orientação) para encontrar a placa.
    private func processImage(_ image: UIImage) -> String? {
        guard let cgImage = image.cgImage else { return nil }

        var rawText = ""
        var candidateStrings: [String] = []
        let semaphore = DispatchSemaphore(value: 0)

        let request = VNRecognizeTextRequest { (request, error) in
            defer { semaphore.signal() }
            if let results = request.results as? [VNRecognizedTextObservation] {
                // Junta todo o texto, incluindo hífens (ex: "HQW-5678")
                rawText = results.compactMap { $0.topCandidates(1).first?.string }.joined()
                // Pega os candidatos individuais
                candidateStrings = results.compactMap { $0.topCandidates(1).first?.string }
            }
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        
        try? VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
        semaphore.wait()
        
        // --- [LÓGICA ROBUSTA DE MÚLTIPLOS CANDIDATOS] ---
        
        // 1. A regra do hífen é a mais forte.
        let hasHyphen = rawText.contains("-")
        
        // 2. Limpa o texto para análise (ex: "HQW-5678" -> "HQW5678")
        let cleanedText = rawText.uppercased().filter { $0.isLetter || $0.isNumber }
        
        // 3. Adiciona todos os candidatos individuais (limpos) à lista de análise
        var allCandidatesToTest = Set<String>()
        candidateStrings.forEach { str in
            allCandidatesToTest.insert(str.uppercased().filter { $0.isLetter || $0.isNumber })
        }
        
        // 4. Adiciona substrings do texto limpo (para o caso de "XHQW5678")
        if cleanedText.count >= 7 {
            for i in 0...(cleanedText.count - 7) {
                let start = cleanedText.index(cleanedText.startIndex, offsetBy: i)
                let end = cleanedText.index(start, offsetBy: 7)
                allCandidatesToTest.insert(String(cleanedText[start..<end]))
            }
        }

        var validMercosulPlates: [CorrectionResult] = []
        var validOldPlates: [CorrectionResult] = []

        // 5. Itera por todos os candidatos e tenta os DOIS formatos
        for candidate in allCandidatesToTest.filter({ $0.count == 7 }) {
            
            // Tenta corrigir como Mercosul
            if let correctedPlate = correct(plate: candidate, as: .mercosul) {
                validMercosulPlates.append(CorrectionResult(plate: correctedPlate, format: .mercosul))
            }
            
            // Tenta corrigir como Cinza (Antigo)
            if let correctedPlate = correct(plate: candidate, as: .old) {
                validOldPlates.append(CorrectionResult(plate: correctedPlate, format: .old))
            }
        }

        // --- 6. LÓGICA DE DECISÃO (MESMO PESO) ---
        
        // Caso 1: Encontrou SÓ Mercosul.
        if !validMercosulPlates.isEmpty && validOldPlates.isEmpty {
            print("[OCR] Veredito: Placa Mercosul (Sem ambiguidade).")
            return validMercosulPlates.first!.plate // Retorna a primeira válida
        }
        
        // Caso 2: Encontrou SÓ Cinza.
        if validMercosulPlates.isEmpty && !validOldPlates.isEmpty {
            print("[OCR] Veredito: Placa Cinza (Sem ambiguidade).")
            return validOldPlates.first!.plate // Retorna a primeira válida
        }
        
        // Caso 3: Ambiguidade (Encontrou AMBOS).
        // Ex: OCR lê "ABC1E34", que pode ser "ABC1E34" (Mercosul) ou "ABC1634" (Cinza)
        if !validMercosulPlates.isEmpty && !validOldPlates.isEmpty {
            print("[OCR] Ambiguidade detectada. Usando o HÍFEN como desempate...")
            // A regra do hífen é o desempate
            if hasHyphen {
                print("[OCR] Veredito: Hífen encontrado. Priorizando Placa Cinza.")
                return validOldPlates.first!.plate
            } else {
                print("[OCR] Veredito: Sem hífen. Priorizando Placa Mercosul.")
                return validMercosulPlates.first!.plate
            }
        }
        
        // Caso 4: Não encontrou nada.
        print("[OCR] Veredito: Nenhum padrão de placa válido foi encontrado.")
        return nil
    }

    /// Aplica a correção posicional baseada no formato da placa.
    private func correct(plate: String, as format: PlateFormat) -> String? {
        guard plate.count == 7 else { return nil }
        var correctedChars = Array(plate)

        switch format {
        case .old: // LLLNNNN
            // Posições 0-2: Devem ser letras.
            for i in 0..<3 {
                if numbers.contains(correctedChars[i]), let fix = numberToLetter[correctedChars[i]] {
                    correctedChars[i] = fix
                }
            }
            // Posições 3-6: Devem ser números.
            for i in 3..<7 {
                // Usa o dicionário agressivo
                if letters.contains(correctedChars[i]), let fix = letterToNumber[correctedChars[i]] {
                    correctedChars[i] = fix
                }
            }

        case .mercosul: // LLLNLNN
            // Posições 0-2 (Letras)
            for i in 0..<3 {
                if numbers.contains(correctedChars[i]), let fix = numberToLetter[correctedChars[i]] {
                    correctedChars[i] = fix
                }
            }
            // Posição 3 (Número)
            if letters.contains(correctedChars[3]), let fix = letterToNumber[correctedChars[3]] {
                correctedChars[3] = fix
            }
            // Posição 4 (Letra)
            if numbers.contains(correctedChars[4]), let fix = numberToLetter[correctedChars[4]] {
                correctedChars[4] = fix
            }
            // Posições 5-6 (Números)
            for i in 5..<7 {
                if letters.contains(correctedChars[i]), let fix = letterToNumber[correctedChars[i]] {
                    correctedChars[i] = fix
                }
            }
        }
        
        let finalPlate = String(correctedChars)
        
        // Validação final: A placa corrigida DEVE bater 100% com o formato
        return isValid(plate: finalPlate, as: format) ? finalPlate : nil
    }

    /// Valida estritamente se uma string corresponde a um formato de placa.
    private func isValid(plate: String, as format: PlateFormat) -> Bool {
        guard plate.count == 7 else { return false }
        let chars = Array(plate)
        
        switch format {
        case .old: // LLLNNNN
            return  letters.contains(chars[0]) && letters.contains(chars[1]) && letters.contains(chars[2]) &&
                    numbers.contains(chars[3]) && numbers.contains(chars[4]) && numbers.contains(chars[5]) && numbers.contains(chars[6])
        case .mercosul: // LLLNLNN
            return  letters.contains(chars[0]) && letters.contains(chars[1]) && letters.contains(chars[2]) &&
                    numbers.contains(chars[3]) &&
                    letters.contains(chars[4]) &&
                    numbers.contains(chars[5]) && numbers.contains(chars[6])
        }
    }
}


// Extensões de UIImage (Não alteradas)
extension UIImage {
    func rotated(by degrees: CGFloat) -> UIImage? {
        let radians = degrees * .pi / 180
        var newSize = CGRect(origin: .zero, size: self.size).applying(CGAffineTransform(rotationAngle: radians)).size
        newSize.width = floor(newSize.width)
        newSize.height = floor(newSize.height)
        UIGraphicsBeginImageContextWithOptions(newSize, false, self.scale)
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        context.translateBy(x: newSize.width / 2, y: newSize.height / 2)
        context.rotate(by: radians)
        self.draw(in: CGRect(x: -self.size.width / 2, y: -self.size.height / 2, width: self.size.width, height: self.size.height))
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return newImage
    }
    
    func crop(to rect: CGRect) -> UIImage? {
        let scale = self.scale
        let cropRect = CGRect(
            x: rect.origin.x * scale,
            y: rect.origin.y * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
        guard let cgImage = self.cgImage?.cropping(to: cropRect) else { return nil }
        return UIImage(cgImage: cgImage, scale: scale, orientation: self.imageOrientation)
    }
}
