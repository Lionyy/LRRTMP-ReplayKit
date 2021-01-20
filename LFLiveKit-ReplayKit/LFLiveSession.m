//
//  LFLiveSession.m
//  LFLiveKit
//
//  Created by LaiFeng on 16/5/20.
//  Copyright © 2016年 LaiFeng All rights reserved.
//

#import "LFLiveSession.h"
#import "LFHardwareVideoEncoder.h"
#import "LFHardwareAudioEncoder.h"
#import "LFStreamRTMPSocket.h"
#import "LFLiveStreamInfo.h"
#import <Accelerate/Accelerate.h>
#import "MTIImage+Filters.h"
#import "MTIContext+Rendering.h"
#import "MTIImage+Filters.h"
#import "MTITransformFilter.h"
#import "MTICVPixelBufferPool.h"

@interface LFLiveSession ()<LFAudioEncodingDelegate, LFVideoEncodingDelegate, LFStreamSocketDelegate>

/// 音频配置
@property (nonatomic, strong) LFLiveAudioConfiguration *audioConfiguration;
/// 视频配置
@property (nonatomic, strong) LFLiveVideoConfiguration *videoConfiguration;
/// 音频编码
@property (nonatomic, strong) id<LFAudioEncoding> audioEncoder;
/// 视频编码
@property (nonatomic, strong) id<LFVideoEncoding> videoEncoder;
/// 上传
@property (nonatomic, strong) id<LFStreamSocket> socket;

#pragma mark -- 内部标识
/// 调试信息
@property (nonatomic, strong) LFLiveDebug *debugInfo;
/// 流信息
@property (nonatomic, strong) LFLiveStreamInfo *streamInfo;
/// 是否开始上传
@property (nonatomic, assign) BOOL uploading;
/// 当前状态
@property (nonatomic, assign, readwrite) LFLiveState state;
/// 当前直播type
@property (nonatomic, assign, readwrite) LFLiveCaptureTypeMask captureType;
/// 时间戳锁
@property (nonatomic, strong) dispatch_semaphore_t lock;

@end

/**  时间戳 */
#define NOW (CACurrentMediaTime()*1000)

@interface LFLiveSession ()

/// 上传相对时间戳
@property (nonatomic, assign) uint64_t relativeTimestamps;
/// 音视频是否对齐
@property (nonatomic, assign) BOOL AVAlignment;
/// 当前是否采集到了音频
@property (nonatomic, assign) BOOL hasCaptureAudio;
/// 当前是否采集到了关键帧
@property (nonatomic, assign) BOOL hasKeyFrameVideo;

//@property (nonatomic, strong) CIContext *cicontext;

@property (nonatomic, assign) CGImagePropertyOrientation lastOrientation;

@property (nonatomic, assign) BOOL landscape;

@property (nonatomic, strong) MTIContext * mtiContext;
@property (nonatomic, strong) MTICVPixelBufferPool *pixelBufferPool;
@end

@implementation LFLiveSession

#pragma mark -- LifeCycle
- (instancetype)initWithAudioConfiguration:(nullable LFLiveAudioConfiguration *)audioConfiguration videoConfiguration:(nullable LFLiveVideoConfiguration *)videoConfiguration {
    return [self initWithAudioConfiguration:audioConfiguration videoConfiguration:videoConfiguration captureType:LFLiveInputMaskAll];
}

- (nullable instancetype)initWithAudioConfiguration:(nullable LFLiveAudioConfiguration *)audioConfiguration videoConfiguration:(nullable LFLiveVideoConfiguration *)videoConfiguration captureType:(LFLiveCaptureTypeMask)captureType{
    if (self = [super init]) {
        _audioConfiguration = audioConfiguration;
        _videoConfiguration = videoConfiguration;
        _adaptiveBitrate = NO;
        _captureType = captureType;
        _lastOrientation = kCGImagePropertyOrientationUp;
    }
    return self;
}

- (void)dealloc {
}

#pragma mark -- CustomMethod
- (void)startLive:(LFLiveStreamInfo *)streamInfo {
    if (!streamInfo) return;
    _streamInfo = streamInfo;
    _streamInfo.videoConfiguration = _videoConfiguration;
    _streamInfo.audioConfiguration = _audioConfiguration;
    [self.socket start];
}

