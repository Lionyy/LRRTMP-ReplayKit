//
//  LYUDPSession.m
//  Recoder
//
//  Created by RoyLei on 1/8/21.
//  Copyright © 2021 admin. All rights reserved.
//

#import "LYUDPSession.h"
#import <GCDAsyncUdpSocket.h>
#import "MJExtension.h"
#import "LKAlert.h"
#import "YYReachability.h"
#import "LYMacro.h"
#import "req_proto.h"
#import "LYUtils.h"

NSString * const kBroadcastUDPIP = @"255.255.255.255";
uint16_t const kBroadcastUDPPort = 20603;

@interface LYUDPSession()<GCDAsyncUdpSocketDelegate>
{
    ly_search_response_t *_search_response;
    ly_request_port_response_t *_request_port;
}
@property (strong, nonatomic) GCDAsyncUdpSocket * udpSocket;

@property (strong, nonatomic) YYReachability * reachability;
/// 请求到的接音视频数据的IP及端口
@property (copy  , nonatomic) NSString * ipAddress;
@property (assign, nonatomic) uint16_t port;
/// 上传音视频ip及端口
@property (copy  , nonatomic) NSString * mediaIpAddress;
@property (assign, nonatomic) uint16_t videoPort;
@property (assign, nonatomic) uint16_t audioPort;

@end

@implementation LYUDPSession

- (instancetype)init
{
    self = [super init];
    if (self) {
        [self initReachability];
        [self initUdpSocket];
    }
    return self;
}

- (void)initReachability
{
    _reachability = [YYReachability reachability];
    @weakify(self)
    _reachability.notifyBlock = ^(YYReachability * _Nonnull reachability) {
        @strongify(self)
        if (reachability.status == YYReachabilityStatusWiFi) {
            [self searchServerAddress];
        }
    };
}

- (void)initUdpSocket
{
    _udpSocket = [[GCDAsyncUdpSocket alloc] initWithDelegate:self delegateQueue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)];
    [_udpSocket setIPv4Enabled:YES];
    [_udpSocket setIPv6Enabled:YES];
    
    NSError *error = nil;
    [_udpSocket enableBroadcast:YES error:&error];
    
    if(error) {
        NSLog(@"enableBroadcast 失败: %@", error);
    }
}

#pragma mark - UDP Socket

- (void)closeUdpSocket
{
    if (_udpSocket) {
        [_udpSocket close];
        _udpSocket = nil;
    }
}

#pragma mark - UDP Request

- (void)searchServerAddress
{
    NSError *error = nil;
    [_udpSocket bindToPort:kBroadcastUDPPort error:&error];
    if(error) {
        NSLog(@"绑定UDP端口[%@]失败: %@", @(kBroadcastUDPPort), error);
    }
    
    ly_search_t search;
    memset(&search, 0, sizeof(ly_search_t));
    search.magic = LY_SEARCH_CMD;
    
    NSData *searchData = [NSData dataWithBytes:&search length:sizeof(ly_search_t)];
    
    [_udpSocket sendData:searchData toHost:kBroadcastUDPIP port:kBroadcastUDPPort withTimeout:-1 tag:1000];
    [_udpSocket beginReceiving:&error];

    if (error) {
        NSLog(@"广播搜索投屏服务的IP及端口发送失败: %@", error);
        
        [self handleRequestError:error];

        if (_delegate && [_delegate respondsToSelector:@selector(udpSession:didRequestError:)]) {
            [_delegate udpSession:self didRequestError:error];
        }
        
        // 间隔3秒再次请求
        @weakify(self)
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            @strongify(self)
            [self searchServerAddress];
        });
    }
}

- (void)requestMediaServerIPAndPort
{
    if (!self.ipAddress || self.port == 0) {
        return;
    }

    NSError *error = nil;

    ly_request_port_t reuqest;
    memset(&reuqest, 0, sizeof(ly_request_port_t));
    reuqest.magic = LY_REQ_PORT_CMD;
    
    NSData *reuqestData = [NSData dataWithBytes:&reuqest length:sizeof(ly_search_t)];
    
    [_udpSocket sendData:reuqestData toHost:self.ipAddress port:self.port withTimeout:-1 tag:1000];
    [_udpSocket enableBroadcast:NO error:&error];
    [_udpSocket beginReceiving:&error];
    
    if (error) {
        NSLog(@"请求接音视频数据的IP及端口发送失败: %@", error);

        [self handleRequestError:error];
        
        if (_delegate && [_delegate respondsToSelector:@selector(udpSession:didRequestError:)]) {
            [_delegate udpSession:self didRequestError:error];
        }
        
        // 间隔3秒再次请求
        @weakify(self)
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            @strongify(self)
            [self requestMediaServerIPAndPort];
        });
    }
}

