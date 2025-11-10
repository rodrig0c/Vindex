import UIKit

extension UIImage {
    
    /// Desenha uma ou mais caixas (CGRect) numa imagem.
    func drawRects(boxes: [CGRect], color: UIColor = .systemYellow, lineWidth: CGFloat = 2.0) -> UIImage {
        // Inicia o contexto de desenho
        UIGraphicsBeginImageContextWithOptions(self.size, false, self.scale)
        guard let context = UIGraphicsGetCurrentContext() else { return self }
        
        // Desenha a imagem original
        self.draw(at: .zero)
        
        // Configura a cor e a espessura da linha
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(lineWidth)
        
        // Desenha cada caixa
        for box in boxes {
            context.stroke(box)
        }
        
        // Obtém a nova imagem
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        
        // Fecha o contexto
        UIGraphicsEndImageContext()
        
        return newImage ?? self
    }
}
