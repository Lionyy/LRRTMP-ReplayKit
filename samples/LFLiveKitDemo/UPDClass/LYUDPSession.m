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

uint16_t const kBroadcastUDPPort = 7788;

@interface LYUDPSession()<GCDAsyncUdpSocketDelegate>

@property (strong, nonatomic) GCDAsyncUdpSocket * udpSocket;

@property (strong, nonatomic) YYReachability * reachability;

@property (copy  , nonatomic) NSString * ipAddress;
@property (assign, nonatomic) uint16_t port;

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
            [self sendBroadcast];
        }
    };
}

- (void)initUdpSocket
{
    _udpSocket = [[GCDAsyncUdpSocket alloc] initWithDelegate:self delegateQueue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)];
    [_udpSocket setIPv4Enabled:YES];
    [_udpSocket setIPv6Enabled:YES];
}

- (void)closeUdpSocket
{
    if (_udpSocket) {
        [_udpSocket close];
        _udpSocket = nil;
    }
}

- (void)sendBroadcast
{
    if (_reachability.status != YYReachabilityStatusWiFi) {
        [LKAlert alert:@"请检查手机是否连接到正确的Wifi？" okAction:nil];
        return;
    }
    
    NSError *error = nil;
    [_udpSocket bindToPort:kBroadcastUDPPort error:&error];
    if(error) {
        NSLog(@"绑定UDP端口[%@]失败: %@", @(kBroadcastUDPPort), error);
    }
    
    [_udpSocket sendData:[@{@"msg":@"广播测试"} mj_JSONData] toHost:@"255.255.255.255" port:kBroadcastUDPPort withTimeout:-1 tag:1000];
    [_udpSocket enableBroadcast:YES error:&error];
    [_udpSocket beginReceiving:&error];
    
    if (error) {
        NSLog(@"广播发送失败: %@", error);
        if (error.code == GCDAsyncUdpSocketBadConfigError) {
            
            if (_delegate && [_delegate respondsToSelector:@selector(udpSession:didBroadcastError:)]) {
                [_delegate udpSession:self didBroadcastError:error];
            }
            
            [LKAlert showAlertViewTitle:nil message:@"要开启本地网络权限后，才能投屏，是否去开启？" leftButtonTitle:@"取消" rightButtonTitle:@"去设置" leftButtonAction:^(UIAlertAction *action) {
                
            } rightButtonAction:^(UIAlertAction *action) {
                NSURL *url = [NSURL URLWithString:UIApplicationOpenSettingsURLString];
                if (url  && [[UIApplication sharedApplication] canOpenURL:url]) {
                    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
                }
            }];
        }
    }
}

#pragma mark - GCDAsyncUdpSocketDelegate

- (void)udpSocket:(GCDAsyncUdpSocket *)sock didNotSendDataWithTag:(long)tag dueToError:(NSError * _Nullable)error
{
    NSLog(@"didNotSendDataWithTag error: %@", error);
}

- (void)udpSocketDidClose:(GCDAsyncUdpSocket *)sock withError:(NSError  * _Nullable)error
{
    
}

- (void)udpSocket:(GCDAsyncUdpSocket *)sock didConnectToAddress:(NSData *)address
{
    
}

- (void)udpSocket:(GCDAsyncUdpSocket *)sock didReceiveData:(NSData *)data
                                             fromAddress:(NSData *)address
                                       withFilterContext:(nullable id)filterContext
{
    NSDictionary *dict = [data mj_JSONObject];
    self.ipAddress = [GCDAsyncUdpSocket hostFromAddress:address];
    self.port = [GCDAsyncUdpSocket portFromAddress:address];

    NSLog(@"收到来自[%@:%@]的消息: %@", self.ipAddress, @(self.port), dict.mj_JSONString);

    dispatch_async(dispatch_get_main_queue(), ^{
        if (_delegate && [_delegate respondsToSelector:@selector(udpSession:didReceivedServerHost:port:)]) {
            [_delegate udpSession:self didReceivedServerHost:self.ipAddress port:self.port];
        }
    });
    
}

@end
