//
//  LFStreamRTMPSocket.m
//  LFLiveKit
//
//  Created by LaiFeng on 16/5/20.
//  Copyright © 2016年 LaiFeng All rights reserved.
//

#import "LFStreamRTMPSocket.h"

#if __has_include(<pili-librtmp/rtmp.h>)
#import <pili-librtmp/rtmp.h>
#else
#import "rtmp.h"
#endif

static const NSInteger RetryTimesBreaken = 5;  ///<  重连1分钟  3秒一次 一共20次
static const NSInteger RetryTimesMargin = 3;

typedef struct HVCCNALUnitArray {
    uint8_t  array_completeness;
    uint8_t  NAL_unit_type;
    uint16_t numNalus;
    uint16_t *nalUnitLength;
    uint8_t  **nalUnit;
} HVCCNALUnitArray;

typedef struct HEVCDecoderConfigurationRecord {
    uint8_t  configurationVersion;
    uint8_t  general_profile_space;
    uint8_t  general_tier_flag;
    uint8_t  general_profile_idc;
    uint32_t general_profile_compatibility_flags;
    uint64_t general_constraint_indicator_flags;
    uint8_t  general_level_idc;
    uint16_t min_spatial_segmentation_idc;
    uint8_t  parallelismType;
    uint8_t  chromaFormat;
    uint8_t  bitDepthLumaMinus8;
    uint8_t  bitDepthChromaMinus8;
    uint16_t avgFrameRate;
    uint8_t  constantFrameRate;
    uint8_t  numTemporalLayers;
    uint8_t  temporalIdNested;
    uint8_t  lengthSizeMinusOne;
    uint8_t  numOfArrays;
    HVCCNALUnitArray *array;
} HEVCDecoderConfigurationRecord;

#define RTMP_RECEIVE_TIMEOUT    2
#define DATA_ITEMS_MAX_COUNT 100
#define RTMP_DATA_RESERVE_SIZE 400
#define RTMP_HEAD_SIZE (sizeof(PILI_RTMPPacket) + RTMP_MAX_HEADER_SIZE)

#define SAVC(x)    static const AVal av_ ## x = AVC(#x)

static const AVal av_setDataFrame = AVC("@setDataFrame");
static const AVal av_SDKVersion = AVC("LFLiveKit-Recoder 2.7.3");
SAVC(onMetaData);
SAVC(duration);
SAVC(width);
SAVC(height);
SAVC(videocodecid);
SAVC(videodatarate);
SAVC(framerate);
SAVC(audiocodecid);
SAVC(audiodatarate);
SAVC(audiosamplerate);
SAVC(audiosamplesize);
//SAVC(audiochannels);
SAVC(stereo);
SAVC(encoder);
//SAVC(av_stereo);
SAVC(fileSize);
SAVC(avc1);
SAVC(hevc);
SAVC(mp4a);

@interface LFStreamRTMPSocket ()<LFStreamingBufferDelegate>
{
    PILI_RTMP *_rtmp;
}
@property (nonatomic, weak) id<LFStreamSocketDelegate> delegate;
@property (nonatomic, strong) LFLiveStreamInfo *stream;
@property (nonatomic, strong) LFStreamingBuffer *buffer;
@property (nonatomic, strong) LFLiveDebug *debugInfo;
@property (nonatomic, strong) dispatch_queue_t rtmpSendQueue;
//错误信息
@property (nonatomic, assign) RTMPError error;
@property (nonatomic, assign) NSInteger retryTimes4netWorkBreaken;
@property (nonatomic, assign) NSInteger reconnectInterval;
@property (nonatomic, assign) NSInteger reconnectCount;

@property (atomic, assign) BOOL isSending;
@property (nonatomic, assign) BOOL isConnected;
@property (nonatomic, assign) BOOL isConnecting;
@property (nonatomic, assign) BOOL isReconnecting;

@property (nonatomic, assign) BOOL sendVideoHead;
@property (nonatomic, assign) BOOL sendAudioHead;

@end

@implementation LFStreamRTMPSocket

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
        
        [self addObserver:self forKeyPath:@"isSending" options:NSKeyValueObservingOptionNew context:nil];//这里改成observer主要考虑一直到发送出错情况下，可以继续发送
    }
    return self;
}

- (void)dealloc{
    [self removeObserver:self forKeyPath:@"isSending"];
}