- (void)stopLive {
    self.uploading = NO;
    [self.socket stop];
    self.socket = nil;
}

- (void)pushAudioBuffer:(CMSampleBufferRef)sampleBuffer {
    AudioBufferList audioBufferList;
    CMBlockBufferRef blockBuffer;
    
    CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sampleBuffer, NULL, &audioBufferList, sizeof(audioBufferList), NULL, NULL, 0, &blockBuffer);
    
    for( int y=0; y<audioBufferList.mNumberBuffers; y++ ) {
        AudioBuffer audioBuffer = audioBufferList.mBuffers[y];
        void* audio = audioBuffer.mData;
        NSData *data = [NSData dataWithBytes:audio length:audioBuffer.mDataByteSize];
        [self pushAudio:data];
    }
    CFRelease(blockBuffer);
}

- (void)pushVideoBuffer:(CMSampleBufferRef)sampleBuffer {
    [self pushVideoBuffer:sampleBuffer videoOrientation:kCGImagePropertyOrientationUp];
}

- (void)pushVideoBuffer:(CMSampleBufferRef)sampleBuffer videoOrientation:(uint32_t)videoOrientation {
    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
//    NSLog(@"pixelBuffer size %@", NSStringFromCGSize(CVImageBufferGetDisplaySize(pixelBuffer)));
    if(self.captureType & LFLiveInputMaskVideo){
        if (self.uploading) [self.videoEncoder encodeVideoData:pixelBuffer timeStamp:NOW videoOrientation:videoOrientation];
    }
}

- (void)pushAudio:(nullable NSData*)audioData{
    if(self.captureType & LFLiveInputMaskAudio){
        if (self.uploading) [self.audioEncoder encodeAudioData:audioData timeStamp:NOW];
    }
}

#pragma mark -- PrivateMethod
//Rotate  CMSampleBufferRef to landscape

void freePixelBufferDataAfterRelease(void *releaseRefCon, const void *baseAddress)
{
    // Free the memory we malloced for the vImage rotation
    free((void *)baseAddress);
}

/* rotationConstant:
 *  0 -- rotate 0 degrees (simply copy the data from src to dest)
 *  1 -- rotate 90 degrees counterclockwise
 *  2 -- rotate 180 degress
 *  3 -- rotate 270 degrees counterclockwise
 */
//- (CVPixelBufferRef)rotateBuffer:(CMSampleBufferRef)sampleBuffer withConstant:(uint8_t)rotationConstant
//{
//    CVImageBufferRef imageBuffer        = CMSampleBufferGetImageBuffer(sampleBuffer);
//    CVPixelBufferLockBaseAddress(imageBuffer, 0);
//
//    OSType pixelFormatType              = CVPixelBufferGetPixelFormatType(imageBuffer);
//
//    NSAssert(pixelFormatType == kCVPixelFormatType_32ARGB, @"Code works only with 32ARGB format. Test/adapt for other formats!");
//
//    const size_t kAlignment_32ARGB      = 32;
//    const size_t kBytesPerPixel_32ARGB  = 4;
//
//    size_t bytesPerRow                  = CVPixelBufferGetBytesPerRow(imageBuffer);
//    size_t width                        = CVPixelBufferGetWidth(imageBuffer);
//    size_t height                       = CVPixelBufferGetHeight(imageBuffer);
//
//    BOOL rotatePerpendicular            = (rotationConstant == 1) || (rotationConstant == 3); // Use enumeration values here
//    const size_t outWidth               = rotatePerpendicular ? height : width;
//    const size_t outHeight              = rotatePerpendicular ? width  : height;
//
//    size_t bytesPerRowOut               = kBytesPerPixel_32ARGB * ceil(outWidth * 1.0 / kAlignment_32ARGB) * kAlignment_32ARGB;
//
//    const size_t dstSize                = bytesPerRowOut * outHeight * sizeof(unsigned char);
//
//    void *srcBuff                       = CVPixelBufferGetBaseAddress(imageBuffer);
//
//    unsigned char *dstBuff              = (unsigned char *)malloc(dstSize);
//
//    vImage_Buffer inbuff                = {srcBuff, height, width, bytesPerRow};
//    vImage_Buffer outbuff               = {dstBuff, outHeight, outWidth, bytesPerRowOut};
//
//    uint8_t bgColor[4]                  = {0, 0, 0, 0};
//
//    vImage_Error err                    = vImageRotate90_ARGB8888(&inbuff, &outbuff, rotationConstant, bgColor, 0);
//    if (err != kvImageNoError)
//    {
//        NSLog(@"%ld", err);
//    }
//
//    CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
//
//    CVPixelBufferRef rotatedBuffer      = NULL;
//    CVPixelBufferCreateWithBytes(NULL,
//                                 outWidth,
//                                 outHeight,
//                                 pixelFormatType,
//                                 outbuff.data,
//                                 bytesPerRowOut,
//                                 freePixelBufferDataAfterRelease,
//                                 NULL,
//                                 NULL,
//                                 &rotatedBuffer);
//
//    return rotatedBuffer;
//}

