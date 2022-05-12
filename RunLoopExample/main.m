//
//  main.m
//  RunLoop Demo
//
//  Created by AFuture on 2022/5/11.
//

#import <Foundation/Foundation.h>

#pragma mark - RunLoop Source Manager

@interface RLS: NSObject

@property (nonatomic) CFRunLoopTimerRef timer;
@property (nonatomic) CFRunLoopObserverRef observer;

@property (nonatomic) CFMachPortRef port;
@property (nonatomic) CFRunLoopSourceRef source1;

@property (nonatomic) CFRunLoopSourceRef source0;
@property (nonatomic) NSInteger sourcePerformCnt;

@property (nonatomic) BOOL keepLoop;
@property (nonatomic) CFRunLoopRef workingRL;

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

#pragma mark - RLS Life

- (void)start {
    _keepLoop = YES;
    // timer
    CFRunLoopAddTimer(self.workingRL, self.timer, kCFRunLoopDefaultMode);
    
    // Observer
    CFRunLoopAddObserver(self.workingRL, self.observer, kCFRunLoopDefaultMode);
    
    // Source0
    CFRunLoopAddSource(self.workingRL, self.source0, kCFRunLoopDefaultMode);
    
    // Source1
    CFRunLoopAddSource(self.workingRL, self.source1, kCFRunLoopDefaultMode);
}

- (void)stop {
    CFRunLoopTimerInvalidate(self.timer);
    CFRunLoopSourceInvalidate(self.source0);
    CFRunLoopObserverInvalidate(self.observer);
}

- (void)shutdown {
    CFRunLoopSourceInvalidate(self.source1);
    
    CFRunLoopRemoveTimer(self.workingRL, self.timer, kCFRunLoopDefaultMode);
    CFRunLoopRemoveSource(self.workingRL, self.source0, kCFRunLoopDefaultMode);
    CFRunLoopRemoveSource(self.workingRL, self.source1, kCFRunLoopDefaultMode);
    CFRunLoopRemoveObserver(self.workingRL, self.observer, kCFRunLoopDefaultMode);
    CFRunLoopStop(self.workingRL);
    _keepLoop = NO;
}

#pragma mark - RLS Actions

- (void)checkTimer {
    [self signalSource0];
}

- (void)signalSource0 {
    CFRunLoopSourceSignal(self.source0);
}

- (void)signalSource1 {
    
    mach_port_t port = CFMachPortGetPort(self.port);
    
    // Construct our message.
    struct {
        mach_msg_header_t header;
        char some_text[10];
        int some_number;
    } message;
    
    message.header.msgh_bits        = MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND, 0);
    message.header.msgh_remote_port = port;
    message.header.msgh_local_port  = MACH_PORT_NULL;
    message.some_number = 10007;    // random info.
    strncpy(message.some_text, "Hello", sizeof(message.some_text));
    
    // Send the message.
    mach_msg_return_t kr = mach_msg(
        &message.header,            // Same as (mach_msg_header_t *) &message.
        MACH_SEND_MSG,              // Options. We're sending a message.
        sizeof(message),            // Size of the message being sent.
        0,                          // Size of the buffer for receiving.
        MACH_PORT_NULL,             // A port to receive a message on, if receiving.
        MACH_MSG_TIMEOUT_NONE,
        MACH_PORT_NULL              // Port for the kernel to send notifications about this message to.
    );
    
    if (kr != KERN_SUCCESS) {
        NSLog(@"[Source1] mach_msg() failed with code 0x%x\n", kr);
    }
}

#pragma mark - RLS Getter

- (void)setSourcePerformCnt:(NSInteger)sourcePerformCnt {
    if (_sourcePerformCnt >= 3) {
        [self stop];
        return;
    }
    _sourcePerformCnt = sourcePerformCnt;
}

@end

#pragma mark - RunLoop Source Callback

void ScheduleCallBack(void *info, CFRunLoopRef rl, CFRunLoopMode mode) {
    NSLog(@"[Source0 ] Scheduled!");
}

