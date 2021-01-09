//
//  LKAlert.m
//  vpn
//
//  Created by Heller on 2016/11/23.
//  Copyright © 2016年 Heller. All rights reserved.
//

#import "LKAlert.h"

/**
 本地化显示字符串
 
 @param str 要本地化显示的字符串
 */
static inline NSString *LKLocalizedString(NSString *str){
    return NSLocalizedString(str, nil);
}

@implementation LKAlert

+ (void)alert:(NSString *)message
{
    UIAlertController * alertController = [UIAlertController alertControllerWithTitle:@""
                                                                              message:message
                                                                       preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction * okAction = [UIAlertAction actionWithTitle:LKLocalizedString(@"确定") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
    }];
    [alertController addAction:okAction];
    [[LKAlert rootViewController] presentViewController:alertController animated:YES completion:nil];
}

+ (void)alert:(NSString *)message okAction:(void (^)(UIAlertAction *action))handler
{
    UIAlertController * alertController = [UIAlertController alertControllerWithTitle:@""
                                                                              message:message
                                                                       preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction * okAction = [UIAlertAction actionWithTitle:LKLocalizedString(@"确定") style:UIAlertActionStyleDefault handler:handler];
    [alertController addAction:okAction];
    [[LKAlert rootViewController] presentViewController:alertController animated:YES completion:nil];
}

+ (void)alert:(NSString *)message okAction:(void (^)(UIAlertAction *action))okHandler cancleAction:(void (^)(UIAlertAction *action))cancleHandler
{
    UIAlertController * alertController = [UIAlertController alertControllerWithTitle:@""
                                                                              message:message
                                                                       preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction * cancleAction = [UIAlertAction actionWithTitle:LKLocalizedString(@"取消") style:UIAlertActionStyleDefault handler:cancleHandler];
    [alertController addAction:cancleAction];
    
    UIAlertAction * okAction = [UIAlertAction actionWithTitle:LKLocalizedString(@"确定") style:UIAlertActionStyleDefault handler:okHandler];
    [alertController addAction:okAction];
    
    [[LKAlert rootViewController] presentViewController:alertController animated:YES completion:nil];
}

+ (void)alert:(NSString *)message
      okTitle:(NSString *)okTitle
  cancelTitle:(NSString *)cancelTitle
     okAction:(void (^)(UIAlertAction *action))okHandler
 cancleAction:(void (^)(UIAlertAction *action))cancleHandler
{
    UIAlertController * alertController = [UIAlertController alertControllerWithTitle:message
                                                                              message:@""
                                                                       preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction * cancleAction = [UIAlertAction actionWithTitle:cancelTitle style:UIAlertActionStyleDefault handler:cancleHandler];
    [alertController addAction:cancleAction];
    
    UIAlertAction * okAction = [UIAlertAction actionWithTitle:okTitle style:UIAlertActionStyleDefault handler:okHandler];
    [alertController addAction:okAction];
    
    [[LKAlert rootViewController] presentViewController:alertController animated:YES completion:nil];
}

+ (void)showAlertViewTitle:(NSString *)title
                   message:(NSString *)message
           leftButtonTitle:(NSString *)leftButtonTitle
          rightButtonTitle:(NSString *)rightButtonTitle
          leftButtonAction:(void (^)(UIAlertAction *action))leftButtonHandler
         rightButtonAction:(void (^)(UIAlertAction *action))rightButtonHandler
{
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:title
                                                                             message:message
                                                                      preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *leftAction = [UIAlertAction actionWithTitle:leftButtonTitle style:UIAlertActionStyleDefault handler:leftButtonHandler];
    [alertController addAction:leftAction];
    
    UIAlertAction *rightAction = [UIAlertAction actionWithTitle:rightButtonTitle style:UIAlertActionStyleDefault handler:rightButtonHandler];
    [alertController addAction:rightAction];
    
    [[LKAlert rootViewController] presentViewController:alertController animated:YES completion:nil];
}

+ (void)alertNotUseWifiNetworkWithContinueAction:(void (^)(UIAlertAction *action))continueHandler cancleAction:(void (^)(UIAlertAction *action))cancleHandler
{
    UIAlertController * alertController = [UIAlertController alertControllerWithTitle:@"您正在使用移动网络播放视频，继续使用将产生流量费用！"
                                                                              message:@""
                                                                       preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction * cancleAction = [UIAlertAction actionWithTitle:LKLocalizedString(@"停止播放") style:UIAlertActionStyleDefault handler:cancleHandler];
    [alertController addAction:cancleAction];
    
    UIAlertAction * okAction = [UIAlertAction actionWithTitle:LKLocalizedString(@"继续播放") style:UIAlertActionStyleDefault handler:continueHandler];
    [alertController addAction:okAction];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [[LKAlert rootViewController] presentViewController:alertController animated:YES completion:nil];
    });
}

+ (UIViewController *)rootViewController
{
    UIViewController *ctrl = nil;
    UIApplication *app = [UIApplication sharedApplication];
    if (!ctrl) ctrl = app.keyWindow.rootViewController;
    if (!ctrl) ctrl = [app.windows.firstObject rootViewController];
    if (!ctrl) return nil;
    
    while (ctrl.presentedViewController) {
        ctrl = ctrl.presentedViewController;
    }
    
    if (!ctrl.view.window) return nil;
    return ctrl;
}

@end
