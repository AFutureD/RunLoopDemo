//
//  main.m
//  RunLoop Demo
//
//  Created by AFuture on 2022/5/11.
//

#import <Foundation/Foundation.h>

@interface RLS: NSObject

@property CFRunLoopRef workingRL;
@property CFRunLoopSourceRef source;
@property NSInteger signalCounts;
@property BOOL keepLoop;

@end

@implementation RLS

+ (instancetype)shared {
    static RLS *_instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _instance = [RLS new];
    });
    return _instance;
}

- (void)prepare {
    _keepLoop = YES;
    CFRunLoopAddSource(self.workingRL, self.source, kCFRunLoopDefaultMode);
}

- (void)shutdown {
    CFRunLoopRemoveSource(self.workingRL, self.source, kCFRunLoopDefaultMode);
    CFRunLoopStop(self.workingRL);
    _keepLoop = NO;
}

- (void)signal {
    if (self.signalCounts < 4) {
        CFRunLoopSourceSignal(self.source);
        self.signalCounts += 1;
    } else {
        CFRunLoopSourceInvalidate(self.source);
    }
}

@end

void ScheduleCallBack(void *info, CFRunLoopRef rl, CFRunLoopMode mode) {
    NSLog(@"Scheduled!");
}

void CancelCallBack(void *info, CFRunLoopRef rl, CFRunLoopMode mode) {
    NSLog(@"Canceled!");
    [[RLS shared] shutdown];
}

void PerformCallBack(void *info) {
    NSLog(@"Performed!");
    
    // `dispatch_after` will also create a `source` and add to runloop.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        NSLog(@"Try Signal");
        [[RLS shared] signal];
    });
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSLog(@"Start!");

        CFRunLoopSourceContext context = {
            0,
            NULL, NULL, NULL, NULL, NULL, NULL,
            ScheduleCallBack,
            CancelCallBack,
            PerformCallBack
        };

        CFRunLoopSourceRef source = CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &context);

        NSRunLoop *theRL = [NSRunLoop currentRunLoop];
        [RLS shared].workingRL = [theRL getCFRunLoop];
        [RLS shared].source = source;

        [[RLS shared] prepare];
        [[RLS shared] signal];

        while ([RLS shared].keepLoop && [theRL runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]]) {
            NSLog(@"Event Happened!");
        }

        NSLog(@"Finish!");
    }
    return 0;
}