void CancelCallBack(void *info, CFRunLoopRef rl, CFRunLoopMode mode) {
    NSLog(@"[Source0 ] Canceled!");
    [[RLS shared] signalSource1];
}

void PerformCallBack(void *info) {
    NSLog(@"[Source0 ] Performed!");
    [RLS shared].sourcePerformCnt += 1;
}

void machPortCallback(CFMachPortRef port, void *msg, CFIndex size, void *info) {
    NSLog(@"[Source1 ] Performed!");
    [[RLS shared] shutdown];
}


#pragma mark - RunLoop Observer

NSString *activityDescription(CFRunLoopActivity activity) {
    NSString *description;
    switch (activity) {
        case kCFRunLoopEntry: {
            description = @"kCFRunLoopEntry";
        }   break;
            
        case kCFRunLoopBeforeTimers: {
            description = @"kCFRunLoopBeforeTimers";
        }   break;
    
        case kCFRunLoopBeforeSources: {
            description = @"kCFRunLoopBeforeSources";
        }   break;

        case kCFRunLoopBeforeWaiting: {
            description = @"kCFRunLoopBeforeWaiting";
        }   break;

        case kCFRunLoopAfterWaiting: {
            description = @"kCFRunLoopAfterWaiting";
        }   break;

        case kCFRunLoopExit: {
            description = @"kCFRunLoopExit";
        }   break;

        default:
            break;
    }
    return description;
}

void currentRunLoopObserver(CFRunLoopObserverRef observer, CFRunLoopActivity activity, void *info) {
    NSLog(@"[Activity] %@", activityDescription(activity));
}

#pragma mark - Main

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        
        // Observer
        // CFRunLoopObserverRef observer = CFRunLoopObserverCreate(kCFAllocatorDefault, kCFRunLoopAllActivities, YES, 0, &currentRunLoopObserver, NULL);
        CFRunLoopObserverRef observerWithBlock = CFRunLoopObserverCreateWithHandler(kCFAllocatorDefault, kCFRunLoopAllActivities,  YES, 0, ^(CFRunLoopObserverRef observer, CFRunLoopActivity activity) {
            NSLog(@"[Activity] %@", activityDescription(activity));
        });
        
        // Source0
        CFRunLoopSourceContext source0Context = {
            0,
            NULL, NULL, NULL, NULL, NULL, NULL,
            ScheduleCallBack,
            CancelCallBack,
            PerformCallBack
        };
        CFRunLoopSourceRef source0 = CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &source0Context);
        
        // Source1
        CFMachPortContext portContext = {
            0, NULL, NULL, NULL, NULL
        };
        
        CFMachPortRef port = CFMachPortCreate(kCFAllocatorDefault, &machPortCallback, &portContext, NULL);
        CFRunLoopSourceRef source1 = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0);
        
        // timer
        CFRunLoopTimerRef timer = CFRunLoopTimerCreateWithHandler(kCFAllocatorDefault, 0, 1, 0, 0, ^(CFRunLoopTimerRef timer) {
            CFAbsoluteTime timestamp = CFRunLoopTimerGetNextFireDate(timer);
            NSLog(@"[Timer   ] next at %f", timestamp);
            [[RLS shared] checkTimer];
        });
        
        // configure
        [[RLS shared] setPort:port];
        [[RLS shared] setTimer:timer];
        [[RLS shared] setSource0:source0];
        [[RLS shared] setSource1:source1];
        [[RLS shared] setObserver:observerWithBlock];
        [[RLS shared] setWorkingRL:CFRunLoopGetCurrent()];
        // [[RLS shared] setObserver:observer]; // OR
        
        [[RLS shared] start];
        
        NSLog(@"[RunLoop ] Start!");
        
        while ([RLS shared].keepLoop && [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]]) {
            NSLog(@"[RunLoop ] One Loop!");
        }

        NSLog(@"[RunLoop ] Finish!");
    }
    return 0;
}
