//
//  LYStreamingUDPSocket.m
//  LFLiveKit-ReplayKit
//
//  Created by RoyLei on 1/8/21.
//

#import "LYStreamingUDPSocket.h"
#import <GCDAsyncUdpSocket.h>
#import "media_proto.h"

uint16_t const kLocalUDPPort = 20605;
static const NSInteger RetryTimesBreaken = 5;  ///<  重连1分钟  3秒一次 一共20次
static const NSInteger RetryTimesMargin = 3;

@interface LYStreamingUDPSocket ()<LFStreamingBufferDelegate, GCDAsyncUdpSocketDelegate>

@property (nonatomic, weak) id<LFStreamSocketDelegate> delegate;
@property (nonatomic, strong) GCDAsyncUdpSocket *udpSocket;
@property (nonatomic, strong) LFLiveStreamInfo *stream;
@property (nonatomic, strong) LFStreamingBuffer *buffer;
@property (nonatomic, strong) LFLiveDebug *debugInfo;
@property (nonatomic, strong) dispatch_queue_t udpSendQueue;
@property (nonatomic, assign) NSInteger retryTimes4netWorkBreaken;
@property (nonatomic, assign) NSInteger reconnectInterval;
@property (nonatomic, assign) NSInteger reconnectCount;

@property (atomic, assign) BOOL isSending;

@property (nonatomic, assign) BOOL sendVideoHead;
@property (nonatomic, assign) BOOL sendAudioHead;

@property (nonatomic, assign) BOOL serverReady;

@end


@implementation LYStreamingUDPSocket
#pragma mark -- LFStreamSocket
- (nullable instancetype)initWithStream:(nullable LFLiveStreamInfo *)stream{
    return [self initWithStream:stream reconnectInterval:0 reconnectCount:0];
}

- (nullable instancetype)initWithStream:(nullable LFLiveStreamInfo *)stream reconnectInterval:(NSInteger)reconnectInterval reconnectCount:(NSInteger)reconnectCount{
    if (!stream) @throw [NSException exceptionWithName:@"LFStreamRtmpSocket init error" reason:@"stream is nil" userInfo:nil];
    if (self = [super init]) {
        _stream = stream;
        if (reconnectInterval > 0) _reconnectInterval = reconnectInterval;
        else _reconnectInterval = RetryTimesMargin;
        
        if (reconnectCount > 0) _reconnectCount = reconnectCount;
        else _reconnectCount = RetryTimesBreaken;
        
        // 这里改成observer主要考虑一直到发送出错情况下，可以继续发送
        [self addObserver:self forKeyPath:@"isSending" options:NSKeyValueObservingOptionNew context:nil];
    }
    return self;
}

- (void)dealloc {
    [self removeObserver:self forKeyPath:@"isSending"];
}

- (void)start {
    dispatch_async(self.udpSendQueue, ^{
        [self _start];
    });
}

- (void)_start {
    if (!_stream) return;
    if (_udpSocket != NULL) return;
    self.debugInfo.streamId = self.stream.streamId;
    self.debugInfo.uploadUrl = self.stream.url;
    self.debugInfo.isRtmp = YES;
    
    if (self.delegate && [self.delegate respondsToSelector:@selector(socketStatus:status:)]) {
        [self.delegate socketStatus:self status:LFLivePending];
    }
    
    if (_udpSocket != nil) {
        [_udpSocket close];
        _udpSocket = nil;
    }
    [self startUDPSocket];
}

- (void)stop {
    dispatch_async(self.udpSendQueue, ^{
        [self _stop];
        [NSObject cancelPreviousPerformRequestsWithTarget:self];
    });
}

- (void)_stop {
    if (self.delegate && [self.delegate respondsToSelector:@selector(socketStatus:status:)]) {
        [self.delegate socketStatus:self status:LFLiveStop];
    }
    
    if (_udpSocket != nil) {
        [_udpSocket close];
        _udpSocket = nil;
    }
    
    [self clean];
}

- (void)sendFrame:(LFFrame *)frame {
    if (!frame) return;
    [self.buffer appendObject:frame];
    
    if(!self.isSending){
        [self sendFrame];
    }
}

