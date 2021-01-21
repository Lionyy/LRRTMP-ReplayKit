//
//  RYPixcelBufferHandler.m
//  LFLiveKit-ReplayKit
//
//  Created by RoyLei on 2021/1/20.
//

#import "RYPixcelBufferHandler.h"
#import "MTIImage+Filters.h"
#import "MTIContext+Rendering.h"
#import "MTIImage+Filters.h"
#import "MTITransformFilter.h"
#import "MTICVPixelBufferPool.h"
#import <Accelerate/Accelerate.h>

@interface RYPixcelBufferHandler ()

@property (nonatomic, strong) MTIContext * mtiContext;
@property (nonatomic, strong) MTICVPixelBufferPool *pixelBufferPool;

@end

@implementation RYPixcelBufferHandler

void freePixelBufferDataAfterRelease(void *releaseRefCon, const void *baseAddress) {
    // Free the memory we malloced for the vImage rotation
    free((void *)baseAddress);
}

/// Accelerate Framework vImageRotate90_Planar8 vImageRotate90_Planar16U rotate pixelBuffer use CPU
/// @param imageBuffer original pixelBuffer
/// @param videoOrientation 0 -- rotate 0 degrees (simply copy the data from src to dest)
///                         3 -- rotate 90 degrees clockwise
///                         2 -- rotate 180 degress clockwise
///                         1 -- rotate 270 degrees clockwise
- (CVPixelBufferRef)rotateVImagePixelBuffer:(CVPixelBufferRef)imageBuffer videoOrientation:(CGImagePropertyOrientation)videoOrientation {
    
    OSType pixelFormatType = CVPixelBufferGetPixelFormatType(imageBuffer);
    const size_t planeCount = CVPixelBufferGetPlaneCount(imageBuffer);

    if (pixelFormatType != kCVPixelFormatType_420YpCbCr8BiPlanarFullRange) {
        return imageBuffer;
    }
    
    if (planeCount != 2) {
        return imageBuffer;
    }

    uint8_t rotationConstant = kRotate0DegreesClockwise;
    switch (videoOrientation) {
        case kCGImagePropertyOrientationUp:
            rotationConstant = kRotate0DegreesClockwise;
            break;
        case kCGImagePropertyOrientationLeft:
            rotationConstant = kRotate90DegreesClockwise;
            break;
        case kCGImagePropertyOrientationDown:
            rotationConstant = kRotate180DegreesClockwise;
            break;
        case kCGImagePropertyOrientationRight:
            rotationConstant = kRotate270DegreesClockwise;
            break;
        default:
            break;
    }
        
    vImage_Error err = kvImageNoError;
    CVPixelBufferLockBaseAddress(imageBuffer, 0);
    const size_t width = CVPixelBufferGetWidth(imageBuffer);
    const size_t height = CVPixelBufferGetHeight(imageBuffer);
    
    const BOOL rotatePerpendicular = (rotationConstant == kRotate90DegreesClockwise ||
                                      rotationConstant == kRotate270DegreesClockwise); // Use enumeration values here
    
    const size_t outWidth = rotatePerpendicular ? height : width;
    const size_t outHeight= rotatePerpendicular ? width  : height;

    // create buffer
    CVPixelBufferRef rotatedBuffer = NULL;
    CVPixelBufferCreate(kCFAllocatorDefault, outWidth, outHeight, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, NULL, &rotatedBuffer);
    CVPixelBufferLockBaseAddress(rotatedBuffer, 0);

    // rotate Y plane
    vImage_Buffer originalYBuffer = { CVPixelBufferGetBaseAddressOfPlane(imageBuffer, 0), CVPixelBufferGetHeightOfPlane(imageBuffer, 0),
        CVPixelBufferGetWidthOfPlane(imageBuffer, 0), CVPixelBufferGetBytesPerRowOfPlane(imageBuffer, 0) };
    vImage_Buffer rotatedYBuffer = { CVPixelBufferGetBaseAddressOfPlane(rotatedBuffer, 0), CVPixelBufferGetHeightOfPlane(rotatedBuffer, 0),
        CVPixelBufferGetWidthOfPlane(rotatedBuffer, 0), CVPixelBufferGetBytesPerRowOfPlane(rotatedBuffer, 0) };
    err = vImageRotate90_Planar8(&originalYBuffer, &rotatedYBuffer, rotationConstant, 0.0, kvImageNoFlags);

    // rotate UV plane
    vImage_Buffer originalUVBuffer = { CVPixelBufferGetBaseAddressOfPlane(imageBuffer, 1), CVPixelBufferGetHeightOfPlane(imageBuffer, 1),
        CVPixelBufferGetWidthOfPlane(imageBuffer, 1), CVPixelBufferGetBytesPerRowOfPlane(imageBuffer, 1) };
    vImage_Buffer rotatedUVBuffer = { CVPixelBufferGetBaseAddressOfPlane(rotatedBuffer, 1), CVPixelBufferGetHeightOfPlane(rotatedBuffer, 1),
    CVPixelBufferGetWidthOfPlane(rotatedBuffer, 1), CVPixelBufferGetBytesPerRowOfPlane(rotatedBuffer, 1) };
    err = vImageRotate90_Planar16U(&originalUVBuffer, &rotatedUVBuffer, rotationConstant, 0.0, kvImageNoFlags);

    CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
    CVPixelBufferUnlockBaseAddress(rotatedBuffer, 0);

    return rotatedBuffer;
}

