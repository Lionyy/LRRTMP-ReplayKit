//
//  LYUtils.m
//  LFLiveKitDemo
//
//  Created by RoyLei on 1/11/21.
//  Copyright © 2021 admin. All rights reserved.
//

#import "LYUtils.h"
#import <arpa/inet.h>

NSString * const kAppFirstLaunch = @"LY_FIRST_LAUNCH_APP";

@implementation LYUtils

+ (BOOL)isFirstLaunchApp {
    BOOL ret = [NSUserDefaults.standardUserDefaults boolForKey:kAppFirstLaunch];
    if (ret == NO) {
        [NSUserDefaults.standardUserDefaults setBool:YES forKey:kAppFirstLaunch];
    }
    return ret;
}

+ (NSString *)ipStringWithAddress:(uint32_t)addr {
    uint32_t ip = addr;
    struct in_addr addrST = *(struct in_addr *)&ip;
    NSString *ipString = [NSString stringWithFormat: @"%s",inet_ntoa(addrST)];
    
    return ipString;
}

+ (NSString *)formatedSpeed:(float)bytes elapsedMilli:(float)elapsed_milli {
    if (elapsed_milli <= 0) {
        return @"N/A";
    }
    if (bytes <= 0) {
        return @"0 KB/s";
    }
    float bytes_per_sec = ((float)bytes) * 1000.f /  elapsed_milli;
    if (bytes_per_sec >= 1000 * 1000) {
        return [NSString stringWithFormat:@"%.2f MB/s", ((float)bytes_per_sec) / 1000 / 1000];
    } else if (bytes_per_sec >= 1000) {
        return [NSString stringWithFormat:@"%.1f KB/s", ((float)bytes_per_sec) / 1000];
    } else {
        return [NSString stringWithFormat:@"%ld B/s", (long)bytes_per_sec];
    }
}

@end
