//
//  LFHardwareVideoEncoder.m
//  LFLiveKit
//
//  Created by LaiFeng on 16/5/20.
//  Copyright © 2016年 LaiFeng All rights reserved.
//
#import "LFHardwareVideoEncoder.h"
#import <VideoToolbox/VideoToolbox.h>
#import <AVFoundation/AVFoundation.h>

#define LFUseAnnexBStyle 0

@interface LFHardwareVideoExtInfo : NSObject
@property (assign, nonatomic) uint32_t frameNumber;
@property (assign, nonatomic) uint64_t timeStamp;
@property (assign, nonatomic) CGImagePropertyOrientation videoOrientation;
@end

@implementation LFHardwareVideoExtInfo
@end

@interface LFHardwareVideoEncoder (){
    VTCompressionSessionRef compressionSession;
    NSInteger frameCount;
    NSData *vps;
    NSData *sps;
    NSData *pps;
    FILE *fp;
    BOOL enabledWriteVideoFile;
    BOOL inResetting;
}

@property (nonatomic, strong) LFLiveVideoConfiguration *configuration;
@property (nonatomic, weak) id<LFVideoEncodingDelegate> encoderDelegate;
@property (nonatomic) NSInteger currentVideoBitRate;
@property (nonatomic) BOOL isBackGround;
@property (nonatomic) uint32_t frameNumber;
@end

@implementation LFHardwareVideoEncoder

#pragma mark - LifeCycle
- (instancetype)initWithVideoStreamConfiguration:(LFLiveVideoConfiguration *)configuration {
    if (self = [super init]) {
        NSLog(@"USE LFHardwareVideoEncoder");
        _configuration = configuration;
        _frameNumber = 0;
        if (_configuration.encoderType == LFVideoH265Encoder) {
            if ([[AVAssetExportSession allExportPresets] containsObject:AVAssetExportPresetHEVCHighestQuality] &&
                VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC)) {
                _configuration.encoderType = LFVideoH265Encoder;
            }else {
                _configuration.encoderType = LFVideoH264Encoder;
            }
        }
        [self resetCompressionSession];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(willEnterBackground:) name:UIApplicationWillResignActiveNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(willEnterForeground:) name:UIApplicationDidBecomeActiveNotification object:nil];
#ifdef DEBUG
        enabledWriteVideoFile = NO;
        [self initForFilePath];
#endif
        
    }
    return self;
}

