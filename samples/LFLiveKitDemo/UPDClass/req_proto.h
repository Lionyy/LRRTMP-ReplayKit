//
//  req_proto.h
//  Pods
//
//  Created by RoyLei on 2021/1/10.
//

#ifndef req_proto_h
#define req_proto_h

#pragma pack(push, 1)

static uint32_t LY_SEARCH_CMD = 0xFFEEAACC;
static uint32_t LY_REQ_PORT_CMD = 0xFFEEAABB;

/// 广播搜索投屏服务请求
typedef struct ly_search_t
{
    uint32_t  magic; //4字节，固定值0xFFEEAACC
    uint16_t  len;   //2字节，暂时不用，置为0
    uint8_t   data[1300]; //4字节，暂时不用，置为0
} ly_search_t;

/// 广播搜索投屏服务响应
typedef struct ly_search_response_t
{
    uint32_t  magic; //4字节，固定值0xFFEEAACC
    uint32_t  addr; //4字节，投屏服务的IP，客户端也可通过recvfrom函数获取投屏服务的IP
    uint16_t  port; //4字节，接收命令的udp端口
    uint8_t   name[32]; //32字节，投屏服务的名称，utf8编码格式
    uint16_t  len; //2字节，暂时不用，置为0
    uint8_t   data[1300]; //4字节，暂时不用，置为0
} ly_search_response_t;

/// 请求接音视频数据的IP及端口
typedef struct ly_request_port_t
{
    uint32_t  magic; //4字节，固定值0xFFEEAABB
    uint32_t  width; //4字节，投屏客户端图像的宽度
    uint32_t  height; //4字节，投屏客户端图像的高度
    uint16_t  video_fps; //2字节，视频帧率
    uint16_t  sample_frequency; //2字节，音频采样率
    uint16_t  bit_per_sample; //2字节，每个声音样本的位数
    uint16_t  num_channels; //2字节，通道数
    uint16_t  audio_fps; //2字节，音频帧率
    uint8_t   name[32]; //32字节，投屏客户端名称，utf8编码格式
    uint16_t  len; //2字节，暂时不用，置为0
    uint8_t   data[1300]; //4字节，暂时不用，置为0
} ly_request_port_t;

/// 请求接音视频数据的IP及端口响应
typedef struct ly_request_port_response_t
{
    uint32_t  magic; // 4字节，固定值0xFFEEAABB
    uint32_t  addr; // 4字节，接收端的IP
    uint16_t  video_port; //4字节，接收视频数据的udp端口
    uint16_t  audio_port; //4字节，接收音频数据的udp端口
    uint16_t  len; //2字节，暂时不用，置为0
    uint8_t   data[1300]; //4字节，暂时不用，置为0
} ly_request_port_response_t;

#pragma pack(pop)

#endif /* req_proto_h */
