//
//  LYStreamingUDPSocket.h
//  LFLiveKit-ReplayKit
//
//  Created by RoyLei on 1/8/21.
//

#import "LFStreamSocket.h"

NS_ASSUME_NONNULL_BEGIN

@interface LYStreamingUDPSocket : NSObject<LFStreamSocket>

#pragma mark - Initializer
///=============================================================================
/// @name Initializer
///=============================================================================
- (nullable instancetype)init UNAVAILABLE_ATTRIBUTE;
+ (nullable instancetype)new UNAVAILABLE_ATTRIBUTE;

@end

NS_ASSUME_NONNULL_END
