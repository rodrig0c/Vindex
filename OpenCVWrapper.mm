#import <opencv2/opencv.hpp>
#import <opencv2/imgcodecs/ios.h>
#import "OpenCVWrapper.h"
#import <vector>

@implementation OpenCVWrapper

// --- VERSÃO V6: (BGRA -> GRAY) + Blur + CLAHE ---
// Adiciona um GaussianBlur para remover o ruído antes do CLAHE,
// o que deve impedir que o CLAHE amplifique o ruído e confunda o OCR.
+ (UIImage * _Nullable)correctPerspectiveFor:(UIImage *)image withBoundingBox:(CGRect)box {
    cv::Mat originalMat;
    UIImageToMat(image, originalMat); // Converte para BGRA
    if (originalMat.empty()) { return nil; }

    // --- ETAPA 1: Redimensiona/Corrige perspectiva ---
    float plateWidth = 440.0;
    float plateHeight = 130.0;

    cv::Point2f srcPoints[4];
    srcPoints[0] = cv::Point2f(box.origin.x, box.origin.y);
    srcPoints[1] = cv::Point2f(box.origin.x + box.size.width, box.origin.y);
    srcPoints[2] = cv::Point2f(box.origin.x + box.size.width, box.origin.y + box.size.height);
    srcPoints[3] = cv::Point2f(box.origin.x, box.origin.y + box.size.height);
    
    cv::Point2f dstPoints[4];
    dstPoints[0] = cv::Point2f(0, 0);
    dstPoints[1] = cv::Point2f(plateWidth - 1, 0);
    dstPoints[2] = cv::Point2f(plateWidth - 1, plateHeight - 1);
    dstPoints[3] = cv::Point2f(0, plateHeight - 1);

    cv::Mat M = cv::getPerspectiveTransform(srcPoints, dstPoints);
    cv::Mat warpedMat;
    cv::warpPerspective(originalMat, warpedMat, M, cv::Size(plateWidth, plateHeight));
    
    // --- [FIX V6] ETAPA 2: PRÉ-PROCESSAMENTO ---
    
    cv::Mat grayMat;
    cv::cvtColor(warpedMat, grayMat, cv::COLOR_BGRA2GRAY); // Correção de Cor

    // [FIX] 2. Adiciona um Blur suave para remover o ruído da imagem
    cv::Mat blurredMat;
    cv::GaussianBlur(grayMat, blurredMat, cv::Size(3, 3), 0);

    // 3. Aplica CLAHE na imagem *sem ruído*
    cv::Ptr<cv::CLAHE> clahe = cv::createCLAHE();
    clahe->setClipLimit(2.0);
    clahe->setTilesGridSize(cv::Size(8, 8));
    
    cv::Mat claheMat;
    clahe->apply(blurredMat, claheMat); // Aplica na imagem borrada

    // Retorna a imagem limpa e com contraste para o Vision
    return MatToUIImage(claheMat);
}

@end
