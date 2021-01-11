//
//  LFLiveStreamInfo.m
//  LFLiveKit
//
//  Created by LaiFeng on 16/5/20.
//  Copyright © 2016年 LaiFeng All rights reserved.
//

#import "LFLiveStreamInfo.h"

@implementation LFLiveStreamInfo

- (instancetype)init
{
    self = [super init];
    if (self) {
        uint64_t timestamp = (long long)[[NSDate date] timeIntervalSince1970];
        _sourceId = @(timestamp % 100 + arc4random_uniform(1000)).stringValue;
        _streamId = @(timestamp % 100 + arc4random_uniform(1000)).stringValue;
    }
    return self;
}

@end
