// Copyright contributors. Game-free iOS shell; not a playable TotK build.
// The real runtime frontend already lives at games/totk/runtime/frontend_ios.m.
// This file intentionally does NOT link or execute game code.
#import <UIKit/UIKit.h>
#import <QuartzCore/CAMetalLayer.h>
#import <Metal/Metal.h>
#import <GameController/GameController.h>
#import "touch_controls.h"

@interface TOTKMetalHostView : UIView
@end
@implementation TOTKMetalHostView
+ (Class)layerClass { return [CAMetalLayer class]; }
@end

@interface TOTKBootstrapController : UIViewController
@end

@implementation TOTKBootstrapController {
    id<MTLDevice> _device;
    id<MTLCommandQueue> _queue;
    CAMetalLayer *_metalLayer;
    CADisplayLink *_displayLink;
    UILabel *_headline;
    UILabel *_details;
    UILabel *_inputStatus;
    TOTKTouchControls *_touchControls;
    IOSPadState _touchState;
    NSUInteger _frames;
}

- (void)loadView {
    self.view = [[TOTKMetalHostView alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.view.backgroundColor = [UIColor colorWithRed:0.03 green:0.06 blue:0.09 alpha:1.0];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _device = MTLCreateSystemDefaultDevice();
    _queue = [_device newCommandQueue];
    _metalLayer = (CAMetalLayer *)self.view.layer;
    _metalLayer.device = _device;
    _metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    _metalLayer.framebufferOnly = YES;
    _metalLayer.opaque = YES;

    _headline = [[UILabel alloc] initWithFrame:CGRectZero];
    _headline.text = @"iOSNativeGames";
    _headline.font = [UIFont systemFontOfSize:26 weight:UIFontWeightBold];
    _headline.textAlignment = NSTextAlignmentCenter;
    _headline.textColor = UIColor.whiteColor;
    [self.view addSubview:_headline];

    _details = [[UILabel alloc] initWithFrame:CGRectZero];
    _details.numberOfLines = 0;
    _details.textAlignment = NSTextAlignmentCenter;
    _details.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    _details.textColor = [UIColor colorWithWhite:0.78 alpha:1.0];
    _details.text = _device ?
        @"Metal device ready • unsigned iOS bootstrap\nTotK runtime and game data are NOT linked" :
        @"No Metal device available • cannot initialize renderer";
    [self.view addSubview:_details];

    _inputStatus = [[UILabel alloc] initWithFrame:CGRectZero];
    _inputStatus.textAlignment = NSTextAlignmentCenter;
    _inputStatus.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    _inputStatus.textColor = [UIColor colorWithWhite:0.75 alpha:1.0];
    [self.view addSubview:_inputStatus];

    _touchControls = [[TOTKTouchControls alloc] initWithFrame:self.view.bounds];
    _touchControls.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    __weak typeof(self) weakSelf = self;
    _touchControls.onStateChanged = ^(IOSPadState state) {
        TOTKBootstrapController *strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf->_touchState = state;
        [strongSelf refreshInputStatus];
        // Integration milestone: pass state to runtime_touch_pad_set when the
        // signed guest-code runtime is separately linked and device-tested.
    };
    [self.view addSubview:_touchControls];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(refreshInputStatus)
                                                 name:GCControllerDidConnectNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(refreshInputStatus)
                                                 name:GCControllerDidDisconnectNotification object:nil];
    [GCController startWirelessControllerDiscoveryWithCompletionHandler:nil];
    [self refreshInputStatus];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGSize s = self.view.bounds.size;
    CGFloat scale = self.view.window.screen.nativeScale;
    if (scale <= 0) scale = UIScreen.mainScreen.nativeScale;
    _metalLayer.drawableSize = CGSizeMake(MAX(1, round(s.width * scale)), MAX(1, round(s.height * scale)));
    _headline.frame = CGRectMake(20, s.height * 0.23, s.width - 40, 40);
    _details.frame = CGRectMake(18, CGRectGetMaxY(_headline.frame) + 7, s.width - 36, 54);
    _inputStatus.frame = CGRectMake(15, s.height * 0.63, s.width - 30, 22);
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (!_displayLink && _queue) {
        _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(drawFrame:)];
        _displayLink.preferredFramesPerSecond = 30;
        [_displayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [_displayLink invalidate];
    _displayLink = nil;
    [_touchControls resetInput];
}

- (void)refreshInputStatus {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self refreshInputStatus]; });
        return;
    }
    _inputStatus.text = [NSString stringWithFormat:
        @"Touch: 0x%04llx  Stick: (%d,%d)  Controllers: %lu",
        (unsigned long long)_touchState.buttons, _touchState.lx, _touchState.ly,
        (unsigned long)[GCController controllers].count];
}

- (void)drawFrame:(CADisplayLink *)link {
    (void)link;
    if (!_queue || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
    id<CAMetalDrawable> drawable = [_metalLayer nextDrawable];
    if (!drawable) return;
    MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture = drawable.texture;
    pass.colorAttachments[0].loadAction = MTLLoadActionClear;
    pass.colorAttachments[0].storeAction = MTLStoreActionStore;
    pass.colorAttachments[0].clearColor = MTLClearColorMake(0.023, 0.048, 0.076, 1.0);
    id<MTLCommandBuffer> command = [_queue commandBuffer];
    id<MTLRenderCommandEncoder> encoder = [command renderCommandEncoderWithDescriptor:pass];
    [encoder endEncoding];
    [command presentDrawable:drawable];
    [command commit];
    _frames++;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskLandscape;
}
- (BOOL)prefersStatusBarHidden { return YES; }
- (BOOL)prefersHomeIndicatorAutoHidden { return YES; }
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
@end

@interface TOTKBootstrapDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end
@implementation TOTKBootstrapDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    (void)application; (void)options;
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [[TOTKBootstrapController alloc] init];
    [self.window makeKeyAndVisible];
    return YES;
}
- (void)applicationWillResignActive:(UIApplication *)application {
    (void)application;
    [((TOTKBootstrapController *)self.window.rootViewController)->_touchControls resetInput];
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(TOTKBootstrapDelegate.class));
    }
}
