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

/// 获取到服务器地址及端口信息
- (void)udpSession:(LYUDPSession *)udpSession didReceivedServerHost:(NSString *)host port:(uint16_t)port;
/// 广播失败回调
- (void)udpSession:(LYUDPSession *)udpSession didBroadcastError:(NSError *)error;

@end

@interface LYUDPSession : NSObject

@property (weak  , nonatomic) id <LYUDPSessionDelegate> delegate;
/// UDP广播获取到的服务器ip地址
@property (copy  , nonatomic, readonly) NSString * ipAddress;
/// UDP广播获取到的服务器端口号
@property (assign, nonatomic, readonly) uint16_t port;

/// UDP广播获取ip地址、端口号
- (void)sendBroadcast;

@end

NS_ASSUME_NONNULL_END
