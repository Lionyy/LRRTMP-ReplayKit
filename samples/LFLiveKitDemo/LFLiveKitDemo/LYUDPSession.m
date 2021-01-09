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

uint16_t const kBroadcastUDPPort = 7788;

@interface LYUDPSession()<GCDAsyncUdpSocketDelegate>

@property (strong, nonatomic) GCDAsyncUdpSocket * udpSocket;

@end

@implementation LYUDPSession

- (instancetype)init
{
    self = [super init];
    if (self) {
        [self setupUdpSocket];
    }
    return self;
}

- (void)setupUdpSocket
{
    NSError *error = nil;
    _udpSocket = [[GCDAsyncUdpSocket alloc] initWithDelegate:self delegateQueue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)];
    [_udpSocket setIPv4Enabled:YES];
    [_udpSocket setIPv6Enabled:YES];
    [_udpSocket bindToPort:kBroadcastUDPPort error:&error];

    if(error) {
        NSLog(@"绑定UDP端口[%@]失败: %@", @(kBroadcastUDPPort), error);
    }
}

- (void)sendBroadcast
{
    NSError *error = nil;
    [_udpSocket sendData:[@{@"msg":@"广播测试"} mj_JSONData] toHost:@"255.255.255.255" port:kBroadcastUDPPort withTimeout:-1 tag:1000];
    [_udpSocket enableBroadcast:YES error:&error];
    [_udpSocket beginReceiving:&error];
    
    if (error) {
        NSLog(@"广播发送失败: %@", error);
        if (error.code == GCDAsyncUdpSocketBadConfigError) {
            [LKAlert showAlertViewTitle:nil message:@"请开启本地网络权限" leftButtonTitle:@"取消" rightButtonTitle:@"去设置" leftButtonAction:^(UIAlertAction *action) {
                
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
    NSString *ip = [GCDAsyncUdpSocket hostFromAddress:address];
    uint16_t port = [GCDAsyncUdpSocket portFromAddress:address];

    NSLog(@"收到来自[%@:%@]的消息: %@", ip, @(port), dict.mj_JSONString);

    
//    dispatch_async(dispatch_get_main_queue(), ^{
//
//    });
    
}

@end
