//
//  LYUtils.h
//  LFLiveKitDemo
//
//  Created by RoyLei on 1/11/21.
//  Copyright © 2021 admin. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface LYUtils : NSObject

+ (BOOL)isFirstLaunchApp;

+ (NSString *)ipStringWithAddress:(uint32_t)addr;

+ (NSString *)formatedSpeed:(float)bytes elapsedMilli:(float)elapsed_milli;

@end

NS_ASSUME_NONNULL_END