- (void)dealloc {
    if (compressionSession != NULL) {
        VTCompressionSessionCompleteFrames(compressionSession, kCMTimeInvalid);

        VTCompressionSessionInvalidate(compressionSession);
        CFRelease(compressionSession);
        compressionSession = NULL;
    }
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (BOOL)isSupportPropertyWithSession:(VTCompressionSessionRef)session key:(CFStringRef)key {
    OSStatus status;
    static CFDictionaryRef supportedPropertyDictionary;
    if (!supportedPropertyDictionary) {
        status = VTSessionCopySupportedPropertyDictionary(session, &supportedPropertyDictionary);
        if (status != noErr) {
            return NO;
        }
    }
    BOOL isSupport = [NSNumber numberWithBool:CFDictionaryContainsKey(supportedPropertyDictionary, key)].intValue;
    return isSupport;
}

- (void)resetCompressionSession {
    if (inResetting) {
        return;
    }
    inResetting = YES;
    if (compressionSession) {
        VTCompressionSessionCompleteFrames(compressionSession, kCMTimeInvalid);
        VTCompressionSessionInvalidate(compressionSession);
        CFRelease(compressionSession);
        compressionSession = NULL;
    }
    
    CMVideoCodecType codecType = kCMVideoCodecType_H264;
    if (_configuration.encoderType == LFVideoH264Encoder) {
        codecType = kCMVideoCodecType_H264;
    }else if (_configuration.encoderType == LFVideoH265Encoder) {
        codecType = kCMVideoCodecType_HEVC;
    }
    
    OSStatus status = VTCompressionSessionCreate(NULL, _configuration.videoSize.width, _configuration.videoSize.height, codecType, NULL, NULL, NULL, VideoCompressonOutputCallback, (__bridge void *)self, &compressionSession);
    if (status != noErr) {
        return;
    }

    _currentVideoBitRate = _configuration.videoBitRate;
    
    if ([self isSupportPropertyWithSession:compressionSession key:kVTCompressionPropertyKey_MaxKeyFrameInterval]) {
        VTSessionSetProperty(compressionSession,
                             kVTCompressionPropertyKey_MaxKeyFrameInterval,
                             (__bridge CFTypeRef)@(_configuration.videoMaxKeyframeInterval));
    }
    
    if ([self isSupportPropertyWithSession:compressionSession key:kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration]) {
        VTSessionSetProperty(compressionSession,
                             kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration,
                             (__bridge CFTypeRef)@(_configuration.videoMaxKeyframeInterval/_configuration.videoFrameRate));
    }
    
    if ([self isSupportPropertyWithSession:compressionSession key:kVTCompressionPropertyKey_ExpectedFrameRate]) {
        VTSessionSetProperty(compressionSession, kVTCompressionPropertyKey_ExpectedFrameRate, (__bridge CFTypeRef)@(_configuration.videoFrameRate));
    }
    
    if ([self isSupportPropertyWithSession:compressionSession key:kVTCompressionPropertyKey_AverageBitRate]) {
        VTSessionSetProperty(compressionSession, kVTCompressionPropertyKey_AverageBitRate, (__bridge CFTypeRef)@(_configuration.videoBitRate));
    }
    
    if ([self isSupportPropertyWithSession:compressionSession key:kVTCompressionPropertyKey_DataRateLimits]) {
        NSArray *limit = @[@(_configuration.videoBitRate * 1.5/8), @(1)];
        VTSessionSetProperty(compressionSession, kVTCompressionPropertyKey_DataRateLimits, (__bridge CFArrayRef)limit);
    }

    if ([self isSupportPropertyWithSession:compressionSession key:kVTCompressionPropertyKey_RealTime]) {
        VTSessionSetProperty(compressionSession, kVTCompressionPropertyKey_RealTime, kCFBooleanTrue);
    }
    
    if ([self isSupportPropertyWithSession:compressionSession key:kVTCompressionPropertyKey_AllowFrameReordering]) {
        VTSessionSetProperty(compressionSession, kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse);
    }

    if (_configuration.encoderType == LFVideoH264Encoder) {
        VTSessionSetProperty(compressionSession, kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_H264_Main_AutoLevel);
        VTSessionSetProperty(compressionSession, kVTCompressionPropertyKey_H264EntropyMode, kVTH264EntropyMode_CABAC);
    }else if (_configuration.encoderType == LFVideoH265Encoder) {
        VTSessionSetProperty(compressionSession, kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_HEVC_Main_AutoLevel);
    }
    
    VTCompressionSessionPrepareToEncodeFrames(compressionSession);
    inResetting = NO;
}

- (void)setVideoBitRate:(NSInteger)videoBitRate {
    if(_isBackGround) return;
    
    if ([self isSupportPropertyWithSession:compressionSession key:kVTCompressionPropertyKey_AverageBitRate]) {
        VTSessionSetProperty(compressionSession, kVTCompressionPropertyKey_AverageBitRate, (__bridge CFTypeRef)@(videoBitRate));
    }
    
    if ([self isSupportPropertyWithSession:compressionSession key:kVTCompressionPropertyKey_DataRateLimits]) {
        NSArray *limit = @[@(videoBitRate * 1.5/8), @(1)];
        VTSessionSetProperty(compressionSession, kVTCompressionPropertyKey_DataRateLimits, (__bridge CFArrayRef)limit);
    }
    _currentVideoBitRate = videoBitRate;
}

- (NSInteger)videoBitRate {
    return _currentVideoBitRate;
}

#pragma mark - LFVideoEncoder

- (void)encodeVideoData:(CVPixelBufferRef)pixelBuffer timeStamp:(uint64_t)timeStamp videoOrientation:(CGImagePropertyOrientation)videoOrientation {
    if(_isBackGround) return;
    frameCount++;
    if (!compressionSession) {
        return;
    }
    CMTime presentationTimeStamp = CMTimeMake(frameCount, (int32_t)_configuration.videoFrameRate);
    VTEncodeInfoFlags flags;
    CMTime duration = CMTimeMake(1, (int32_t)_configuration.videoFrameRate);
    NSDictionary *properties = nil;
    if (frameCount % (int32_t)_configuration.videoMaxKeyframeInterval == 0) {
        properties = @{(__bridge NSString *)kVTEncodeFrameOptionKey_ForceKeyFrame: @YES};
    }
    LFHardwareVideoExtInfo *videoExtInfo = [[LFHardwareVideoExtInfo alloc] init];
    videoExtInfo.timeStamp = timeStamp;
    videoExtInfo.videoOrientation = videoOrientation;
    videoExtInfo.frameNumber = _frameNumber++;
    
    OSStatus status = VTCompressionSessionEncodeFrame(compressionSession, pixelBuffer, presentationTimeStamp, duration, (__bridge CFDictionaryRef)properties, (__bridge_retained void *)videoExtInfo, &flags);
    if(status != noErr){
        NSLog(@"status != noErr, %d", status);
        [self resetCompressionSession];
    }
}

- (void)stopEncoder {
    _frameNumber = 0;
    VTCompressionSessionCompleteFrames(compressionSession, kCMTimeIndefinite);
}

- (void)setDelegate:(id<LFVideoEncodingDelegate>)delegate {
    _encoderDelegate = delegate;
}

#pragma mark - Notification
- (void)willEnterBackground:(NSNotification*)notification {
    _isBackGround = YES;
}

- (void)willEnterForeground:(NSNotification*)notification {
    [self resetCompressionSession];
    _isBackGround = NO;
}

- (CGFloat)getRotateByImageOrientation:(CGImagePropertyOrientation)orientation {
   CGFloat rotate = 0;
    switch (orientation) {
            // 竖屏时候
            // SDK内部会做图像大小自适配(不会变形) 所以上层只要控制横屏时候的影像旋转的问题
        case kCGImagePropertyOrientationUp:{
            rotate = 0;
            NSLog(@"---->>>>sampleBuffer: kCGImagePropertyOrientationUp");

        }
            break;
        case kCGImagePropertyOrientationDown:{
            rotate = 180;
            NSLog(@"---->>>>sampleBuffer: kCGImagePropertyOrientationDown");

            break;
        }
        case kCGImagePropertyOrientationLeft: {
            // 静音键那边向上 所需转90度
            NSLog(@"---->>>>sampleBuffer: kCGImagePropertyOrientationLeft");

            rotate = 90;
        }
            break;
        case kCGImagePropertyOrientationRight:{
            // 关机键那边向上 所需转270
            NSLog(@"---->>>>sampleBuffer: kCGImagePropertyOrientationRight");
            rotate = 270;
        }
            break;
        default:
            break;
    }
    return rotate;
}

#pragma mark - VideoCallBack
static void VideoCompressonOutputCallback(void *VTref, void *VTFrameRef, OSStatus status, VTEncodeInfoFlags infoFlags, CMSampleBufferRef sampleBuffer){
    if (!sampleBuffer) return;
    CFArrayRef array = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, true);
    if (!array) return;
    CFDictionaryRef dic = (CFDictionaryRef)CFArrayGetValueAtIndex(array, 0);
    if (!dic) return;

    BOOL keyframe = !CFDictionaryContainsKey(dic, kCMSampleAttachmentKey_NotSync);
    
    LFHardwareVideoExtInfo *videoExtInfo = ((__bridge_transfer LFHardwareVideoExtInfo *)VTFrameRef);
    
    uint64_t timeStamp = videoExtInfo.timeStamp;
    uint32_t videoOrientation = videoExtInfo.videoOrientation;
    uint32_t frameNumber = videoExtInfo.frameNumber;

    LFHardwareVideoEncoder *videoEncoder = (__bridge LFHardwareVideoEncoder *)VTref;
    if (status != noErr) {
        return;
    }

    [videoEncoder getRotateByImageOrientation:videoExtInfo.videoOrientation];
    
    if (keyframe && !videoEncoder->sps) {
        CMFormatDescriptionRef format = CMSampleBufferGetFormatDescription(sampleBuffer);

        if (videoEncoder.configuration.encoderType == LFVideoH264Encoder) {
            size_t sparameterSetSize, sparameterSetCount;
            const uint8_t *sparameterSet;
            OSStatus statusCode = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, 0, &sparameterSet, &sparameterSetSize, &sparameterSetCount, 0);
            if (statusCode == noErr) {
                size_t pparameterSetSize, pparameterSetCount;
                const uint8_t *pparameterSet;
                OSStatus statusCode = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, 1, &pparameterSet, &pparameterSetSize, &pparameterSetCount, 0);
                if (statusCode == noErr) {
                    videoEncoder->sps = [NSData dataWithBytes:sparameterSet length:sparameterSetSize];
                    videoEncoder->pps = [NSData dataWithBytes:pparameterSet length:pparameterSetSize];

                    if (videoEncoder->enabledWriteVideoFile) {
                        NSMutableData *data = [[NSMutableData alloc] init];
                        uint8_t header[] = {0x00, 0x00, 0x00, 0x01};
                        [data appendBytes:header length:4];
                        [data appendData:videoEncoder->sps];
                        [data appendBytes:header length:4];
                        [data appendData:videoEncoder->pps];
                        fwrite(data.bytes, 1, data.length, videoEncoder->fp);
                    }
                }// pps
            }// sps
        }
        else if (videoEncoder.configuration.encoderType == LFVideoH265Encoder) {
            const uint8_t *vps;
            size_t vpsSize;
            int NALUnitHeaderLengthOut;
            size_t parmCount;
            OSStatus statusCode = CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(format, 0, &vps, &vpsSize, &parmCount, &NALUnitHeaderLengthOut);
            if (statusCode == noErr) {
                const uint8_t *sps;
                size_t spsSize;
                statusCode = CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(format, 1, &sps, &spsSize, &parmCount, &NALUnitHeaderLengthOut);
                if (statusCode == noErr) {
                    const uint8_t *pps;
                    size_t ppsSize;
                    statusCode = CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(format, 2, &pps, &ppsSize, &parmCount, &NALUnitHeaderLengthOut);
                    if (statusCode == noErr) {
                        videoEncoder->vps = [NSData dataWithBytes:vps length:vpsSize];
                        videoEncoder->sps = [NSData dataWithBytes:sps length:spsSize];
                        videoEncoder->pps = [NSData dataWithBytes:pps length:ppsSize];
                        
                        if (videoEncoder->enabledWriteVideoFile) {
                            NSMutableData *data = [[NSMutableData alloc] init];
                            uint8_t header[] = {0x00, 0x00, 0x00, 0x01};
                            [data appendBytes:header length:4];
                            [data appendData:videoEncoder->vps];
                            [data appendBytes:header length:4];
                            [data appendData:videoEncoder->sps];
                            [data appendBytes:header length:4];
                            [data appendData:videoEncoder->pps];
                            fwrite(data.bytes, 1, data.length, videoEncoder->fp);
                        }
                    }// pps
                }// sps
            }// vps
        }// h265
    }

    CMBlockBufferRef dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
    size_t length, totalLength;
    char *dataPointer;
    OSStatus statusCodeRet = CMBlockBufferGetDataPointer(dataBuffer, 0, &length, &totalLength, &dataPointer);
    if (statusCodeRet == noErr) {
        size_t bufferOffset = 0;
        static const int AVCCHeaderLength = 4;
        while (bufferOffset < totalLength - AVCCHeaderLength) {
            // Read the NAL unit length
            uint32_t NALUnitLength = 0;
            memcpy(&NALUnitLength, dataPointer + bufferOffset, AVCCHeaderLength);

            NALUnitLength = CFSwapInt32BigToHost(NALUnitLength);

            LFVideoFrame *videoFrame = [LFVideoFrame new];
            NSData *rawVideoData = [[NSData alloc] initWithBytes:(dataPointer + bufferOffset + AVCCHeaderLength) length:NALUnitLength];
#if LFUseAnnexBStyle
            NSMutableData *frameData = [[NSMutableData alloc] init];
            uint8_t header[] = {0x00, 0x00, 0x00, 0x01};
            if (keyframe) {
                if (videoEncoder->vps) {
                    [frameData appendBytes:header length:4];
                    [frameData appendData:videoEncoder->vps];
                }
                if (videoEncoder->sps) {
                    [frameData appendBytes:header length:4];
                    [frameData appendData:videoEncoder->sps];
                }
                if (videoEncoder->pps) {
                    [frameData appendBytes:header length:4];
                    [frameData appendData:videoEncoder->pps];
                }
                
                uint8_t header[] = {0x00, 0x00, 0x00, 0x01};
                [frameData appendBytes:header length:4];
                [frameData appendData:rawVideoData];
            } else {
                uint8_t header[] = {0x00, 0x00, 0x01};
                [frameData appendBytes:header length:3];
                [frameData appendData:rawVideoData];
            }
            videoFrame.data = frameData;
#else
            videoFrame.data = rawVideoData;
#endif
            videoFrame.isKeyFrame = keyframe;
            videoFrame.vps = videoEncoder->vps;
            videoFrame.sps = videoEncoder->sps;
            videoFrame.pps = videoEncoder->pps;
            
            videoFrame.timestamp = timeStamp;
            videoFrame.frameNumber = frameNumber;
            videoFrame.videoOrientation = videoOrientation;
            
            if (videoEncoder.encoderDelegate && [videoEncoder.encoderDelegate respondsToSelector:@selector(videoEncoder:videoFrame:)]) {
                [videoEncoder.encoderDelegate videoEncoder:videoEncoder videoFrame:videoFrame];
            }

            if (videoEncoder->enabledWriteVideoFile) {
                NSMutableData *data = [[NSMutableData alloc] init];
                if (keyframe) {
                    uint8_t header[] = {0x00, 0x00, 0x00, 0x01};
                    [data appendBytes:header length:4];
                } else {
                    uint8_t header[] = {0x00, 0x00, 0x01};
                    [data appendBytes:header length:3];
                }
                [data appendData:videoFrame.data];

                fwrite(data.bytes, 1, data.length, videoEncoder->fp);
            }

            bufferOffset += AVCCHeaderLength + NALUnitLength;
        }
    }
}

#pragma mark - Debug

- (void)initForFilePath {
    NSString *path = [self GetFilePathByfileName:@"IOSCamDemo.h264"];
    if (_configuration.encoderType == LFVideoH265Encoder) {
        path = [self GetFilePathByfileName:@"IOSCamDemo.h265"];
    }
    NSLog(@"%@", path);
    self->fp = fopen([path cStringUsingEncoding:NSUTF8StringEncoding], "wb");
}

- (NSString *)GetFilePathByfileName:(NSString *)filename {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    NSString *writablePath = [documentsDirectory stringByAppendingPathComponent:filename];
    return writablePath;
}

@end
