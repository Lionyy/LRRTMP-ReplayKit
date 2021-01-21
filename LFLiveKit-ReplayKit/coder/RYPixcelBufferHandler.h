//
//  RYPixcelBufferHandler.h
//  LFLiveKit-ReplayKit
//
//  Created by RoyLei on 2021/1/20.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RYPixcelBufferHandler : NSObject

/// Metal rotate pixelBuffer use GPU and CPU
/// @param pixelBuffer original pixelBuffer
/// @param videoOrientation pixelBuffer CGImagePropertyOrientation property
/// @param useMetal 是否使用metal GPU进行画面旋转
- (CVPixelBufferRef)rotatePixelBuffer:(CVPixelBufferRef)pixelBuffer
                     videoOrientation:(CGImagePropertyOrientation)videoOrientation
                             useMetal:(BOOL)useMetal;

@end

NS_ASSUME_NONNULL_END