- (CVPixelBufferRef)rotateMetalPixelBuffer:(CVPixelBufferRef)pixelBuffer videoOrientation:(CGImagePropertyOrientation)videoOrientation {
    
    CVPixelBufferRef fixedPixelBufferRef = pixelBuffer;
    uint8_t rotationConstant = kRotate0DegreesClockwise;
    CGFloat angle = 0;
    
    switch (videoOrientation) {
        case kCGImagePropertyOrientationUp:
            rotationConstant = kRotate0DegreesClockwise;
            angle = 0;
            break;
        case kCGImagePropertyOrientationLeft:
            rotationConstant = kRotate90DegreesClockwise;
            angle = M_PI_2;
            break;
        case kCGImagePropertyOrientationDown:
            rotationConstant = kRotate180DegreesClockwise;
            angle = M_PI;
            break;
        case kCGImagePropertyOrientationRight:
            rotationConstant = kRotate270DegreesClockwise;
            angle = M_PI + M_PI_2;
            break;
        default:
            break;
    }
    
    if (rotationConstant > 0) {
        
        MTIImage *mtiImage = [[MTIImage alloc] initWithCVPixelBuffer:pixelBuffer alphaType:MTIAlphaTypeAlphaIsOne];
        
        CGAffineTransform transform = CGAffineTransformMakeRotation(angle);
        MTITransformFilter *transformFilter = [[MTITransformFilter alloc] init];
        transformFilter.inputImage = mtiImage;
        transformFilter.transform = CATransform3DMakeAffineTransform(transform);
        transformFilter.viewport = transformFilter.minimumEnclosingViewport;
        
        MTIImage *outputImage = transformFilter.outputImage;
        
        if (outputImage) {
            fixedPixelBufferRef = [self createPixelBuffer:pixelBuffer withConstant:rotationConstant];
            NSError *error = nil;
            if (fixedPixelBufferRef != NULL) {
                if (![self.mtiContext renderImage:outputImage toCVPixelBuffer:fixedPixelBufferRef error:&error]) {
                    NSLog(@"MTIContext renderImage error %@", error);
                    CVPixelBufferRelease(fixedPixelBufferRef);
                }
            }
        }
    }
    
    return fixedPixelBufferRef;
}

- (CVPixelBufferRef)rotatePixelBuffer:(CVPixelBufferRef)pixelBuffer videoOrientation:(CGImagePropertyOrientation)videoOrientation useMetal:(BOOL)useMetal
{
    if (useMetal) {
        return [self rotateMetalPixelBuffer:pixelBuffer videoOrientation:videoOrientation];
    }else {
        return [self rotateVImagePixelBuffer:pixelBuffer videoOrientation:videoOrientation];
    }
}

#pragma mark - Private Methods

- (CVPixelBufferRef)createPixelBuffer:(CVPixelBufferRef)imageBuffer withConstant:(uint8_t)rotationConstant {
    
    OSType pixelFormatType = CVPixelBufferGetPixelFormatType(imageBuffer);

    CVPixelBufferLockBaseAddress(imageBuffer, 0);
    const size_t width = CVPixelBufferGetWidth(imageBuffer);
    const size_t height = CVPixelBufferGetHeight(imageBuffer);
    
    const BOOL rotatePerpendicular = (rotationConstant == kRotate90DegreesClockwise ||
                                      rotationConstant == kRotate270DegreesClockwise); // Use enumeration values here
    
    const size_t outWidth = rotatePerpendicular ? height : width;
    const size_t outHeight = rotatePerpendicular ? width  : height;
    NSError *error = nil;

    if (!_pixelBufferPool) {
        _pixelBufferPool = [[MTICVPixelBufferPool alloc] initWithPixelBufferWidth:outWidth
                                                                pixelBufferHeight:outHeight
                                                                  pixelFormatType:pixelFormatType
                                                               minimumBufferCount:1
                                                                            error:&error];
        if (!_pixelBufferPool) {
            NSLog(@"MTICVPixelBufferPool init error %@", error);
        }
    }

    CVPixelBufferRef rotatedBuffer = [_pixelBufferPool newPixelBufferWithAllocationThreshold:2 error:&error];
    if (rotatedBuffer == NULL) {
        NSLog(@"MTICVPixelBufferPool newPixelBufferWithAllocationThreshold error: %@", error);
    }
    
    return rotatedBuffer;
}

#pragma mark - Getter

- (MTIContext *)mtiContext {
    if (!_mtiContext) {
        NSError *error = nil;
        _mtiContext = [[MTIContext alloc] initWithDevice:MTLCreateSystemDefaultDevice() error:&error];
        if (!_mtiContext) {
            NSLog(@"Create MTIContext error %@", error);
        }
    }
    return _mtiContext;
}

@end
