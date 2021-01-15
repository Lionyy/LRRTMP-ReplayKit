//
//  ZFUploadTool.m
//  Recoder
//
//  Created by 张帆 on 2018/12/6.
//  Copyright © 2018 admin. All rights reserved.
//

#import "ZFUploadTool.h"
#import "LYUtils.h"
#import <LFLiveKit.h>
#import <ReplayKit/ReplayKit.h>

@interface ZFUploadTool () <LFLiveSessionDelegate>

@property (nonatomic, strong) LFLiveDebug *debugInfo;
@property (nonatomic, strong) LFLiveSession *session;
@property (nonatomic, assign) BOOL mic;
@property (nonatomic, assign) int frameQuality;
@property (nonatomic, copy) NSString *url;

@end

@implementation ZFUploadTool

+ (instancetype)shareTool {
    static dispatch_once_t onceToken;
    static ZFUploadTool *tool = nil;
    dispatch_once(&onceToken, ^{
        tool = [[ZFUploadTool alloc] init];
    });
    return tool;
}

- (void)prepareToStart:(NSDictionary *)dict {
    _url = dict[@"endpointURL"];
    _mic = [dict[@"mic"] boolValue];
    _mic = YES;
    _frameQuality = [dict[@"frameQuality"] intValue]; // 0 高 1中 2低
    if (!_url) {
        _url = @"rtmp://192.168.44.90/live/123";
    }
    [self lf];
}
- (void)lf {
    LFLiveStreamInfo *stream = [LFLiveStreamInfo new];
    stream.url = _url;

    [self.session startLive:stream];
}

#pragma mark -- Getter Setter
- (LFLiveSession *)session {
    if (_session == nil) {
        
        LFLiveAudioConfiguration *audioConfiguration = [LFLiveAudioConfiguration defaultConfigurationForQuality:LFLiveAudioQuality_High];
        audioConfiguration.numberOfChannels = 1;
        LFLiveVideoConfiguration *videoConfiguration;
       
        videoConfiguration = [LFLiveVideoConfiguration defaultConfigurationForQuality:LFLiveVideoQuality_High4];
        videoConfiguration.videoSize = CGSizeMake((NSInteger)(UIScreen.mainScreen.bounds.size.width/UIScreen.mainScreen.bounds.size.height * 1920), 1920);
        videoConfiguration.encoderType = LFVideoH265Encoder;
        
        _session = [[LFLiveSession alloc] initWithAudioConfiguration:audioConfiguration videoConfiguration:videoConfiguration captureType:_mic? LFLiveInputMaskAll:LFLiveInputMaskVideo];
        
        _session.delegate = self;
        _session.showDebugInfo = YES;
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(statusBarChanged:)
                                                     name:UIApplicationWillChangeStatusBarOrientationNotification
                                                   object:nil];
    }
    return _session;
}

- (void)statusBarChanged:(NSNotification *)notification
{
    UIInterfaceOrientation orientation = (UIInterfaceOrientation)[[notification.userInfo objectForKey:UIApplicationStatusBarOrientationUserInfoKey] integerValue];
    NSLog(@"---->>>>notification.userInfo: %@", notification.userInfo);

    if (orientation == UIInterfaceOrientationLandscapeLeft) {
        NSLog(@"---->>>>statusBarChanged: UIInterfaceOrientationLandscapeLeft");
        
    } else if (orientation == UIInterfaceOrientationLandscapeRight) {
        NSLog(@"---->>>>statusBarChanged: UIInterfaceOrientationLandscapeRight");

    } else if (orientation == UIInterfaceOrientationPortrait) {
        NSLog(@"---->>>>statusBarChanged: UIInterfaceOrientationPortrait");

    } else if (orientation == UIInterfaceOrientationPortraitUpsideDown) {
        NSLog(@"---->>>>statusBarChanged: UIInterfaceOrientationPortrait");

    }
}

-(void)stop {
    [self.session stopLive];
}


- (void)sendAudioBuffer:(CMSampleBufferRef)sampleBuffer {
    if (_mic) {
        [self.session pushAudioBuffer:sampleBuffer];
    }
}

- (void)sendVideoBuffer:(CMSampleBufferRef)sampleBuffer {
    [self.session pushVideoBuffer:sampleBuffer videoOrientation:[self getSampleOrientationByBuffer:sampleBuffer]];
}

- (CGImagePropertyOrientation)getSampleOrientationByBuffer:(CMSampleBufferRef)sampleBuffer {
    CGImagePropertyOrientation orientation = kCGImagePropertyOrientationUp;
    if (@available(iOS 11.1, *)) {
        /*
         1.1以上支持自动旋转
         IOS 11.0系统 编译RPVideoSampleOrientationKey会bad_address
         Replaykit bug：api说ios 11 支持RPVideoSampleOrientationKey 但是 却存在bad_address的情况 代码编译执行会报错bad_address 即使上面@available(iOS 11.1, *)也无效
         解决方案：Link Binary With Libraries  -->Replaykit  Request-->Option
        */
        CFStringRef RPVideoSampleOrientationKeyRef = (__bridge CFStringRef)RPVideoSampleOrientationKey;
        NSNumber *orientationNum = (NSNumber *)CMGetAttachment(sampleBuffer, RPVideoSampleOrientationKeyRef,NULL);
        orientation = (CGImagePropertyOrientation)orientationNum.integerValue;
    }
    return orientation;
}

#pragma mark -- LFStreamingSessionDelegate
/** live status changed will callback */
- (void)liveSession:(nullable LFLiveSession *)session liveStateDidChange:(LFLiveState)state {
    NSLog(@"liveStateDidChange: %ld", state);
    switch (state) {
        case LFLiveReady:
            NSLog(@"未连接");
            break;
        case LFLivePending:
            NSLog(@"连接中");
            break;
        case LFLiveStart:
            NSLog(@"已连接");
            break;
        case LFLiveError:
            NSLog(@"连接错误");
            break;
        case LFLiveStop:
            NSLog(@"未连接");
            break;
        default:
            break;
    }
}

/** live debug info callback */
- (void)liveSession:(nullable LFLiveSession *)session debugInfo:(nullable LFLiveDebug *)debugInfo {
    NSString *speed = [LYUtils formatedSpeed:debugInfo.currentBandwidth elapsedMilli:debugInfo.elapsedMilli];
    NSLog(@"speed:%@", speed);
    
}
/** callback socket errorcode */
- (void)liveSession:(nullable LFLiveSession *)session errorCode:(LFLiveSocketErrorCode)errorCode {
    NSLog(@"errorCode: %lu", (unsigned long)errorCode);
}



@end