- (void)setDelegate:(id<LFStreamSocketDelegate>)delegate {
    _delegate = delegate;
}

#pragma mark - CustomMethod
- (void)sendFrame {
    __weak typeof(self) _self = self;
     dispatch_async(self.udpSendQueue, ^{
        if (!_self.isSending && _self.buffer.list.count > 0) {
            _self.isSending = YES;

            if (!_self.serverReady || !_self.udpSocket){
                _self.isSending = NO;
                return;
            }

            // 调用发送接口
            LFFrame *frame = [_self.buffer popFirstObject];
            if ([frame isKindOfClass:[LFVideoFrame class]]) {
                if (!_self.sendVideoHead) {
                    _self.sendVideoHead = YES;
                    if(!((LFVideoFrame*)frame).sps || !((LFVideoFrame*)frame).pps){
                        _self.isSending = NO;
                        return;
                    }
                    [_self sendVideoHeader:(LFVideoFrame *)frame];
                } else {
                    [_self sendVideo:(LFVideoFrame *)frame];
                }
            } else {
                if (!_self.sendAudioHead) {
                    _self.sendAudioHead = YES;
                    if(!((LFAudioFrame*)frame).audioInfo){
                        _self.isSending = NO;
                        return;
                    }
                    [_self sendAudioHeader:(LFAudioFrame *)frame];
                } else {
                    [_self sendAudio:frame];
                }
            }

            // debug更新
            _self.debugInfo.totalFrame++;
            _self.debugInfo.dropFrame += _self.buffer.lastDropFrames;
            _self.buffer.lastDropFrames = 0;

            _self.debugInfo.dataFlow += frame.data.length;
            _self.debugInfo.elapsedMilli = CACurrentMediaTime() * 1000 - _self.debugInfo.timeStamp;
            if (_self.debugInfo.elapsedMilli < 1000) {
                _self.debugInfo.bandwidth += frame.data.length;
                if ([frame isKindOfClass:[LFAudioFrame class]]) {
                    _self.debugInfo.capturedAudioCount++;
                } else {
                    _self.debugInfo.capturedVideoCount++;
                }

                _self.debugInfo.unSendCount = _self.buffer.list.count;
            } else {
                _self.debugInfo.currentBandwidth = _self.debugInfo.bandwidth;
                _self.debugInfo.currentCapturedAudioCount = _self.debugInfo.capturedAudioCount;
                _self.debugInfo.currentCapturedVideoCount = _self.debugInfo.capturedVideoCount;
                if (_self.delegate && [_self.delegate respondsToSelector:@selector(socketDebug:debugInfo:)]) {
                    [_self.delegate socketDebug:_self debugInfo:_self.debugInfo];
                }
                _self.debugInfo.bandwidth = 0;
                _self.debugInfo.capturedAudioCount = 0;
                _self.debugInfo.capturedVideoCount = 0;
                _self.debugInfo.timeStamp = CACurrentMediaTime() * 1000;
            }
            
            // 修改发送状态
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                // 这里只为了不循环调用sendFrame方法 调用栈是保证先出栈再进栈
                _self.isSending = NO;
            });
            
        }
    });
}

- (void)clean {
    _isSending = NO;
    _sendAudioHead = NO;
    _sendVideoHead = NO;
    _serverReady = NO;
    self.debugInfo = nil;
    [self.buffer removeAllObject];
    self.retryTimes4netWorkBreaken = 0;
}

- (NSInteger)startUDPSocket {
    //由于摄像头的timestamp是一直在累加，需要每次得到相对时间戳
    //分配与初始化
    
    NSError *error = nil;
    
    if (!_udpSocket) {
        _udpSocket = [[GCDAsyncUdpSocket alloc] initWithDelegate:self delegateQueue:self.udpSendQueue socketQueue:self.udpSendQueue];
        [_udpSocket setIPv4Enabled:YES];
        [_udpSocket setIPv6Enabled:YES];
        [_udpSocket enableBroadcast:NO error:&error];
    }

    [_udpSocket bindToPort:kLocalUDPPort error:&error];
    if(error) {
        NSLog(@"绑定UDP端口[%@]失败: %@", @(kLocalUDPPort), error);
    }
    
    error = nil;
    [_udpSocket beginReceiving:&error];
    
    if (error) {
//        goto Failed;
        NSLog(@"beginReceiving失败: %@", error);
    }
    
    if (self.delegate && [self.delegate respondsToSelector:@selector(socketStatus:status:)]) {
        [self.delegate socketStatus:self status:LFLiveStart];
    }

    [self sendMetaData];

    _serverReady = YES;
    _isSending = NO;
    return 0;

//Failed:
//    if (_udpSocket != nil) {
//        [_udpSocket close];
//        _udpSocket = nil;
//    }
//    [self reconnect];
//    return -1;
}

