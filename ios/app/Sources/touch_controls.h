#pragma once
#import <UIKit/UIKit.h>
#import <stdint.h>

// Exact controller field ordering used by games/totk/runtime/runtime.h.
// Keep this interface independent of runtime.h so a game-free app can compile.
typedef struct {
    uint64_t buttons;
    int32_t lx, ly, rx, ry;
    int connected;
} IOSPadState;

@interface TOTKTouchControls : UIView
@property (nonatomic, copy) void (^onStateChanged)(IOSPadState state);
- (void)resetInput;
@end
