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
#import <arpa/inet.h>

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
    
    ly_search_t search;
    memset(&search, 0, sizeof(ly_search_t));
    search.magic = LY_SEARCH_CMD;
    
    NSData *searchData = [NSData dataWithBytes:&search length:sizeof(ly_search_t)];
    
    [_udpSocket sendData:searchData toHost:kBroadcastUDPIP port:kBroadcastUDPPort withTimeout:-1 tag:1000];
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
    if (data.length >= sizeof(ly_search_response_t)) {
        ly_search_response_t searchRespond;
        memcmp(data.bytes, &searchRespond, sizeof(ly_search_response_t));
        _search_response = &searchRespond;
        
        if (searchRespond.magic == LY_SEARCH_CMD) {
            // 广播搜索投屏服务的IP及端口响应
            // TODO: 解析地址及端口逻辑
            uint32_t ip = searchRespond.addr;
            struct in_addr addr = *(struct in_addr *)&ip;
            NSString *ipString = [NSString stringWithFormat: @"%s",inet_ntoa(addr)];
            
            self.ipAddress = ipString;// [GCDAsyncUdpSocket hostFromAddress:address];
            self.port = searchRespond.port;

            NSLog(@"收到来自[%@:%@]广播搜索投屏服务的IP及端口响应", self.ipAddress, @(self.port));

            dispatch_async(dispatch_get_main_queue(), ^{
                if (_delegate && [_delegate respondsToSelector:@selector(udpSession:didReceivedServerHost:port:)]) {
                    [_delegate udpSession:self didReceivedServerHost:self.ipAddress port:self.port];
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
            
            uint32_t ip = request_port.addr;
            struct in_addr addr = *(struct in_addr *)&ip;
            NSString *ipString = [NSString stringWithFormat: @"%s",inet_ntoa(addr)];
            self.mediaIpAddress = ipString;
            self.videoPort = request_port.video_port;
            self.audioPort = request_port.audio_port;

            NSLog(@"收到来自[%@:%@:%@]接音视频数据的IP及端口响应", self.mediaIpAddress, @(self.videoPort), @(self.audioPort));
            // TODO: 解析地址及端口逻辑
            dispatch_async(dispatch_get_main_queue(), ^{

            });
        }
    }
}

@end