#pragma mark - UDP Send

- (void)sendMetaData {

}

- (void)sendVideoHeader:(LFVideoFrame *)videoFrame {
 
    if (videoFrame.vps) {
        [self sendVideoHEVCHeader:videoFrame];
    }else {
        [self sendVideoH264Header:videoFrame];
    }
}

- (void)sendVideoH264Header:(LFVideoFrame *)videoFrame {

}

- (void)sendVideoHEVCHeader:(LFVideoFrame *)videoFrame {

}

- (void)sendVideo:(LFVideoFrame *)frame {

//    NSInteger i = 0;
//    NSInteger rtmpLength = frame.data.length + 9;
//    unsigned char *body = (unsigned char *)malloc(rtmpLength);
//    memset(body, 0, rtmpLength);
//
//    if (frame.vps) {
//        if (frame.isKeyFrame) {
//            body[i++] = 0x1C;        // 1:Iframe  12:HEVC
//        }else {
//            body[i++] = 0x2C;        // 2:Pframe  12:HEVC
//        }
//    } else {
//        if (frame.isKeyFrame) {
//            body[i++] = 0x17;        // 1:Pframe  7:AVC
//        }else {
//            body[i++] = 0x27;        // 2:Pframe  7:AVC
//        }
//    }
//    body[i++] = 0x01;    // NALU
//    body[i++] = 0x00;
//    body[i++] = 0x00;
//    body[i++] = 0x00;
//    body[i++] = (frame.data.length >> 24) & 0xff;
//    body[i++] = (frame.data.length >> 16) & 0xff;
//    body[i++] = (frame.data.length >>  8) & 0xff;
//    body[i++] = (frame.data.length) & 0xff;
//    memcpy(&body[i], frame.data.bytes, frame.data.length);
//
//    [self sendPacket:RTMP_PACKET_TYPE_VIDEO data:body size:(rtmpLength) nTimestamp:frame.timestamp];
//    free(body);
}

- (NSInteger)sendPacket:(unsigned int)nPacketType data:(unsigned char *)data size:(NSInteger)size nTimestamp:(uint64_t)nTimestamp {

    return 0;
}

- (void)sendAudioHeader:(LFAudioFrame *)audioFrame {

//    NSInteger rtmpLength = audioFrame.audioInfo.length + 2;     /*spec data长度,一般是2*/
//    unsigned char *body = (unsigned char *)malloc(rtmpLength);
//    memset(body, 0, rtmpLength);
//
//    /*AF 00 + AAC RAW data*/
//    body[0] = 0xAF;
//    body[1] = 0x00;
//    memcpy(&body[2], audioFrame.audioInfo.bytes, audioFrame.audioInfo.length);          /*spec_buf是AAC sequence header数据*/
//    [self sendPacket:RTMP_PACKET_TYPE_AUDIO data:body size:rtmpLength nTimestamp:0];
//    free(body);
}

- (void)sendAudio:(LFFrame *)frame {

//    NSInteger rtmpLength = frame.data.length + 2;    /*spec data长度,一般是2*/
//    unsigned char *body = (unsigned char *)malloc(rtmpLength);
//    memset(body, 0, rtmpLength);
//
//    /*AF 01 + AAC RAW data*/
//    body[0] = 0xAF;
//    body[1] = 0x01;
//    memcpy(&body[2], frame.data.bytes, frame.data.length);
//    [self sendPacket:RTMP_PACKET_TYPE_AUDIO data:body size:rtmpLength nTimestamp:frame.timestamp];
//    free(body);
}

