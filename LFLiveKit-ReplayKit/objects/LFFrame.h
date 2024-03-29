//
//  LFFrame.h
//  LFLiveKit
//
//  Created by LaiFeng on 16/5/20.
//  Copyright © 2016年 LaiFeng All rights reserved.
//

#import <Foundation/Foundation.h>

@interface LFFrame : NSObject

@property (nonatomic, assign) uint32_t frameNumber;
@property (nonatomic, assign) uint64_t timestamp;
/// CGImagePropertyOrientation
@property (nonatomic, assign) uint32_t videoOrientation;

@property (nonatomic, strong) NSData *data;
///< flv或者rtmp包头
@property (nonatomic, strong) NSData *header;

@end
