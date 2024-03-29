//
//  LFLiveStreamInfo.h
//  LFLiveKit
//
//  Created by LaiFeng on 16/5/20.
//  Copyright © 2016年 LaiFeng All rights reserved.
//

#import <Foundation/Foundation.h>
#import "LFLiveAudioConfiguration.h"
#import "LFLiveVideoConfiguration.h"

/// 流状态
typedef NS_ENUM (NSUInteger, LFLiveState){
    /// 准备
    LFLiveReady = 0,
    /// 连接中
    LFLivePending = 1,
    /// 已连接
    LFLiveStart = 2,
    /// 已断开
    LFLiveStop = 3,
    /// 连接出错
    LFLiveError = 4,
    ///  正在刷新
    LFLiveRefresh = 5
};

typedef NS_ENUM (NSUInteger, LFLiveSocketErrorCode) {
    LFLiveSocketError_PreView = 201,              ///< 预览失败
    LFLiveSocketError_GetStreamInfo = 202,        ///< 获取流媒体信息失败
    LFLiveSocketError_ConnectSocket = 203,        ///< 连接socket失败
    LFLiveSocketError_Verification = 204,         ///< 验证服务器失败
    LFLiveSocketError_ReConnectTimeOut = 205,     ///< 重新连接服务器超时
    LFLiveSocketError_UDPMediaServer = 206        ///< UDP音视频接收服务错误

};

@interface LFLiveStreamInfo : NSObject

@property (nonatomic, copy) NSString *sourceId;
@property (nonatomic, copy) NSString *streamId;

#pragma mark -- FLV
@property (nonatomic, copy) NSString *host;
@property (nonatomic, assign) NSInteger port;
#pragma mark -- RTMP
@property (nonatomic, copy) NSString *url;          ///< 上传地址 (RTMP用就好了)
#pragma mark -- UDP Custom
@property (nonatomic, copy) NSString *udpHost;
@property (nonatomic, assign) NSInteger udpAudioPort;
@property (nonatomic, assign) NSInteger udpVideoPort;

///音频配置
@property (nonatomic, strong) LFLiveAudioConfiguration *audioConfiguration;
///视频配置
@property (nonatomic, strong) LFLiveVideoConfiguration *videoConfiguration;

@end
