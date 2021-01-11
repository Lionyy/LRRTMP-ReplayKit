//
//  LYUDPSession.h
//  Recoder
//
//  Created by RoyLei on 1/8/21.
//  Copyright © 2021 admin. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class LYUDPSession;
@protocol LYUDPSessionDelegate <NSObject>
/// UDP广播获取命令服务器ip地址、端口号失败回调
- (void)udpSession:(LYUDPSession *)udpSession didSearchServerError:(NSError *)error;
/// 请求音视频服务器UPD推流地址及端口号失败回调
- (void)udpSession:(LYUDPSession *)udpSession didRequestMediaServerIPAndPortError:(NSError *)error;
/// 获取到服务器地址及端口信息
- (void)udpSession:(LYUDPSession *)udpSession didReceivedServerHost:(NSString *)host port:(uint16_t)port;
/// 获取到音视频UDP推流服务器地址及端口信息
- (void)udpSession:(LYUDPSession *)udpSession didReceivedUDPMediaHost:(NSString *)host audioPort:(uint16_t)audioPort videoPort:(uint16_t)videoPort;

@end

@interface LYUDPSession : NSObject

@property (weak  , nonatomic) id <LYUDPSessionDelegate> delegate;
/// UDP广播获取到的服务器ip地址
@property (copy  , nonatomic, readonly) NSString * ipAddress;
/// UDP广播获取到的服务器端口号
@property (assign, nonatomic, readonly) uint16_t port;
/// 音视频UPD推流ip地址
@property (copy  , nonatomic, readonly) NSString * mediaIpAddress;
/// 音频UPD推流端口号
@property (assign, nonatomic, readonly) uint16_t audioPort;
/// 视频UPD推流端口号
@property (assign, nonatomic, readonly) uint16_t videoPort;

/// UDP广播获取命令服务器ip地址、端口号
- (void)searchServerAddress;

/// 请求音视频服务器UPD推流地址及端口号
- (void)requestMediaServerIPAndPort;

/// 检测WiFi连接
- (void)checkConnectedWiFi;

@end

NS_ASSUME_NONNULL_END
