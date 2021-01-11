//
//  media_proto.h
//  Pods
//
//  Created by RoyLei on 1/9/21.
//

#ifndef media_proto_h
#define media_proto_h

#pragma once

typedef NS_ENUM (uint8_t, LY_CODEC_ID) {
    LY_CODEC_ID_NONE = 0,
    LY_CODEC_ID_H264 = 1,
    LY_CODEC_ID_H265 = 2,
    LY_CODEC_ID_MPEG2 = 3,
    LY_CODEC_ID_MPEG4 = 4,
    LY_CODEC_ID_PCMA = 16,
    LY_CODEC_ID_PCMU = 17,
    LY_CODEC_ID_AAC = 18,
    LY_CODEC_ID_G711A = 19,
    LY_CODEC_ID_G711U = 20,
    LY_CODEC_ID_G726 = 21
};

typedef NS_ENUM (uint8_t, LY_STREAM_TYPE) {
    LY_STREAM_TYPE_NONE = 0,
    LY_STREAM_TYPE_AUDIO = 1,
    LY_STREAM_TYPE_VIDEO = 2,
    LY_STREAM_TYPE_IMAGE = 3
};

typedef NS_ENUM (uint8_t, LY_STREAM_ID) {
    LY_STREAM_ID_NONE = 0,
    LY_STREAM_ID_AUDIO = 1,
    LY_STREAM_ID_VIDEO = 2
};

#pragma pack(push, 1)

typedef struct ly_video_t {
    uint32_t    width;
    uint32_t    height;
    uint32_t    crop_x;
    uint32_t    crop_y;
    uint32_t    crop_w;
    uint32_t    crop_h;
} ly_video_t;

typedef struct ly_audio_t {
    uint16_t    sample_frequency;
    uint16_t    bit_per_sample;
    uint16_t    num_channels;
} ly_audio_t;

typedef struct ly_stream_t {
    uint64_t   steam_id;
    uint8_t    codec; // codec_id
    uint8_t    type;  // stream type
    ly_video_t video;
    ly_audio_t audio;
} ly_stream_t;

typedef struct ly_output_t {
    uint32_t    addr;
    uint16_t    port;
} ly_output_t;

#define _FRAME_MAGIC_ (0x66668888)

typedef struct ly_frame_t {
    uint32_t    magic;  // _FRAME_MAGIC_
    uint64_t    source_id;
    uint64_t    stream_id;
    uint8_t     media_type; // NONE = 0, AUDIO = 1, VIDEO = 2, IMAGE = 3
    uint8_t     codec; // VIEW_CODEC, NONE = 0, H264 = 1, H265 = 2, MPEG2 = 3, MPEG4 = 4, PCMA = 16, PCMU = 17, AAC = 18, G711A = 19, G711U = 20, G726 = 21
    ly_audio_t  audio;
    ly_video_t  video;
    uint8_t     frame_type; // 0 - unknow, 1-I Frame, 2-P Frame, 3-B Frame
    uint32_t    frame_num;
    uint32_t    frame_len;
    uint64_t    timestamp;
} ly_frame_t;

typedef struct ly_slice_t {
    ly_frame_t  frame;
    uint16_t    slice_cnt;
    uint16_t    slice_num;
    uint16_t    slice_len;
    uint8_t     slice_dat[1300];
} ly_slice_t;

#define _PROTO_CMD_MAGIC_ (0x55557777)
#define _REQUEST_STREAM_  (1)

typedef struct ly_proto_cmd_t {
    uint32_t    magic; // _PROTO_CMD_MAGIC_
    uint16_t    cmd_id;
    uint8_t     reserved[4];
    uint16_t    len;
    uint8_t     data[1300];
} ly_proto_cmd_t;

#pragma pack(pop)

#endif /* media_proto_h */