/* rotationConstant:
 *  0 -- rotate 0 degrees (simply copy the data from src to dest)
 *  3 -- rotate 90 degrees clockwise
 *  2 -- rotate 180 degress clockwise
 *  1 -- rotate 270 degrees clockwise
 */
- (CVPixelBufferRef)rotateBuffer:(CMSampleBufferRef)sampleBuffer withConstant:(uint8_t)rotationConstant {
    
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    OSType pixelFormatType = CVPixelBufferGetPixelFormatType(imageBuffer);
    const size_t planeCount = CVPixelBufferGetPlaneCount(imageBuffer);

    NSAssert(pixelFormatType == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, @"Code works only with 420f format. Test/adapt for other formats!");
    NSAssert(planeCount == 2, @"PlaneCount error!");

    vImage_Error err = kvImageNoError;
    CVPixelBufferLockBaseAddress(imageBuffer, 0);
    const size_t width = CVPixelBufferGetWidth(imageBuffer);
    const size_t height = CVPixelBufferGetHeight(imageBuffer);
    
    const BOOL rotatePerpendicular = (rotationConstant == kRotate90DegreesClockwise) || (rotationConstant == kRotate270DegreesClockwise); // Use enumeration values here
    const size_t outWidth          = rotatePerpendicular ? height : width;
    const size_t outHeight         = rotatePerpendicular ? width  : height;

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

- (CVPixelBufferRef)createPixelBuffer:(CMSampleBufferRef)sampleBuffer withConstant:(uint8_t)rotationConstant {
    
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    OSType pixelFormatType = CVPixelBufferGetPixelFormatType(imageBuffer);

    vImage_Error err = kvImageNoError;
    CVPixelBufferLockBaseAddress(imageBuffer, 0);
    const size_t width = CVPixelBufferGetWidth(imageBuffer);
    const size_t height = CVPixelBufferGetHeight(imageBuffer);
    
    const BOOL rotatePerpendicular = (rotationConstant == kRotate90DegreesClockwise) || (rotationConstant == kRotate270DegreesClockwise); // Use enumeration values here
    const size_t outWidth          = rotatePerpendicular ? height : width;
    const size_t outHeight         = rotatePerpendicular ? width  : height;
    NSError *error = nil;

    if (!_pixelBufferPool) {
        _pixelBufferPool = [[MTICVPixelBufferPool alloc] initWithPixelBufferWidth:outWidth pixelBufferHeight:outHeight pixelFormatType:pixelFormatType minimumBufferCount:1 error:&error];
    }

    CVPixelBufferRef rotatedBuffer = [_pixelBufferPool newPixelBufferWithAllocationThreshold:2 error:&error];
    if (rotatedBuffer == NULL) {
        NSLog(@"MTICVPixelBufferPool newPixelBufferWithAllocationThreshold error: %@", error);
    }
    
    return rotatedBuffer;
}

- (CVPixelBufferRef)correctBufferOrientation:(CMSampleBufferRef)sampleBuffer videoOrientation:(uint32_t)videoOrientation
{
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    CVPixelBufferLockBaseAddress(imageBuffer, 0);

    size_t bytesPerRow                  = CVPixelBufferGetBytesPerRow(imageBuffer);
    size_t width                        = CVPixelBufferGetWidth(imageBuffer);
    size_t height                       = CVPixelBufferGetHeight(imageBuffer);

    void *srcBuff                       = CVPixelBufferGetBaseAddress(imageBuffer);
    
    size_t dstWidth                     = width;
    size_t dstHeight                    = height;

    /* rotationConstant:
     *  0 -- rotate 0 degrees (simply copy the data from src to dest)
     *  3 -- rotate 90 degrees clockwise
     *  2 -- rotate 180 degress clockwise
     *  1 -- rotate 270 degrees clockwise
     */
    uint8_t rotationConstant = kRotate0DegreesClockwise;
    CGImagePropertyOrientation cgOrientation = videoOrientation;
    NSLog(@"cgOrientation: %@", @(cgOrientation));

    switch (cgOrientation) {
        case kCGImagePropertyOrientationUp:
            rotationConstant = kRotate0DegreesClockwise;
            break;
        case kCGImagePropertyOrientationLeft:
            rotationConstant = kRotate90DegreesClockwise;
            dstWidth = height;
            dstHeight = width;
            break;
        case kCGImagePropertyOrientationDown:
            rotationConstant = kRotate180DegreesClockwise;
            break;
        case kCGImagePropertyOrientationRight:
            rotationConstant = kRotate270DegreesClockwise;
            dstWidth = height;
            dstHeight = width;
            break;
        default:
            break;
    }
    
    size_t destBytesPerRow = dstWidth * 4;
    size_t dstSize         = destBytesPerRow * dstHeight;
    uint8_t *dstBuff       = (uint8_t *)malloc(dstSize);
    size_t bytesPerRowOut  = 4 * dstHeight;
    
    vImage_Buffer inbuff   = {srcBuff, height, width, bytesPerRow};
    vImage_Buffer outbuff  = {dstBuff, dstHeight, dstWidth, bytesPerRowOut};
    uint8_t bgColor[4]     = {0, 0, 0, 0};

    vImage_Error err = vImageRotate90_ARGB8888(&inbuff, &outbuff, rotationConstant, bgColor, 0);
    if (err != kvImageNoError) NSLog(@"%ld", err);

    CVPixelBufferUnlockBaseAddress(imageBuffer, 0);

    CVPixelBufferRef rotatedBuffer = NULL;
    CVPixelBufferCreateWithBytes(NULL,
                                 height,
                                 width,
                                 kCVPixelFormatType_32BGRA,
                                 outbuff.data,
                                 bytesPerRowOut,
                                 freePixelBufferDataAfterRelease,
                                 NULL,
                                 NULL,
                                 &rotatedBuffer);

    return rotatedBuffer;
}

- (void)newPushVideoBuffer:(CMSampleBufferRef)sampleBuffer videoOrientation:(uint32_t)videoOrientation {
    
    CGImagePropertyOrientation cgOrientation = videoOrientation;
    uint8_t rotationConstant = 0;
//    NSLog(@"cgOrientation: %@", @(cgOrientation));

    switch (cgOrientation) {
        case kCGImagePropertyOrientationUp:
            self.landscape = NO;
            rotationConstant = 0;
            break;
        case kCGImagePropertyOrientationLeft:
            rotationConstant = 1;
            self.landscape = YES;
            break;
        case kCGImagePropertyOrientationDown:
            self.landscape = NO;
            rotationConstant = 2;
            break;
        case kCGImagePropertyOrientationRight:
            rotationConstant = 3;
            self.landscape = YES;
            break;
        default:
            break;
    }
    
    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    BOOL needRelease = NO;
    if (rotationConstant > 0) {
        if (!_mtiContext) {
            NSError *error = nil;
            _mtiContext = [[MTIContext alloc] initWithDevice:MTLCreateSystemDefaultDevice() error:&error];
            if (!_mtiContext) {
                NSLog(@"Create MTIContext error %@", error);
            }
        }
        
        MTIImage *mtiImage = [[MTIImage alloc] initWithCVPixelBuffer:pixelBuffer alphaType:MTIAlphaTypeAlphaIsOne];
        [mtiImage imageByApplyingCGOrientation:cgOrientation];
//        CGAffineTransform transform = CGAffineTransformRotate(CGAffineTransformIdentity, M_PI_2);
//
//        MTITransformFilter *transformFilter = [[MTITransformFilter alloc] init];
//        transformFilter.inputImage = mtiImage;
//        transformFilter.transform = CATransform3DMakeAffineTransform(transform);
//        transformFilter.viewport = transformFilter.minimumEnclosingViewport;
        
        if (mtiImage) {
            
            CVPixelBufferRef newPixelBufferRef = [self createPixelBuffer:sampleBuffer withConstant:rotationConstant];
            NSError *error = nil;
            if (newPixelBufferRef != NULL && [_mtiContext renderImage:mtiImage toCVPixelBuffer:newPixelBufferRef error:&error]) {
                pixelBuffer = newPixelBufferRef;//[self rotateBuffer:sampleBuffer withConstant:rotationConstant];
                needRelease = YES;
            }else {
                needRelease = NO;
                if (newPixelBufferRef != NULL) {
                    CVPixelBufferRelease(pixelBuffer);
                }
                pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
                NSLog(@"MTIContext renderImage error %@", error);
            }
        }
    }
    
    size_t width = CVPixelBufferGetWidth(pixelBuffer);
    size_t height = CVPixelBufferGetHeight(pixelBuffer);
    
//    CIImage *ciimage = [CIImage imageWithCVPixelBuffer:pixelBuffer];
//    CIImage *wImage = [ciimage imageByApplyingCGOrientation:kCGImagePropertyOrientationUp];
//    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
//    NSLog(@"sample width :%@ height :%@", @(width), @(height));
//
//    CVPixelBufferRef newPixcelBuffer = nil;
//    CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, nil, &newPixcelBuffer);
//
//    if(!_cicontext) {
//        _cicontext = [CIContext context];
//    }
//    [_cicontext render:wImage toCVPixelBuffer:newPixcelBuffer];
//    CVPixelBufferRelease(newPixcelBuffer);
//
    _videoConfiguration.videoSize = CGSizeMake(width, height);
    NSLog(@"Session: _videoConfiguration.videoSize :%@", NSStringFromCGSize(_videoConfiguration.videoSize));

    if (self.lastOrientation != cgOrientation) {
        self.lastOrientation = cgOrientation;
    }

    if(self.captureType & LFLiveInputMaskVideo) {
        if (self.uploading) [self.videoEncoder encodeVideoData:pixelBuffer timeStamp:NOW videoOrientation:videoOrientation];
    }
    
    if (needRelease) {
        CVPixelBufferRelease(pixelBuffer);
    }
    // roate ciimage
//    CIImage *wImage = [ciimage imageByApplyingCGOrientation:cgOrientation];
//    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
//    NSLog(@"sample width :%@ height :%@", @(width), @(height));
//
//    CVPixelBufferRef newPixcelBuffer = nil;
//    CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, nil, &newPixcelBuffer);
//
//    if(!_cicontext) {
//        _cicontext = [CIContext context];
//    }
//    [_cicontext render:wImage toCVPixelBuffer:newPixcelBuffer];
//
//    //encode newSampleBuffer by ************
//    if(self.captureType & LFLiveInputMaskVideo) {
//        if (self.uploading) [self.videoEncoder encodeVideoData:newPixcelBuffer timeStamp:NOW videoOrientation:videoOrientation];
//    }
//
//    // release
//    CVPixelBufferRelease(newPixcelBuffer);
}

- (void)pushSendBuffer:(LFFrame*)frame{
    if(self.relativeTimestamps == 0){
        self.relativeTimestamps = frame.timestamp;
    }
//    NSLog(@"%s", __func__);
    frame.timestamp = [self uploadTimestamp:frame.timestamp];
    [self.socket sendFrame:frame];
}

#pragma mark -- EncoderDelegate
- (void)audioEncoder:(nullable id<LFAudioEncoding>)encoder audioFrame:(nullable LFAudioFrame *)frame {
    ///<  时间戳对齐
    if (self.uploading){
        [self pushSendBuffer:frame];
//        self.hasCaptureAudio = YES;
//        if (self.AVAlignment) {
//        }
    }
}

- (void)videoEncoder:(nullable id<LFVideoEncoding>)encoder videoFrame:(nullable LFVideoFrame *)frame {
    ///< 时间戳对齐
    if (self.uploading){
//        if(frame.isKeyFrame && self.hasCaptureAudio){
//           self.hasKeyFrameVideo = YES;
//        }
        
        [self pushSendBuffer:frame];
//        if(self.AVAlignment) {
//        } else {
////            NSLog(@"videoEncoder self.AVAlignment NO");
//        }
        
    }
}

#pragma mark -- LFStreamTcpSocketDelegate
- (void)socketStatus:(nullable id<LFStreamSocket>)socket status:(LFLiveState)status {
    if (status == LFLiveStart) {
        if (!self.uploading) {
            self.AVAlignment = NO;
            self.hasCaptureAudio = NO;
            self.hasKeyFrameVideo = NO;
            self.relativeTimestamps = 0;
            self.uploading = YES;
        }
    } else if(status == LFLiveStop || status == LFLiveError){
        self.uploading = NO;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        self.state = status;
        if (self.delegate && [self.delegate respondsToSelector:@selector(liveSession:liveStateDidChange:)]) {
            [self.delegate liveSession:self liveStateDidChange:status];
        }
    });
}