// 断线重连
//- (void)reconnect {
//    dispatch_async(self.udpSendQueue, ^{
//        if (self.retryTimes4netWorkBreaken++ < self.reconnectCount && !self.isReconnecting) {
//            self.isConnected = NO;
//            self.isConnecting = NO;
//            self.isReconnecting = YES;
//            dispatch_async(dispatch_get_main_queue(), ^{
//                 [self performSelector:@selector(_reconnect) withObject:nil afterDelay:self.reconnectInterval];
//            });
//
//        } else if (self.retryTimes4netWorkBreaken >= self.reconnectCount) {
//            if (self.delegate && [self.delegate respondsToSelector:@selector(socketStatus:status:)]) {
//                [self.delegate socketStatus:self status:LFLiveError];
//            }
//            if (self.delegate && [self.delegate respondsToSelector:@selector(socketDidError:errorCode:)]) {
//                [self.delegate socketDidError:self errorCode:LFLiveSocketError_ReConnectTimeOut];
//            }
//        }
//    });
//}
//
//- (void)_reconnect {
//    [NSObject cancelPreviousPerformRequestsWithTarget:self];
//
//    _isReconnecting = NO;
//    if(_isConnected) return;
//
//    _isReconnecting = NO;
//    if (_isConnected) return;
//    if (_udpSocket != nil) {
//        [_udpSocket close];
//        _udpSocket = nil;
//    }
//    _sendAudioHead = NO;
//    _sendVideoHead = NO;
//
//    if (self.delegate && [self.delegate respondsToSelector:@selector(socketStatus:status:)]) {
//        [self.delegate socketStatus:self status:LFLiveRefresh];
//    }
//
//    if (_udpSocket != nil) {
//        [_udpSocket close];
//        _udpSocket = nil;
//    }
//    [self startUDPSocket];
//}

#pragma mark - GCDAsyncUdpSocketDelegate

- (void)udpSocket:(GCDAsyncUdpSocket *)sock didNotConnect:(NSError * _Nullable)error
{
//    if (error) {
//        [self reconnect];
//    }
}

- (void)udpSocket:(GCDAsyncUdpSocket *)sock didNotSendDataWithTag:(long)tag dueToError:(NSError * _Nullable)error
{
    
}

- (void)udpSocketDidClose:(GCDAsyncUdpSocket *)sock withError:(NSError  * _Nullable)error
{
    
}

- (void)udpSocket:(GCDAsyncUdpSocket *)sock didConnectToAddress:(NSData *)address
{
    
}

//void RTMPErrorCallback(RTMPError *error, void *userData) {
//    LFStreamRTMPSocket *socket = (__bridge LFStreamRTMPSocket *)userData;
//    if (error->code < 0) {
//        [socket reconnect];
//    }
//}
//
//void ConnectionTimeCallback(PILI_CONNECTION_TIME *conn_time, void *userData) {
//}

#pragma mark - LFStreamingBufferDelegate

- (void)streamingBuffer:(nullable LFStreamingBuffer *)buffer bufferState:(LFLiveBuffferState)state {
    if(self.delegate && [self.delegate respondsToSelector:@selector(socketBufferStatus:status:)]){
        [self.delegate socketBufferStatus:self status:state];
    }
}

#pragma mark - Observer

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if([keyPath isEqualToString:@"isSending"]){
        if(!self.isSending){
            [self sendFrame];
        }
    }
}

#pragma mark - Getter

- (LFStreamingBuffer *)buffer {
    if (!_buffer) {
        _buffer = [[LFStreamingBuffer alloc] init];
        _buffer.delegate = self;
    }
    return _buffer;
}

- (LFLiveDebug *)debugInfo {
    if (!_debugInfo) {
        _debugInfo = [[LFLiveDebug alloc] init];
    }
    return _debugInfo;
}

- (dispatch_queue_t)udpSendQueue {
    if(!_udpSendQueue){
        _udpSendQueue = dispatch_queue_create("com.vison.shareScreen.RtmpSendQueue", NULL);
    }
    return _udpSendQueue;
}

@end
