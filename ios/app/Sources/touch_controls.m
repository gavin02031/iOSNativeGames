// Game-independent iPhone controller prototype. Button bit assignments must
// match games/totk/runtime/gamepad.m (Switch FullKey state).
#import "touch_controls.h"
#import <math.h>

@interface TOTKAnalogStick : UIView
@property (nonatomic, copy) void (^onChange)(float x, float y);
- (void)reset;
@end

@implementation TOTKAnalogStick {
    UIView *_thumb;
    UITouch *_activeTouch;
}
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.multipleTouchEnabled = YES;
        self.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.11];
        self.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.40].CGColor;
        self.layer.borderWidth = 1.5;
        _thumb = [[UIView alloc] initWithFrame:CGRectZero];
        _thumb.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.46];
        _thumb.layer.borderColor = [UIColor whiteColor].CGColor;
        _thumb.layer.borderWidth = 1.0;
        [self addSubview:_thumb];
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat size = MIN(self.bounds.size.width, self.bounds.size.height);
    self.layer.cornerRadius = size / 2;
    _thumb.bounds = CGRectMake(0, 0, size * 0.40, size * 0.40);
    _thumb.layer.cornerRadius = size * 0.20;
    if (!_activeTouch) _thumb.center = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
}
- (void)moveTouch:(UITouch *)touch {
    CGPoint p = [touch locationInView:self];
    CGFloat cx = CGRectGetMidX(self.bounds), cy = CGRectGetMidY(self.bounds);
    CGFloat radius = MAX(1, MIN(self.bounds.size.width, self.bounds.size.height) * 0.36);
    CGFloat dx = p.x - cx, dy = p.y - cy;
    CGFloat length = hypot(dx, dy);
    if (length > radius) { dx *= radius / length; dy *= radius / length; }
    _thumb.center = CGPointMake(cx + dx, cy + dy);
    if (self.onChange) self.onChange((float)(dx / radius), (float)(-dy / radius));
}
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    (void)event;
    if (_activeTouch) return;
    _activeTouch = touches.anyObject;
    if (_activeTouch) [self moveTouch:_activeTouch];
}
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    (void)event;
    if (_activeTouch && [touches containsObject:_activeTouch]) [self moveTouch:_activeTouch];
}
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    (void)event;
    if (_activeTouch && [touches containsObject:_activeTouch]) [self reset];
}
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self touchesEnded:touches withEvent:event];
}
- (void)reset {
    _activeTouch = nil;
    _thumb.center = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
    if (self.onChange) self.onChange(0, 0);
}
@end

