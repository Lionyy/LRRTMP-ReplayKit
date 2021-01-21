//
//  ViewController.m
//  LFLiveKitDemo
//
//  Created by admin on 16/8/30.
//  Copyright © 2016年 admin. All rights reserved.
//

#import "ViewController.h"
#import <ReplayKit/ReplayKit.h>
#import <LFLiveKit.h>
#import "AppDelegate.h"
#import "LYUDPSession.h"
#import "LYUtils.h"

@interface ViewController () <LFLiveSessionDelegate, RPBroadcastControllerDelegate, RPBroadcastActivityViewControllerDelegate, LYUDPSessionDelegate>
@property (nonatomic, strong) LFLiveSession *session;
@property (nonatomic, strong) LYUDPSession * udpSession;
@property (nonatomic, strong) UIView *testView;
@property (nonatomic, strong) RPBroadcastController *broadcastController;
@property (nonatomic, strong) UIView *pickerView;

@property (nonatomic) BOOL needQueryMediaServer;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [[[NSURLSession sharedSession] dataTaskWithURL:[NSURL URLWithString:@"https://www.baidu.com"] completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        // 请求网络权限
    }] resume];
    
    UIView *testView = ({
        UIView *view = [[UIView alloc] initWithFrame:CGRectMake(100, 100, 100, 100)];
        [view setBackgroundColor:[UIColor purpleColor]];
        view;
    });
    [self.view addSubview:testView];
    
    {
        /*
         这个动画会让直播一直有视频帧
         动画类型不限，只要屏幕是变化的就会有视频帧
         */
        [testView.layer removeAllAnimations];
        CABasicAnimation *rA = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
        rA.duration = 3.0;
        rA.toValue = [NSNumber numberWithFloat:M_PI * 2];
        rA.repeatCount = MAXFLOAT;
        rA.removedOnCompletion = NO;
        [testView.layer addAnimation:rA forKey:@""];
    }
    
    UIButton *perpareButton = ({
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        [button setFrame:CGRectMake(50, 300, 100, 50)];
        [button setTitle:@"Perpare" forState:UIControlStateNormal];
        // 连接直播端口 < 准备直播
        [button addTarget:self action:@selector(perpare) forControlEvents:UIControlEventTouchUpInside];
        button;
    });
    
    UIButton *statrButton1 = ({
        // 第一种直播方式
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        [button setFrame:CGRectMake(130, 300, 100, 50)];
        [button setTitle:@"Start" forState:UIControlStateNormal];
        // 点击开始推流
        [button addTarget:self action:@selector(statrButtonClick:) forControlEvents:UIControlEventTouchUpInside];
        button;
    });
    
    UIButton *statrButton2 = ({
        // 第二种直播方式 调用Extension
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        [button setFrame:CGRectMake(300, 300, 150, 50)];
        [button setTitle:@"Extension" forState:UIControlStateNormal];
        // 点击开始推流
        [button addTarget:self action:@selector(startLive) forControlEvents:UIControlEventTouchUpInside];
        button;
    });
    
    _pickerView = ({
        UIView *view = [[UIView alloc] initWithFrame:CGRectMake(500, 300, 70, 70)];
        view;
    });
    [self.view addSubview:_pickerView];
    
    if (@available(iOS 12.0, *)) {
        RPSystemBroadcastPickerView *broadcastPicker = [[RPSystemBroadcastPickerView alloc] initWithFrame:_pickerView.bounds];
        broadcastPicker.preferredExtension = @"com.roy.recoderDemo.Recoder";
        [_pickerView addSubview:broadcastPicker];
    }

    [self.view addSubview:perpareButton];
    [self.view addSubview:statrButton1];
    [self.view addSubview:statrButton2];
    
    CGFloat width = UIScreen.mainScreen.bounds.size.width;
    CGFloat height = UIScreen.mainScreen.bounds.size.height;
    if(width < height) {
        width = ceilf(width / height * 1920);
        height = 1920;
    }else {
        height = ceilf(height / width * 1920);
        width = 1920;
    }

    LFLiveAudioConfiguration *audioConfiguration = [LFLiveAudioConfiguration defaultConfigurationForQuality:LFLiveAudioQuality_High];
    audioConfiguration.numberOfChannels = 1;
    LFLiveVideoConfiguration *videoConfiguration = [LFLiveVideoConfiguration defaultConfigurationForQuality:LFLiveVideoQuality_High4
                                                                                     outputImageOrientation:UIInterfaceOrientationLandscapeRight];
    videoConfiguration.videoSize = CGSizeMake(width, height);
    videoConfiguration.encoderType = LFVideoH265Encoder;
    
    _udpSession = [[LYUDPSession alloc] initWithAudioConfiguration:audioConfiguration videoConfiguration:videoConfiguration];
    _udpSession.delegate = self;
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
//    [_udpSession searchServerAddress];
}

