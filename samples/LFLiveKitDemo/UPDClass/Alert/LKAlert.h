//
//  LKAlert.h
//  vpn
//
//  Created by Heller on 2016/11/23.
//  Copyright © 2016年 Heller. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface LKAlert : NSObject

/**
 提示对话框

 @param message 提示文本,按钮是"确定"
 */
+ (void)alert:(NSString *)message;

+ (void)alert:(NSString *)message okAction:(void (^)(UIAlertAction *action))handler;

+ (void)alert:(NSString *)message
     okAction:(void (^)(UIAlertAction *action))okHandler
 cancleAction:(void (^)(UIAlertAction *action))cancleHandler;

+ (void)alert:(NSString *)message
      okTitle:(NSString *)okTitle
  cancelTitle:(NSString *)cancelTitle
     okAction:(void (^)(UIAlertAction *action))okHandler
 cancleAction:(void (^)(UIAlertAction *action))cancleHandler;

+ (void)showAlertViewTitle:(NSString *)title
                   message:(NSString *)message
           leftButtonTitle:(NSString *)leftButtonTitle
          rightButtonTitle:(NSString *)rightButtonTitle
          leftButtonAction:(void (^)(UIAlertAction *action))leftButtonHandler
         rightButtonAction:(void (^)(UIAlertAction *action))rightButtonHandler;

/**
 警告非Wifi网络的时候

 @param continueHandler 继续播放动作
 @param cancleHandler   停止播放动作
 */
+ (void)alertNotUseWifiNetworkWithContinueAction:(void (^)(UIAlertAction *action))continueHandler
                                    cancleAction:(void (^)(UIAlertAction *action))cancleHandler;

@end
