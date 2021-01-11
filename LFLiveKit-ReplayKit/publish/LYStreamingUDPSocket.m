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
                /*
                 * flv格式
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
                */
                
                [_self sendVideo:(LFVideoFrame *)frame];

            } else {
                /*
                 * flv格式
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
                */
                
                [_self sendAudio:frame];
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

- (void)startUDPSocket {
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
        NSLog(@"beginReceiving失败: %@", error);
    }
    
    if (self.delegate && [self.delegate respondsToSelector:@selector(socketStatus:status:)]) {
        [self.delegate socketStatus:self status:LFLiveStart];
    }

    _serverReady = YES;
    _isSending = NO;
}

#pragma mark - UDP Send

- (void)sendAudio:(LFFrame *)frame {
    
    ly_frame_t frameT;
    memset(&frameT, 0, sizeof(ly_frame_t));
    ly_slice_t slice;
    memset(&slice, 0, sizeof(ly_slice_t));

    frameT.magic = _FRAME_MAGIC_;
    frameT.source_id = self.stream.sourceId.longLongValue;
    frameT.stream_id = self.stream.streamId.longLongValue + LY_STREAM_ID_AUDIO;
    frameT.media_type = LY_STREAM_TYPE_AUDIO;
    frameT.codec = LY_CODEC_ID_AAC;
    frameT.audio = [self _audioInfo];
    frameT.frame_num = frame.frameNumber;
    frameT.frame_len = frame.data.length;
    frameT.timestamp = frame.timestamp;
    
    slice.frame = frameT;

    NSInteger maxSliceSize = sizeof(slice.slice_dat);
    [self sendFrame:frame mediaSlice:slice dataLimitedLength:maxSliceSize toUDPPort:self.stream.udpAudioPort];
}

- (void)sendVideo:(LFVideoFrame *)frame {
    
    ly_frame_t frameT;
    memset(&frameT, 0, sizeof(ly_frame_t));
    ly_slice_t slice;
    memset(&slice, 0, sizeof(ly_slice_t));
    
    frameT.magic = _FRAME_MAGIC_;
    frameT.source_id = self.stream.sourceId.longLongValue;
    frameT.stream_id = self.stream.streamId.longLongValue + LY_STREAM_ID_VIDEO;
    frameT.media_type = LY_STREAM_TYPE_VIDEO;
    if (self.stream.videoConfiguration.encoderType == LFVideoH264Encoder) {
        frameT.codec = LY_CODEC_ID_H264;
    } else {
        frameT.codec = LY_CODEC_ID_H265;
    }
    frameT.video = [self _videoInfo];
    frameT.frame_type = frame.isKeyFrame ? 1 : 2;
    frameT.frame_num = frame.frameNumber;
    frameT.frame_len = frame.data.length;
    frameT.timestamp = frame.timestamp;
    
    slice.frame = frameT;
    
    NSInteger maxSliceSize = sizeof(slice.slice_dat);
    [self sendFrame:frame mediaSlice:slice dataLimitedLength:maxSliceSize toUDPPort:self.stream.udpVideoPort];
}

- (void)sendFrame:(LFFrame *)frame mediaSlice:(ly_slice_t)slice dataLimitedLength:(NSInteger)limitedLength toUDPPort:(int16_t)udpPort {

    slice.slice_cnt = frame.data.length / limitedLength + frame.data.length % limitedLength ? 1 : 0;
    
    if(slice.slice_cnt > 1) {
        NSInteger sliceNum = 0;
        NSInteger framePos = 0;
        uint8_t *frameDP = (uint8_t *)frame.data.bytes;

        while (framePos < frame.data.length) {
            ly_slice_t sliceTmp;
            memset(&sliceTmp, 0, sizeof(ly_slice_t));
            
            sliceTmp.frame = slice.frame;
            sliceTmp.slice_cnt = slice.slice_cnt;
            sliceTmp.slice_num = sliceNum;
            sliceTmp.slice_len = MIN(limitedLength, frame.data.length - framePos);
            
            memcpy(&sliceTmp.slice_dat, frameDP + framePos, sliceTmp.slice_len);
            
            sliceNum++;
            framePos += sliceTmp.slice_len;
            
            [self sendSlice:sliceTmp toUDPPort:udpPort];
        }
    }else {
        [self sendSlice:slice toUDPPort:udpPort];
    }
}

- (void)sendSlice:(ly_slice_t)slice toUDPPort:(int16_t)udpPort {

    NSData *sliceData = [NSData dataWithBytes:&slice length:sizeof(slice)];
    [_udpSocket sendData:sliceData toHost:self.stream.udpHost port:udpPort withTimeout:-1 tag:101];
}

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

- (ly_video_t)_videoInfo {
    ly_video_t videoT;
    memset(&videoT, 0, sizeof(ly_video_t));
    videoT.width = self.stream.videoConfiguration.videoSize.width;
    videoT.height = self.stream.videoConfiguration.videoSize.height;
    return videoT;
}

- (ly_audio_t)_audioInfo {
    ly_audio_t audioT;
    memset(&audioT, 0, sizeof(ly_audio_t));
    audioT.bit_per_sample = 16;
    audioT.sample_frequency = self.stream.audioConfiguration.audioSampleRate;
    audioT.num_channels = self.stream.audioConfiguration.numberOfChannels;
    return audioT;
}

@end