@implementation TOTKTouchControls {
    IOSPadState _state;
    NSMutableArray<UIButton *> *_buttons;
    TOTKAnalogStick *_leftStick;
    TOTKAnalogStick *_rightStick;
}
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.multipleTouchEnabled = YES;
        self.backgroundColor = UIColor.clearColor;
        _buttons = [NSMutableArray arrayWithCapacity:16];
        _state.connected = 1;

        // Native gamepad.m button mapping: A/B/X/Y, L3/R3, L/R, ZL/ZR,
        // Plus/Minus, left/up/right/down d-pad.
        NSArray<NSString *> *labels = @[@"A", @"B", @"X", @"Y", @"L3", @"R3",
                                         @"L", @"R", @"ZL", @"ZR", @"+", @"−",
                                         @"◀", @"▲", @"▶", @"▼"];
        for (NSUInteger bit = 0; bit < labels.count; bit++) {
            UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
            button.tag = (NSInteger)bit;
            button.backgroundColor = [UIColor colorWithRed:0.18 green:0.23 blue:0.31 alpha:0.81];
            button.layer.cornerRadius = 22;
            button.layer.borderWidth = 1.1;
            button.layer.borderColor = [UIColor colorWithWhite:0.85 alpha:0.48].CGColor;
            button.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
            [button setTitle:labels[bit] forState:UIControlStateNormal];
            [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
            button.accessibilityLabel = labels[bit];
            [button addTarget:self action:@selector(buttonDown:) forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
            [button addTarget:self action:@selector(buttonUp:) forControlEvents:UIControlEventTouchUpInside |
                 UIControlEventTouchUpOutside | UIControlEventTouchCancel | UIControlEventTouchDragExit];
            [_buttons addObject:button];
            [self addSubview:button];
        }
        _leftStick = [[TOTKAnalogStick alloc] initWithFrame:CGRectZero];
        _rightStick = [[TOTKAnalogStick alloc] initWithFrame:CGRectZero];
        _leftStick.accessibilityLabel = @"Move Link";
        _rightStick.accessibilityLabel = @"Look around";
        __weak typeof(self) weakSelf = self;
        _leftStick.onChange = ^(float x, float y) {
            TOTKTouchControls *strongSelf = weakSelf;
            if (!strongSelf) return;
            strongSelf->_state.lx = (int32_t)lroundf(x * 32767);
            strongSelf->_state.ly = (int32_t)lroundf(y * 32767);
            [strongSelf publish];
        };
        _rightStick.onChange = ^(float x, float y) {
            TOTKTouchControls *strongSelf = weakSelf;
            if (!strongSelf) return;
            strongSelf->_state.rx = (int32_t)lroundf(x * 32767);
            strongSelf->_state.ry = (int32_t)lroundf(y * 32767);
            [strongSelf publish];
        };
        [self addSubview:_leftStick];
        [self addSubview:_rightStick];
    }
    return self;
}
- (void)publish {
    _state.connected = 1;
    if (self.onStateChanged) self.onStateChanged(_state);
}
- (void)buttonDown:(UIButton *)button {
    _state.buttons |= UINT64_C(1) << (unsigned)button.tag;
    button.backgroundColor = [UIColor colorWithRed:0.34 green:0.50 blue:0.59 alpha:0.95];
    [self publish];
}
- (void)buttonUp:(UIButton *)button {
    _state.buttons &= ~(UINT64_C(1) << (unsigned)button.tag);
    button.backgroundColor = [UIColor colorWithRed:0.18 green:0.23 blue:0.31 alpha:0.81];
    [self publish];
}
- (void)resetInput {
    _state.buttons = 0;
    for (UIButton *button in _buttons) {
        button.backgroundColor = [UIColor colorWithRed:0.18 green:0.23 blue:0.31 alpha:0.81];
    }
    [_leftStick reset];
    [_rightStick reset];
    [self publish];
}
- (void)setButton:(NSUInteger)bit center:(CGPoint)center size:(CGFloat)size {
    UIButton *button = _buttons[bit];
    button.bounds = CGRectMake(0, 0, size, size);
    button.center = center;
    button.layer.cornerRadius = size / 2;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width, h = self.bounds.size.height;
    CGFloat insetL = MAX(16, self.safeAreaInsets.left + 8);
    CGFloat insetR = MAX(16, self.safeAreaInsets.right + 8);
    CGFloat small = (w < 720 ? 36 : 42);
    CGFloat bottom = h - MAX(14, self.safeAreaInsets.bottom + 10);
    CGFloat stick = MIN(112, MAX(86, h * 0.30));

    _leftStick.bounds = CGRectMake(0, 0, stick, stick);
    _leftStick.center = CGPointMake(insetL + stick * 0.61, bottom - stick * 0.65);
    _leftStick.layer.cornerRadius = stick / 2;

    _rightStick.bounds = CGRectMake(0, 0, stick, stick);
    _rightStick.center = CGPointMake(w - insetR - stick * 2.05, bottom - stick * 0.65);
    _rightStick.layer.cornerRadius = stick / 2;

    CGFloat bx = w - insetR - 68;
    CGFloat by = bottom - 86;
    [self setButton:0 center:CGPointMake(bx + 47, by) size:small];      // A
    [self setButton:1 center:CGPointMake(bx, by + 43) size:small];      // B
    [self setButton:2 center:CGPointMake(bx, by - 43) size:small];      // X
    [self setButton:3 center:CGPointMake(bx - 47, by) size:small];      // Y

    CGFloat dpx = insetL + stick + 82, dpy = bottom - 66;
    [self setButton:12 center:CGPointMake(dpx - 37, dpy) size:small];   // Left
    [self setButton:13 center:CGPointMake(dpx, dpy - 37) size:small];   // Up
    [self setButton:14 center:CGPointMake(dpx + 37, dpy) size:small];   // Right
    [self setButton:15 center:CGPointMake(dpx, dpy + 37) size:small];   // Down

    CGFloat top = MAX(26, self.safeAreaInsets.top + 10);
    [self setButton:6 center:CGPointMake(insetL + 42, top + 23) size:small]; // L
    [self setButton:8 center:CGPointMake(insetL + 93, top + 23) size:small]; // ZL
    [self setButton:7 center:CGPointMake(w - insetR - 42, top + 23) size:small]; // R
    [self setButton:9 center:CGPointMake(w - insetR - 93, top + 23) size:small]; // ZR
    [self setButton:10 center:CGPointMake(w * 0.53, top + 17) size:32]; // Plus
    [self setButton:11 center:CGPointMake(w * 0.47, top + 17) size:32]; // Minus
    [self setButton:4 center:CGPointMake(insetL + 32, bottom - stick - 31) size:30]; // L3
    [self setButton:5 center:CGPointMake(w - insetR - stick * 2.55, bottom - stick - 31) size:30]; // R3
}
@end
