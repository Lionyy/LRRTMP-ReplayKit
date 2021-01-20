//
//  RYPixcelBufferHandler.h
//  LFLiveKit-ReplayKit
//
//  Created by RoyLei on 2021/1/20.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RYPixcelBufferHandler : NSObject

/// Accelerate Framework vImageRotate90_Planar8 vImageRotate90_Planar16U rotate pixelBuffer use CPU
/// @param imageBuffer original pixelBuffer
/// @param rotationConstant 0 -- rotate 0 degrees (simply copy the data from src to dest)
///                         3 -- rotate 90 degrees clockwise
///                         2 -- rotate 180 degress clockwise
///                         1 -- rotate 270 degrees clockwise

- (CVPixelBufferRef)rotatePixelBuffer:(CVPixelBufferRef)imageBuffer withConstant:(uint8_t)rotationConstant;

/// Metal rotate pixelBuffer use GPU and CPU
/// @param pixelBuffer original pixelBuffer
/// @param videoOrientation pixelBuffer CGImagePropertyOrientation property
- (CVPixelBufferRef)rotatePixelBuffer:(CVPixelBufferRef)pixelBuffer videoOrientation:(CGImagePropertyOrientation)videoOrientation;

@end

NS_ASSUME_NONNULL_END