- (void)socketDidError:(nullable id<LFStreamSocket>)socket errorCode:(LFLiveSocketErrorCode)errorCode {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.delegate && [self.delegate respondsToSelector:@selector(liveSession:errorCode:)]) {
            [self.delegate liveSession:self errorCode:errorCode];
        }
    });
}

- (void)socketDebug:(nullable id<LFStreamSocket>)socket debugInfo:(nullable LFLiveDebug *)debugInfo {
    self.debugInfo = debugInfo;
    if (self.showDebugInfo) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.delegate && [self.delegate respondsToSelector:@selector(liveSession:debugInfo:)]) {
                [self.delegate liveSession:self debugInfo:debugInfo];
            }
        });
    }
}

- (void)socketBufferStatus:(nullable id<LFStreamSocket>)socket status:(LFLiveBuffferState)status {
    if((self.captureType & LFLiveInputMaskVideo) && self.adaptiveBitrate){
        NSUInteger videoBitRate = [self.videoEncoder videoBitRate];
        if (status == LFLiveBuffferDecline) {
            if (videoBitRate < _videoConfiguration.videoMaxBitRate) {
                videoBitRate = videoBitRate + 50 * 1000;
                [self.videoEncoder setVideoBitRate:videoBitRate];
                NSLog(@"Increase bitrate %@", @(videoBitRate));
            }
        } else {
            if (videoBitRate > self.videoConfiguration.videoMinBitRate) {
                videoBitRate = videoBitRate - 100 * 1000;
                [self.videoEncoder setVideoBitRate:videoBitRate];
                NSLog(@"Decline bitrate %@", @(videoBitRate));
            }
        }
    }
}