- (void)start {
    dispatch_async(self.rtmpSendQueue, ^{
        [self _start];
    });
}

- (void)_start {
    if (!_stream) return;
    if (_isConnecting) return;
    if (_rtmp != NULL) return;
    self.debugInfo.streamId = self.stream.streamId;
    self.debugInfo.uploadUrl = self.stream.url;
    self.debugInfo.isRtmp = YES;
    if (_isConnecting) return;
    
    _isConnecting = YES;
    if (self.delegate && [self.delegate respondsToSelector:@selector(socketStatus:status:)]) {
        [self.delegate socketStatus:self status:LFLivePending];
    }
    
    if (_rtmp != NULL) {
        PILI_RTMP_Close(_rtmp, &_error);
        PILI_RTMP_Free(_rtmp);
    }
    [self RTMP264_Connect:(char *)[_stream.url cStringUsingEncoding:NSASCIIStringEncoding]];
}

- (void)stop {
    dispatch_async(self.rtmpSendQueue, ^{
        [self _stop];
        [NSObject cancelPreviousPerformRequestsWithTarget:self];
    });
}

- (void)_stop {
    if (self.delegate && [self.delegate respondsToSelector:@selector(socketStatus:status:)]) {
        [self.delegate socketStatus:self status:LFLiveStop];
    }
    if (_rtmp != NULL) {
        PILI_RTMP_Close(_rtmp, &_error);
        PILI_RTMP_Free(_rtmp);
        _rtmp = NULL;
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

#pragma mark -- CustomMethod
- (void)sendFrame {
    __weak typeof(self) _self = self;
     dispatch_async(self.rtmpSendQueue, ^{
        if (!_self.isSending && _self.buffer.list.count > 0) {
            _self.isSending = YES;

            if (!_self.isConnected || _self.isReconnecting || _self.isConnecting || !_rtmp){
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

            //debug更新
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
            
            //修改发送状态
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                //< 这里只为了不循环调用sendFrame方法 调用栈是保证先出栈再进栈
                _self.isSending = NO;
            });
            
        }
    });
}

- (void)clean {
    _isConnecting = NO;
    _isReconnecting = NO;
    _isSending = NO;
    _isConnected = NO;
    _sendAudioHead = NO;
    _sendVideoHead = NO;
    self.debugInfo = nil;
    [self.buffer removeAllObject];
    self.retryTimes4netWorkBreaken = 0;
}

- (NSInteger)RTMP264_Connect:(char *)push_url {
    //由于摄像头的timestamp是一直在累加，需要每次得到相对时间戳
    //分配与初始化
    _rtmp = PILI_RTMP_Alloc();
    PILI_RTMP_Init(_rtmp);

    //设置URL
    if (PILI_RTMP_SetupURL(_rtmp, push_url, &_error) == FALSE) {
        //log(LOG_ERR, "RTMP_SetupURL() failed!");
        goto Failed;
    }

    _rtmp->m_errorCallback = RTMPErrorCallback;
    _rtmp->m_connCallback = ConnectionTimeCallback;
    _rtmp->m_userData = (__bridge void *)self;
    _rtmp->m_msgCounter = 1;
    _rtmp->Link.timeout = RTMP_RECEIVE_TIMEOUT;
    
    //设置可写，即发布流，这个函数必须在连接前使用，否则无效
    PILI_RTMP_EnableWrite(_rtmp);

    //连接服务器
    if (PILI_RTMP_Connect(_rtmp, NULL, &_error) == FALSE) {
        goto Failed;
    }

    //连接流
    if (PILI_RTMP_ConnectStream(_rtmp, 0, &_error) == FALSE) {
        goto Failed;
    }

    if (self.delegate && [self.delegate respondsToSelector:@selector(socketStatus:status:)]) {
        [self.delegate socketStatus:self status:LFLiveStart];
    }

    [self sendMetaData];

    _isConnected = YES;
    _isConnecting = NO;
    _isReconnecting = NO;
    _isSending = NO;
    return 0;

Failed:
    PILI_RTMP_Close(_rtmp, &_error);
    PILI_RTMP_Free(_rtmp);
    _rtmp = NULL;
    [self reconnect];
    return -1;
}

#pragma mark -- Rtmp Send

- (void)sendMetaData {
    PILI_RTMPPacket packet;

    char pbuf[2048], *pend = pbuf + sizeof(pbuf);

    packet.m_nChannel = 0x03;                   // control channel (invoke)
    packet.m_headerType = RTMP_PACKET_SIZE_LARGE;
    packet.m_packetType = RTMP_PACKET_TYPE_INFO;
    packet.m_nTimeStamp = 0;
    packet.m_nInfoField2 = _rtmp->m_stream_id;
    packet.m_hasAbsTimestamp = TRUE;
    packet.m_body = pbuf + RTMP_MAX_HEADER_SIZE;

    char *enc = packet.m_body;
    enc = AMF_EncodeString(enc, pend, &av_setDataFrame);
    enc = AMF_EncodeString(enc, pend, &av_onMetaData);

    *enc++ = AMF_OBJECT;

    enc = AMF_EncodeNamedNumber(enc, pend, &av_duration, 0.0);
    enc = AMF_EncodeNamedNumber(enc, pend, &av_fileSize, 0.0);

    // videosize
    enc = AMF_EncodeNamedNumber(enc, pend, &av_width, _stream.videoConfiguration.videoSize.width);
    enc = AMF_EncodeNamedNumber(enc, pend, &av_height, _stream.videoConfiguration.videoSize.height);
    
    // video
    if (_stream.videoConfiguration.encoderType == LFVideoH264Encoder) {
        enc = AMF_EncodeNamedString(enc, pend, &av_videocodecid, &av_avc1);
    }else if (_stream.videoConfiguration.encoderType == LFVideoH265Encoder) {
        enc = AMF_EncodeNamedString(enc, pend, &av_videocodecid, &av_hevc);
    }

    enc = AMF_EncodeNamedNumber(enc, pend, &av_videodatarate, _stream.videoConfiguration.videoBitRate / 1000.f);
    enc = AMF_EncodeNamedNumber(enc, pend, &av_framerate, _stream.videoConfiguration.videoFrameRate);

    // audio
    enc = AMF_EncodeNamedString(enc, pend, &av_audiocodecid, &av_mp4a);
    enc = AMF_EncodeNamedNumber(enc, pend, &av_audiodatarate, _stream.audioConfiguration.audioBitrate);

    enc = AMF_EncodeNamedNumber(enc, pend, &av_audiosamplerate, _stream.audioConfiguration.audioSampleRate);
    enc = AMF_EncodeNamedNumber(enc, pend, &av_audiosamplesize, 16.0);
    enc = AMF_EncodeNamedBoolean(enc, pend, &av_stereo, _stream.audioConfiguration.numberOfChannels == 2);

    // sdk version
    enc = AMF_EncodeNamedString(enc, pend, &av_encoder, &av_SDKVersion);

    *enc++ = 0;
    *enc++ = 0;
    *enc++ = AMF_OBJECT_END;

    packet.m_nBodySize = (uint32_t)(enc - packet.m_body);
    if (!PILI_RTMP_SendPacket(_rtmp, &packet, FALSE, &_error)) {
        return;
    }
}

- (void)sendVideoHeader:(LFVideoFrame *)videoFrame {
 
    if (videoFrame.vps) {
        [self sendVideoHEVCHeader:videoFrame];
    }else {
        [self sendVideoH264Header:videoFrame];
    }
}

- (void)sendVideoH264Header:(LFVideoFrame *)videoFrame {

    unsigned char *body = NULL;
    NSInteger iIndex = 0;
    NSInteger rtmpLength = 1024;
    const char *sps = videoFrame.sps.bytes;
    const char *pps = videoFrame.pps.bytes;
    NSInteger sps_len = videoFrame.sps.length;
    NSInteger pps_len = videoFrame.pps.length;

    body = (unsigned char *)malloc(rtmpLength);
    memset(body, 0, rtmpLength);

    /* Video FLV Tag
    FrameType 是 4 个 bit。取值 1：keyframe，2：inter frame
    CodecID 是 4 个 bit。取值 7，表示 AVC/H264
    AVCPacketType 是 8 个 bit。取值 0：表示 Composition Time 后面的数据是 AVCDecorderConfigurationRecord 结构，如图一所示；取值 1：表示 Composition Time 后面的数据是 H264 NALU 格式，如图二所示。
    Composition Time 是 24 个 bit。表示时间，暂且不用关注。
     */
    
    body[iIndex++] = 0x17;
    body[iIndex++] = 0x00;

    body[iIndex++] = 0x00;
    body[iIndex++] = 0x00;
    body[iIndex++] = 0x00;

    body[iIndex++] = 0x01;
    body[iIndex++] = sps[1];
    body[iIndex++] = sps[2];
    body[iIndex++] = sps[3];
    body[iIndex++] = 0xff;

    /*sps*/
    body[iIndex++] = 0xe1;
    body[iIndex++] = (sps_len >> 8) & 0xff;
    body[iIndex++] = sps_len & 0xff;
    memcpy(&body[iIndex], sps, sps_len);
    iIndex += sps_len;

    /*pps*/
    body[iIndex++] = 0x01;
    body[iIndex++] = (pps_len >> 8) & 0xff;
    body[iIndex++] = (pps_len) & 0xff;
    memcpy(&body[iIndex], pps, pps_len);
    iIndex += pps_len;

    [self sendPacket:RTMP_PACKET_TYPE_VIDEO data:body size:iIndex nTimestamp:0];
    free(body);
}

- (void)sendVideoHEVCHeader:(LFVideoFrame *)videoFrame {

    unsigned char *body = NULL;
    NSInteger iIndex = 0;
    NSInteger rtmpLength = 1024;
    const char *vps = videoFrame.vps.bytes;
    const char *sps = videoFrame.sps.bytes;
    const char *pps = videoFrame.pps.bytes;
    NSInteger vps_len = videoFrame.vps.length;
    NSInteger sps_len = videoFrame.sps.length;
    NSInteger pps_len = videoFrame.pps.length;

    body = (unsigned char *)malloc(rtmpLength);
    memset(body, 0, rtmpLength);
    
    /*
     * FrameType                                    4 bits
     * CodecID                                      4 bits
     * AVCPacketType                                1 byte
     * CompositionTime                              3 bytes
     * HEVCDecoderConfigurationRecord
     *      configurationVersion                    1 byte
     */
    body[iIndex++] = 0x1C;
    body[iIndex++] = 0x00;
    body[iIndex++] = 0x00;
    body[iIndex++] = 0x00;
    body[iIndex++] = 0x00;
    body[iIndex++] = 0x01;
 
    /*
     * HEVCDecoderConfigurationRecord 160 bit
     *      general_profile_space                   2 bits
     *      general_tier_flag                       1 bit
     *      general_profile_idc                     5 bits
     *      general_profile_compatibility_flags     4 bytes
     *      general_constraint_indicator_flags      6 bytes
     *      general_level_idc                       1 byte
     *      min_spatial_segmentation_idc            4 bits reserved + 12 bits
     *      parallelismType                         6 bits reserved + 2 bits
     *      chroma_format_idc                       6 bits reserved + 2 bits
     *      bit_depth_luma_minus8                   5 bits reserved + 3 bits
     *      bit_depth_chroma_minus8                 5 bits reserved + 3 bits
     *      avgFrameRate                            2 bytes
     */
    body[iIndex++] = 0x00;
    body[iIndex++] = 0x00;
    body[iIndex++] = 0x00;
    body[iIndex++] = 0x00;
    body[iIndex++] = 0x00;
    body[iIndex++] = 0x00;
    body[iIndex++] = 0x00;
    body[iIndex++] = 0x00;
    body[iIndex++] = 0x00;
    body[iIndex++] = 0x00;
    body[iIndex++] = 0x00;
    body[iIndex++] = 0x00;
    body[iIndex++] = 0x00;
    body[iIndex++] = 0x00;
    body[iIndex++] = 0x00;
    body[iIndex++] = 0x00;
    body[iIndex++] = 0x00;
    body[iIndex++] = 0x00;
    body[iIndex++] = 0x00;
    body[iIndex++] = 0x00;

    /*
     * HEVCDecoderConfigurationRecord
     *      constantFrameRate                       2 bits
     *      numTemporalLayers                       3 bits
     *      temporalIdNested                        1 bit
     *      lengthSizeMinusOne                      2 bits
     */
    body[iIndex++] = 0x03;

    /*
     * HEVCDecoderConfigurationRecord
     *      numOfArrays                             1 byte
     */
    body[iIndex++] = 0x03;

    /* 
     * array_completeness                       1 bit
     * reserved                                 1 bit
     * NAL_unit_type                            6 bits
     * numNalus                                 2 bytes
     */
    /*vps*/
    body[iIndex++] = 0x20;  //vps 32
    body[iIndex++] = (1 >> 8) & 0xff;
    body[iIndex++] = 1 & 0xff;
    body[iIndex++] = (vps_len >> 8) & 0xff;
    body[iIndex++] = vps_len & 0xff;
    memcpy(&body[iIndex], vps, vps_len);
    iIndex += vps_len;
    
    /*sps*/
    body[iIndex++] = 0x21; //sps 33
    body[iIndex++] = (1 >> 8) & 0xff;
    body[iIndex++] = 1 & 0xff;
    body[iIndex++] = (sps_len >> 8) & 0xff;
    body[iIndex++] = sps_len & 0xff;
    memcpy(&body[iIndex], sps, sps_len);
    iIndex += sps_len;

    /*pps*/
    body[iIndex++] = 0x22; //pps 34
    body[iIndex++] = (1 >> 8) & 0xff;
    body[iIndex++] = 1 & 0xff;
    body[iIndex++] = (pps_len >> 8) & 0xff;
    body[iIndex++] = (pps_len) & 0xff;
    memcpy(&body[iIndex], pps, pps_len);
    iIndex += pps_len;

    [self sendPacket:RTMP_PACKET_TYPE_VIDEO data:body size:iIndex nTimestamp:0];
    free(body);
}

- (void)sendVideo:(LFVideoFrame *)frame {

    NSInteger i = 0;
    NSInteger rtmpLength = frame.data.length + 9;
    unsigned char *body = (unsigned char *)malloc(rtmpLength);
    memset(body, 0, rtmpLength);

    if (frame.vps) {
        if (frame.isKeyFrame) {
            body[i++] = 0x1C;        // 1:Iframe  12:HEVC
        }else {
            body[i++] = 0x2C;        // 2:Pframe  12:HEVC
        }
    } else {
        if (frame.isKeyFrame) {
            body[i++] = 0x17;        // 1:Pframe  7:AVC
        }else {
            body[i++] = 0x27;        // 2:Pframe  7:AVC
        }
    }
    body[i++] = 0x01;    // NALU
    body[i++] = 0x00;
    body[i++] = 0x00;
    body[i++] = 0x00;
    body[i++] = (frame.data.length >> 24) & 0xff;
    body[i++] = (frame.data.length >> 16) & 0xff;
    body[i++] = (frame.data.length >>  8) & 0xff;
    body[i++] = (frame.data.length) & 0xff;
    memcpy(&body[i], frame.data.bytes, frame.data.length);

    [self sendPacket:RTMP_PACKET_TYPE_VIDEO data:body size:(rtmpLength) nTimestamp:frame.timestamp];
    free(body);
}

- (NSInteger)sendPacket:(unsigned int)nPacketType data:(unsigned char *)data size:(NSInteger)size nTimestamp:(uint64_t)nTimestamp {
    NSInteger rtmpLength = size;
    PILI_RTMPPacket rtmp_pack;
    PILI_RTMPPacket_Reset(&rtmp_pack);
    PILI_RTMPPacket_Alloc(&rtmp_pack, (uint32_t)rtmpLength);

    rtmp_pack.m_nBodySize = (uint32_t)size;
    memcpy(rtmp_pack.m_body, data, size);
    rtmp_pack.m_hasAbsTimestamp = 0;
    rtmp_pack.m_packetType = nPacketType;
    if (_rtmp) rtmp_pack.m_nInfoField2 = _rtmp->m_stream_id;
    rtmp_pack.m_nChannel = 0x04;
    rtmp_pack.m_headerType = RTMP_PACKET_SIZE_LARGE;
    if (RTMP_PACKET_TYPE_AUDIO == nPacketType && size != 4) {
        rtmp_pack.m_headerType = RTMP_PACKET_SIZE_MEDIUM;
    }
    rtmp_pack.m_nTimeStamp = (uint32_t)nTimestamp;

    NSInteger nRet = [self RtmpPacketSend:&rtmp_pack];

    PILI_RTMPPacket_Free(&rtmp_pack);
    return nRet;
}

- (NSInteger)RtmpPacketSend:(PILI_RTMPPacket *)packet {
    if (_rtmp && PILI_RTMP_IsConnected(_rtmp)) {
        int success = PILI_RTMP_SendPacket(_rtmp, packet, 0, &_error);
        return success;
    }
    return -1;
}

- (void)sendAudioHeader:(LFAudioFrame *)audioFrame {

    NSInteger rtmpLength = audioFrame.audioInfo.length + 2;     /*spec data长度,一般是2*/
    unsigned char *body = (unsigned char *)malloc(rtmpLength);
    memset(body, 0, rtmpLength);

    /*AF 00 + AAC RAW data*/
    body[0] = 0xAF;
    body[1] = 0x00;
    memcpy(&body[2], audioFrame.audioInfo.bytes, audioFrame.audioInfo.length);          /*spec_buf是AAC sequence header数据*/
    [self sendPacket:RTMP_PACKET_TYPE_AUDIO data:body size:rtmpLength nTimestamp:0];
    free(body);
}

- (void)sendAudio:(LFFrame *)frame {

    NSInteger rtmpLength = frame.data.length + 2;    /*spec data长度,一般是2*/
    unsigned char *body = (unsigned char *)malloc(rtmpLength);
    memset(body, 0, rtmpLength);

    /*AF 01 + AAC RAW data*/
    body[0] = 0xAF;
    body[1] = 0x01;
    memcpy(&body[2], frame.data.bytes, frame.data.length);
    [self sendPacket:RTMP_PACKET_TYPE_AUDIO data:body size:rtmpLength nTimestamp:frame.timestamp];
    free(body);
}

// 断线重连
- (void)reconnect {
    dispatch_async(self.rtmpSendQueue, ^{
        if (self.retryTimes4netWorkBreaken++ < self.reconnectCount && !self.isReconnecting) {
            self.isConnected = NO;
            self.isConnecting = NO;
            self.isReconnecting = YES;
            dispatch_async(dispatch_get_main_queue(), ^{
                 [self performSelector:@selector(_reconnect) withObject:nil afterDelay:self.reconnectInterval];
            });
           
        } else if (self.retryTimes4netWorkBreaken >= self.reconnectCount) {
            if (self.delegate && [self.delegate respondsToSelector:@selector(socketStatus:status:)]) {
                [self.delegate socketStatus:self status:LFLiveError];
            }
            if (self.delegate && [self.delegate respondsToSelector:@selector(socketDidError:errorCode:)]) {
                [self.delegate socketDidError:self errorCode:LFLiveSocketError_ReConnectTimeOut];
            }
        }
    });
}

- (void)_reconnect{
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    
    _isReconnecting = NO;
    if(_isConnected) return;
    
    _isReconnecting = NO;
    if (_isConnected) return;
    if (_rtmp != NULL) {
        PILI_RTMP_Close(_rtmp, &_error);
        PILI_RTMP_Free(_rtmp);
        _rtmp = NULL;
    }
    _sendAudioHead = NO;
    _sendVideoHead = NO;
    
    if (self.delegate && [self.delegate respondsToSelector:@selector(socketStatus:status:)]) {
        [self.delegate socketStatus:self status:LFLiveRefresh];
    }
    
    if (_rtmp != NULL) {
        PILI_RTMP_Close(_rtmp, &_error);
        PILI_RTMP_Free(_rtmp);
    }
    [self RTMP264_Connect:(char *)[_stream.url cStringUsingEncoding:NSASCIIStringEncoding]];
}

#pragma mark -- CallBack
void RTMPErrorCallback(RTMPError *error, void *userData) {
    LFStreamRTMPSocket *socket = (__bridge LFStreamRTMPSocket *)userData;
    if (error->code < 0) {
        [socket reconnect];
    }
}

void ConnectionTimeCallback(PILI_CONNECTION_TIME *conn_time, void *userData) {
}

#pragma mark -- LFStreamingBufferDelegate
- (void)streamingBuffer:(nullable LFStreamingBuffer *)buffer bufferState:(LFLiveBuffferState)state{
    if(self.delegate && [self.delegate respondsToSelector:@selector(socketBufferStatus:status:)]){
        [self.delegate socketBufferStatus:self status:state];
    }
}

#pragma mark -- Observer
-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context{
    if([keyPath isEqualToString:@"isSending"]){
        if(!self.isSending){
            [self sendFrame];
        }
    }
}

#pragma mark -- Getter Setter

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

- (dispatch_queue_t)rtmpSendQueue{
    if(!_rtmpSendQueue){
        _rtmpSendQueue = dispatch_queue_create("com.youku.LaiFeng.RtmpSendQueue", NULL);
    }
    return _rtmpSendQueue;
}

@end
