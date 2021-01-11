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

+ (BOOL)isFirstLaunchApp
{
    BOOL ret = [NSUserDefaults.standardUserDefaults boolForKey:kAppFirstLaunch];
    if (ret == NO) {
        [NSUserDefaults.standardUserDefaults setBool:YES forKey:kAppFirstLaunch];
    }
    return ret;
}

+ (NSString *)ipStringWithAddress:(uint32_t)addr
{
    uint32_t ip = addr;
    struct in_addr addrST = *(struct in_addr *)&ip;
    NSString *ipString = [NSString stringWithFormat: @"%s",inet_ntoa(addrST)];
    
    return ipString;
}

@end