#pragma mark -- Getter Setter

- (id<LFAudioEncoding>)audioEncoder {
    if (!_audioEncoder) {
        _audioEncoder = [[LFHardwareAudioEncoder alloc] initWithAudioStreamConfiguration:_audioConfiguration];
        [_audioEncoder setDelegate:self];
    }
    return _audioEncoder;
}

- (id<LFVideoEncoding>)videoEncoder {
    if (!_videoEncoder) {
        _videoEncoder = [[LFHardwareVideoEncoder alloc] initWithVideoStreamConfiguration:_videoConfiguration];
        [_videoEncoder setDelegate:self];
    }
    return _videoEncoder;
}

- (id<LFStreamSocket>)socket {
    if (!_socket) {
        _socket = [[LFStreamRTMPSocket alloc] initWithStream:self.streamInfo];
        [_socket setDelegate:self];
    }
    return _socket;
}

- (LFLiveStreamInfo *)streamInfo {
    if (!_streamInfo) {
        _streamInfo = [[LFLiveStreamInfo alloc] init];
    }
    return _streamInfo;
}

- (dispatch_semaphore_t)lock {
    if(!_lock){
        _lock = dispatch_semaphore_create(1);
    }
    return _lock;
}

- (uint64_t)uploadTimestamp:(uint64_t)captureTimestamp{
    dispatch_semaphore_wait(self.lock, DISPATCH_TIME_FOREVER);
    uint64_t currentts = 0;
    currentts = captureTimestamp - self.relativeTimestamps;
    dispatch_semaphore_signal(self.lock);
    return currentts;
}

- (BOOL)AVAlignment{
    if((self.captureType & LFLiveInputMaskAudio) &&
       (self.captureType & LFLiveInputMaskVideo)
       ){
        if(self.hasCaptureAudio && self.hasKeyFrameVideo) return YES;
        else  return NO;
    }else{
        return YES;
    }
}

@end