#pragma mark - Error Alert

- (void)checkConnectedWiFi
{
    if (_reachability.status != YYReachabilityStatusWiFi) {
        [LKAlert alert:@"请检查手机是否连接到正确的Wifi？" okAction:nil];
        return;
    }
}

- (void)handleRequestError:(NSError *)error
{
    if (error.code == GCDAsyncUdpSocketBadConfigError) {
        [self showLocalNetworkPermissionAlert];
    }
}

- (void)showLocalNetworkPermissionAlert
{
    if ([LYUtils isFirstLaunchApp]) {
        return;
    }
    
    static BOOL alertOnce = NO;
    if (alertOnce) {
        return;
    }
    alertOnce = YES;
    
    [LKAlert showAlertViewTitle:nil message:@"要开启本地网络权限后，才能投屏，是否去开启？" leftButtonTitle:@"取消" rightButtonTitle:@"去设置" leftButtonAction:^(UIAlertAction *action) {
    } rightButtonAction:^(UIAlertAction *action) {
        NSURL *url = [NSURL URLWithString:UIApplicationOpenSettingsURLString];
        if (url  && [[UIApplication sharedApplication] canOpenURL:url]) {
            [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        }
    }];
}

#pragma mark - GCDAsyncUdpSocketDelegate

- (void)udpSocket:(GCDAsyncUdpSocket *)sock didNotSendDataWithTag:(long)tag dueToError:(NSError * _Nullable)error
{
    NSLog(@"didNotSendDataWithTag error: %@", error);
}

- (void)udpSocketDidClose:(GCDAsyncUdpSocket *)sock withError:(NSError * _Nullable)error
{
    
}

- (void)udpSocket:(GCDAsyncUdpSocket *)sock didConnectToAddress:(NSData *)address
{
    
}

- (void)udpSocket:(GCDAsyncUdpSocket *)sock didReceiveData:(NSData *)data
                                               fromAddress:(NSData *)address
                                         withFilterContext:(nullable id)filterContext
{
    if (data.length >= sizeof(ly_search_response_t)) {
        ly_search_response_t searchRespond;
        memcmp(data.bytes, &searchRespond, sizeof(ly_search_response_t));
        _search_response = &searchRespond;
        
        if (searchRespond.magic == LY_SEARCH_CMD) {
            // 广播搜索投屏服务的IP及端口响应
            self.ipAddress = [LYUtils ipStringWithAddress:searchRespond.addr];// [GCDAsyncUdpSocket hostFromAddress:address];
            self.port = searchRespond.port;

            NSLog(@"收到来自[%@:%@]广播搜索投屏服务的IP及端口响应", self.ipAddress, @(self.port));
            @weakify(self)
            dispatch_async(dispatch_get_main_queue(), ^{
                @strongify(self)
                if (self.delegate && [self.delegate respondsToSelector:@selector(udpSession:didReceivedServerHost:port:)]) {
                    [self.delegate udpSession:self didReceivedServerHost:self.ipAddress port:self.port];
                }
            });
        }
    }
    
    if (data.length >= sizeof(ly_request_port_response_t)) {
        ly_request_port_response_t request_port;
        memcmp(data.bytes, &request_port, sizeof(ly_request_port_response_t));
        _request_port = &request_port;
        
        if (request_port.magic == LY_REQ_PORT_CMD) {
            // 请求接音视频数据的IP及端口响应
            self.mediaIpAddress = [LYUtils ipStringWithAddress:request_port.addr];
            self.audioPort = request_port.audio_port;
            self.videoPort = request_port.video_port;

            NSLog(@"收到来自[%@:%@:%@]接音视频数据的IP及端口响应", self.mediaIpAddress, @(self.videoPort), @(self.audioPort));
            @weakify(self)
            dispatch_async(dispatch_get_main_queue(), ^{
                @strongify(self)
                if (self.delegate && [self.delegate respondsToSelector:@selector(udpSession:didReceivedUDPMediaHost:audioPort:videoPort:)]) {
                    [self.delegate udpSession:self didReceivedUDPMediaHost:self.mediaIpAddress audioPort:self.audioPort videoPort:self.videoPort];
                }
            });
        }
    }
}

@end
