#pragma once
#import <UIkit/UIKit.h>

@interface AlignmentEntry : NSObject

@property(nonatomic, assign) NSRange range;
@property(nonatomic, assign) NSTextAlignment alignment;
@property(nonatomic, assign) NSInteger indentLevel;
@property(nonatomic, assign) BOOL bullet;

@end
