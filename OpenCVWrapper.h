// Vindex/OpenCVWrapper.h

#ifndef OpenCVWrapper_h
#define OpenCVWrapper_h

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface OpenCVWrapper : NSObject

+ (UIImage * _Nullable)correctPerspectiveFor:(UIImage *)image withBoundingBox:(CGRect)box;

@end

NS_ASSUME_NONNULL_END

#endif /* OpenCVWrapper_h */