- (CGImagePropertyOrientation)getSampleOrientationByBuffer:(CMSampleBufferRef)sampleBuffer {
    CGImagePropertyOrientation orientation = kCGImagePropertyOrientationUp;
    if (@available(iOS 11.1, *)) {
        /*
         11.1以上支持自动旋转
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

#pragma mark -- Getter Setter
- (LFLiveSession *)session {
    if (_session == nil) {
        _session = [[LFLiveSession alloc] initWithAudioConfiguration:_udpSession.audioConfiguration
                                                  videoConfiguration:_udpSession.videoConfiguration
                                                         captureType:LFLiveInputMaskAll];
        
        _session.delegate = self;
        _session.showDebugInfo = YES;
        
    }
    return _session;
}

- (void)liveSession:(nullable LFLiveSession *)session liveStateDidChange:(LFLiveState)state {
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

- (void)liveSession:(nullable LFLiveSession *)session debugInfo:(nullable LFLiveDebug *)debugInfo {
    NSString *speed = [LYUtils formatedSpeed:debugInfo.currentBandwidth elapsedMilli:debugInfo.elapsedMilli];
    NSLog(@"speed:%@", speed);
}

- (void)liveSession:(nullable LFLiveSession *)session errorCode:(LFLiveSocketErrorCode)errorCode {
    NSLog(@"errorCode: %lu", (unsigned long)errorCode);
}


- (void)perpare {
        
//    [_udpSession requestMediaServerIPAndPort];

    LFLiveStreamInfo *stream = [LFLiveStreamInfo new];
    // 直播推流地址
    stream.url = LY_TEST_RTMP_URL;
    [self.session startLive:stream];
    [[RPScreenRecorder sharedRecorder] setMicrophoneEnabled:YES];
}

- (void)statrButtonClick:(UIButton *)sender {
    if ([[RPScreenRecorder sharedRecorder] isRecording]) {
        NSLog(@"Recording, stop record");
        [self.session stopLive];
        [[RPScreenRecorder sharedRecorder] stopCaptureWithHandler:^(NSError * _Nullable error) {
            if (error) {
                NSLog(@"stopCaptureWithHandler:%@", error.localizedDescription);
            } else {
                NSLog(@"CaptureWithHandlerStoped");
            }
        }];
    } else {
        [[RPScreenRecorder sharedRecorder] startCaptureWithHandler:^(CMSampleBufferRef  _Nonnull sampleBuffer, RPSampleBufferType bufferType, NSError * _Nullable error) {
//                NSLog(@"bufferTyped:%ld", (long)bufferType);
            switch (bufferType) {
                case RPSampleBufferTypeVideo:
                    [self.session pushVideoBuffer:sampleBuffer videoOrientation:[self getSampleOrientationByBuffer:sampleBuffer]];
                    break;
                case RPSampleBufferTypeAudioMic:
                    [self.session pushAudioBuffer:sampleBuffer];
                    break;
                    
                default:
                    break;
            }
            if (error) {
                NSLog(@"startCaptureWithHandler:error:%@", error.localizedDescription);
            }
        } completionHandler:^(NSError * _Nullable error) {
            if (error) {
                NSLog(@"completionHandler:error:%@", error.localizedDescription);
            }
        }];
    }
}

#pragma mark -
#pragma mark Extension

- (void)startLive {
// 如果需要mic，需要打开x此项
    [[RPScreenRecorder sharedRecorder] setMicrophoneEnabled:YES];
    
    if (![RPScreenRecorder sharedRecorder].isRecording) {
        [RPBroadcastActivityViewController loadBroadcastActivityViewControllerWithHandler:^(RPBroadcastActivityViewController * _Nullable broadcastActivityViewController, NSError * _Nullable error) {
            if (error) {
                NSLog(@"RPBroadcast err %@", [error localizedDescription]);
            }
            broadcastActivityViewController.delegate = self;
            broadcastActivityViewController.modalPresentationStyle = UIModalPresentationPopover;
            if(UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
                broadcastActivityViewController.popoverPresentationController.sourceRect = self.testView.frame;
                broadcastActivityViewController.popoverPresentationController.sourceView = self.testView;
            }
            [self presentViewController:broadcastActivityViewController animated:YES completion:nil];
        }];
    } else {
        
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Stop Live?" message:@"" preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *ok = [UIAlertAction actionWithTitle:NSLocalizedString(@"Yes",nil) style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
            [self stopLive];
        }];
        UIAlertAction *cancle = [UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel",nil) style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
            
        }];
        [alert addAction:ok];
        [alert addAction:cancle];
        [self presentViewController:alert animated:YES completion:nil];
        
    }
}
- (void)stopLive {
    [self.broadcastController finishBroadcastWithHandler:^(NSError * _Nullable error) {
        if (error) {
            NSLog(@"finishBroadcastWithHandler:%@", error.localizedDescription);
        }
        
    }];
}

#pragma mark - Broadcasting
- (void)broadcastActivityViewController:(RPBroadcastActivityViewController *) broadcastActivityViewController
       didFinishWithBroadcastController:(RPBroadcastController *)broadcastController
                                  error:(NSError *)error {
    
    [broadcastActivityViewController dismissViewControllerAnimated:YES
                                                        completion:nil];
    NSLog(@"BundleID %@", broadcastController.broadcastExtensionBundleID);
    self.broadcastController = broadcastController;
    self.broadcastController.delegate = self;
    if (error) {
        NSLog(@"BAC: %@ didFinishWBC: %@, err: %@",
              broadcastActivityViewController,
              broadcastController,
              error);
        return;
    }

    [broadcastController startBroadcastWithHandler:^(NSError * _Nullable error) {
        if (!error) {
            NSLog(@"-----start success----");
            // 这里可以添加camerPreview
        } else {
            NSLog(@"startBroadcast:%@",error.localizedDescription);
        }
    }];
    
}


// Watch for service info from broadcast service
- (void)broadcastController:(RPBroadcastController *)broadcastController
       didUpdateServiceInfo:(NSDictionary <NSString *, NSObject <NSCoding> *> *)serviceInfo {
    NSLog(@"didUpdateServiceInfo: %@", serviceInfo);
    
    
}

// Broadcast service encountered an error
- (void)broadcastController:(RPBroadcastController *)broadcastController
         didFinishWithError:(NSError *)error {
    NSLog(@"didFinishWithError: %@", error);
}

- (void)broadcastController:(RPBroadcastController *)broadcastController didUpdateBroadcastURL:(NSURL *)broadcastURL {
    NSLog(@"---didUpdateBroadcastURL: %@",broadcastURL);
}

#pragma mark - LYUDPSessionDelegate

/// UDP广播获取命令服务器ip地址、端口号失败回调
- (void)udpSession:(LYUDPSession *)udpSession didSearchServerError:(NSError *)error {
    
}

/// 请求音视频服务器UPD推流地址及端口号失败回调
- (void)udpSession:(LYUDPSession *)udpSession didRequestMediaServerIPAndPortError:(NSError *)error {
    
}

/// 获取到服务器地址及端口信息
- (void)udpSession:(LYUDPSession *)udpSession didReceivedServerHost:(NSString *)host port:(uint16_t)port {
    
}

/// 获取到音视频UDP推流服务器地址及端口信息
- (void)udpSession:(LYUDPSession *)udpSession didReceivedUDPMediaHost:(NSString *)host audioPort:(uint16_t)audioPort videoPort:(uint16_t)videoPort {
    
}


@end
