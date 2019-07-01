
#include <stdio.h>

#include <Cocoa/Cocoa.h>
#include <Metal/Metal.h>
#include <QuartzCore/CAMetalLayer.h>
#include <mach/mach_time.h>

#include "OSX_Keycodes.h"
#include "3DMaths.h"
#include "ShaderInterface.h"

///////////////////////////////////////////////////////////////////////
// Application / Window Delegate

@interface OSX_MainDelegate: NSObject<NSApplicationDelegate, NSWindowDelegate>
{
@public bool isRunning;
@public bool windowWasResized;
}
@end

@implementation OSX_MainDelegate
// NSApplicationDelegate methods
// NSWindowDelegate methods
- (NSSize)windowWillResize:(NSWindow*)window toSize:(NSSize)frameSize
{ 
    windowWasResized = true;
    return frameSize;
}
- (void)windowWillClose:(id)sender 
{ 
    isRunning = false; 
}
@end

// Application / Window Delegate
///////////////////////////////////////////////////////////////////////

double osxGetCurrentTimeInSeconds(mach_timebase_info_data_t tb)
{
    uint64_t timeInNanoSecs =  mach_absolute_time() * tb.numer / tb.denom;
    return (double)timeInNanoSecs * 1.0E-9;
}

int main(int argc, const char* argv[])
{
    NSApplication* app = [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    [NSApp activateIgnoringOtherApps:YES];

    // Create a Main Delegate to receive callbacks from App and Window
    OSX_MainDelegate* osxMainDelegate = [OSX_MainDelegate new];
    app.delegate = osxMainDelegate;

    [[NSFileManager defaultManager] changeCurrentDirectoryPath:[NSBundle mainBundle].bundlePath];

    // Create and open an NSWindow
    const float INITIAL_WIN_WIDTH = 1024;
    const float INITIAL_WIN_HEIGHT = 768;
    NSRect screenRect = [NSScreen mainScreen].frame;
    NSRect initialFrame = NSMakeRect((screenRect.size.width - INITIAL_WIN_WIDTH) * 0.5f,
                                    (screenRect.size.height - INITIAL_WIN_HEIGHT) * 0.5f,
                                    INITIAL_WIN_WIDTH, INITIAL_WIN_HEIGHT);

    NSWindowStyleMask windowStyleMask = (NSWindowStyleMaskTitled | NSWindowStyleMaskClosable 
                                        | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable);
    NSWindow* mainWindow = [[NSWindow alloc] initWithContentRect:initialFrame
                                             styleMask:windowStyleMask
                                             backing:NSBackingStoreBuffered
                                             defer:NO];

    mainWindow.backgroundColor = NSColor.purpleColor;
    mainWindow.contentAspectRatio = NSMakeSize(4,3);
    mainWindow.minSize = NSMakeSize(400,300);
    mainWindow.title = @"Metal Keyboard Input";
    mainWindow.delegate = osxMainDelegate;
    mainWindow.contentView.wantsLayer = YES;
    [mainWindow makeKeyAndOrderFront: nil];

    id<MTLDevice> mtlDevice = MTLCreateSystemDefaultDevice();
    printf("System default GPU: %s\n", mtlDevice.name.UTF8String);

    // Create CAMetalLayer and add to mainWindow
    CAMetalLayer* caMetalLayer = [CAMetalLayer new];
    caMetalLayer.frame = mainWindow.contentView.frame;
    caMetalLayer.device = mtlDevice;
    caMetalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    [mainWindow.contentView.layer addSublayer:caMetalLayer];

    [NSApp finishLaunching];
    
    // Load shaders
    NSError* error = nil;
    id<MTLLibrary> mtlLibrary = [mtlDevice newLibraryWithFile: @"shaders.metallib" error:&error];
    if (!mtlLibrary) {
        printf("Failed to load library. Error: %s\n", error.localizedDescription.UTF8String);
        return(1);
    }
    id<MTLFunction> vertFunc = [mtlLibrary newFunctionWithName:@"vert"];
    id<MTLFunction> fragFunc = [mtlLibrary newFunctionWithName:@"frag"];
    [mtlLibrary release];

    // Create Vertex Buffer
    float vertexData[] = { // x, y
        -0.5f,  0.5f, 
        -0.5f, -0.5f, 
         0.5f, -0.5f, 
        -0.5f,  0.5f, 
         0.5f, -0.5f, 
         0.5f,  0.5f     
    };

    id<MTLBuffer> quadVertexBuffer = [mtlDevice newBufferWithBytes:vertexData 
                                            length:sizeof(vertexData)
                                            options:MTLResourceOptionCPUCacheModeDefault];

    // Create Uniform Buffers
    const uint32_t MAX_NUM_FRAMES_IN_FLIGHT = 2;
    id<MTLBuffer> uniformBuffers[MAX_NUM_FRAMES_IN_FLIGHT];
    uniformBuffers[0] = [mtlDevice newBufferWithLength:sizeof(Uniforms)
                                   options:MTLResourceCPUCacheModeWriteCombined];
    uniformBuffers[1] = [mtlDevice newBufferWithLength:sizeof(Uniforms)
                                   options:MTLResourceCPUCacheModeWriteCombined];
    int currentUniformBufferIndex = 0;

    dispatch_semaphore_t uniformBufferSemaphore = dispatch_semaphore_create(MAX_NUM_FRAMES_IN_FLIGHT);

    // Create vertex descriptor
    MTLVertexDescriptor* vertDesc = [MTLVertexDescriptor new];
    vertDesc.attributes[VertexAttributeIndex_Position].format = MTLVertexFormatFloat2;
    vertDesc.attributes[VertexAttributeIndex_Position].offset = 0;
    vertDesc.attributes[VertexAttributeIndex_Position].bufferIndex = VertexBufferIndex_Attributes;
    vertDesc.layouts[VertexBufferIndex_Attributes].stride = 2 * sizeof(float);
    vertDesc.layouts[VertexBufferIndex_Attributes].stepRate = 1;
    vertDesc.layouts[VertexBufferIndex_Attributes].stepFunction = MTLVertexStepFunctionPerVertex;

    // Create Render Pipeline State
    MTLRenderPipelineDescriptor* mtlRenderPipelineDesc = [MTLRenderPipelineDescriptor new];
    mtlRenderPipelineDesc.vertexFunction = vertFunc;
    mtlRenderPipelineDesc.fragmentFunction = fragFunc;
    mtlRenderPipelineDesc.vertexDescriptor = vertDesc;
    mtlRenderPipelineDesc.colorAttachments[0].pixelFormat = caMetalLayer.pixelFormat;
    id<MTLRenderPipelineState> mtlRenderPipelineState = [mtlDevice newRenderPipelineStateWithDescriptor:mtlRenderPipelineDesc error:&error];
    if (!mtlRenderPipelineState) {
        printf("Failed to create pipeline state. Error: %s\n", error.localizedDescription.UTF8String);
        return(1);
    }

    [vertFunc release];
    [fragFunc release];
    [vertDesc release];
    [mtlRenderPipelineDesc release];

    id<MTLCommandQueue> mtlCommandQueue = [mtlDevice newCommandQueue];

    // Input
    enum GameAction {
        GameActionMoveUp,
        GameActionMoveDown,
        GameActionMoveLeft,
        GameActionMoveRight,
        GameActionCount
    };
    bool keyIsDown[GameActionCount] = {};

    // Game data
    float2 playerPos = {};

    // Timing
    mach_timebase_info_data_t machTimebaseInfoData;
    mach_timebase_info(&machTimebaseInfoData);
    assert(machTimebaseInfoData.denom != 0);
    double currentTimeInSeconds = osxGetCurrentTimeInSeconds(machTimebaseInfoData);

    // Main Loop
    osxMainDelegate->isRunning = true;
    while(osxMainDelegate->isRunning) 
    {
        dispatch_semaphore_wait(uniformBufferSemaphore, DISPATCH_TIME_FOREVER);

        double previousTimeInSeconds = currentTimeInSeconds;
        currentTimeInSeconds = osxGetCurrentTimeInSeconds(machTimebaseInfoData);
        float dt = currentTimeInSeconds - previousTimeInSeconds;

        if(dt > (1.f / 60.f))
            dt = (1.f / 60.f);

        @autoreleasepool 
        {
            while(NSEvent* event = [NSApp nextEventMatchingMask:NSEventMaskAny
                                        untilDate:nil
                                        inMode:NSDefaultRunLoopMode
                                        dequeue:YES])
            {
                switch(event.type)
                {
                    case NSEventTypeKeyDown:
                    case NSEventTypeKeyUp:
                    {
                        bool isDown = (event.type == NSEventTypeKeyDown);

                        // Move player with WASD or arrow keys
                        if(event.keyCode == kVK_ANSI_W)
                            keyIsDown[GameActionMoveUp] = isDown;
                        else if(event.keyCode == kVK_ANSI_A)
                            keyIsDown[GameActionMoveLeft] = isDown;
                        else if(event.keyCode == kVK_ANSI_S)
                            keyIsDown[GameActionMoveDown] = isDown;
                        else if(event.keyCode == kVK_ANSI_D)
                            keyIsDown[GameActionMoveRight] = isDown;
                        else if(event.keyCode == kVK_UpArrow)
                            keyIsDown[GameActionMoveUp] = isDown;
                        else if(event.keyCode == kVK_LeftArrow)
                            keyIsDown[GameActionMoveLeft] = isDown;
                        else if(event.keyCode == kVK_DownArrow)
                            keyIsDown[GameActionMoveDown] = isDown;
                        else if(event.keyCode == kVK_RightArrow)
                            keyIsDown[GameActionMoveRight] = isDown;

                        // Reset player with R key
                        else if(event.keyCode == kVK_ANSI_R)
                            playerPos = {};

                        else if(event.keyCode == kVK_Escape)
                            osxMainDelegate->isRunning = false;
                            
                        break;
                    }
                    default: [NSApp sendEvent:event];
                }
            }
        } // autoreleasepool

        if(osxMainDelegate->windowWasResized)
        {
            caMetalLayer.frame = mainWindow.contentView.frame;
            caMetalLayer.drawableSize = caMetalLayer.frame.size;
            osxMainDelegate->windowWasResized = false;
        }

        // Player movement logic
        const float playerSpeed = 1.5f;
        const float playerMoveAmount = playerSpeed * dt;

        if(keyIsDown[GameActionMoveUp])
            playerPos.y += playerMoveAmount;
        if(keyIsDown[GameActionMoveDown])
            playerPos.y -= playerMoveAmount;
        if(keyIsDown[GameActionMoveLeft])
            playerPos.x -= playerMoveAmount;
        if(keyIsDown[GameActionMoveRight])
            playerPos.x += playerMoveAmount;

        // Cycle player color
        float4 playerColor;
        const float colorCyclePeriod = 5.f; //in seconds
        const float colorCycleFreq = 2 * M_PI / colorCyclePeriod;
        playerColor.r = 0.5f * (sinf(colorCycleFreq * currentTimeInSeconds) + 1);
        playerColor.g = 1 - playerColor.r;
        playerColor.b = 0.f;
        playerColor.a = 1.f;

        // Update uniforms
        Uniforms uniforms;
        uniforms.pos = playerPos;
        uniforms.color = playerColor;
        memcpy(uniformBuffers[currentUniformBufferIndex].contents, &uniforms, sizeof(Uniforms));

        @autoreleasepool {
        id<CAMetalDrawable> caMetalDrawable = [caMetalLayer nextDrawable];
        if(!caMetalDrawable) continue;

        MTLRenderPassDescriptor* mtlRenderPassDescriptor = [MTLRenderPassDescriptor new];
        mtlRenderPassDescriptor.colorAttachments[0].texture = caMetalDrawable.texture;
        mtlRenderPassDescriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
        mtlRenderPassDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
        mtlRenderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0.1, 0.2, 0.6, 1.0);

        id<MTLCommandBuffer> mtlCommandBuffer = [mtlCommandQueue commandBuffer];

        id<MTLRenderCommandEncoder> mtlRenderCommandEncoder = 
            [mtlCommandBuffer renderCommandEncoderWithDescriptor:mtlRenderPassDescriptor];
        [mtlRenderPassDescriptor release];

        [mtlRenderCommandEncoder setViewport:(MTLViewport){0, 0, 
                                                           caMetalLayer.drawableSize.width,
                                                           caMetalLayer.drawableSize.height,
                                                           0, 1}];
        [mtlRenderCommandEncoder setRenderPipelineState:mtlRenderPipelineState];
        [mtlRenderCommandEncoder setVertexBuffer:quadVertexBuffer offset:0 atIndex:VertexBufferIndex_Attributes];
        [mtlRenderCommandEncoder setVertexBuffer:uniformBuffers[currentUniformBufferIndex] offset:0 atIndex:VertexBufferIndex_Uniforms];
        [mtlRenderCommandEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6];
        [mtlRenderCommandEncoder endEncoding];

        [mtlCommandBuffer presentDrawable:caMetalDrawable];

        [mtlCommandBuffer addCompletedHandler:^(id<MTLCommandBuffer> mtlCommandBuffer) {
            dispatch_semaphore_signal(uniformBufferSemaphore);
        }];

        [mtlCommandBuffer commit];

        } // autoreleasepool

        currentUniformBufferIndex = (currentUniformBufferIndex+1) % MAX_NUM_FRAMES_IN_FLIGHT;
    }
    return 0;
}
