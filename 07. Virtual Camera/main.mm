
#include <stdio.h>

#include <Cocoa/Cocoa.h>
#include <Metal/Metal.h>
#include <QuartzCore/CAMetalLayer.h>
#include <mach/mach_time.h>

#include "OSX_Keycodes.h"
#include "3DMaths.h"
#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"

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
    mainWindow.title = @"Virtual Camera";
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
    float vertexData[] = { // x, y, u, v
        -0.5f,  0.5f, 0.f, 0.f,
        -0.5f, -0.5f, 0.f, 1.f,
         0.5f, -0.5f, 1.f, 1.f,
        -0.5f,  0.5f, 0.f, 0.f,
         0.5f, -0.5f, 1.f, 1.f,
         0.5f,  0.5f, 1.f, 0.f
    };

    id<MTLBuffer> quadVertexBuffer = [mtlDevice newBufferWithBytes:vertexData 
                                            length:sizeof(vertexData)
                                            options:MTLResourceOptionCPUCacheModeDefault];

    // Load Image
    int texWidth, texHeight, texNumChannels;
    int texForceNumChannels = 4;
    unsigned char* testTextureBytes = stbi_load("testTexture.png", &texWidth, &texHeight,
                                                &texNumChannels, texForceNumChannels);
    int texBytesPerRow = 4 * texWidth;

    // Create Texture
    MTLTextureDescriptor* mtlTextureDescriptor =
        [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                              width:texWidth
                              height:texHeight
                              mipmapped:NO];
    id<MTLTexture> mtlTexture = [mtlDevice newTextureWithDescriptor:mtlTextureDescriptor];
    [mtlTextureDescriptor release];

    // Copy loaded image into MTLTextureObject
    [mtlTexture replaceRegion:MTLRegionMake2D(0,0,texWidth,texHeight)
                mipmapLevel:0
                withBytes:testTextureBytes
                bytesPerRow:texBytesPerRow];

    stbi_image_free(testTextureBytes);

    // Create a Sampler State
    MTLSamplerDescriptor* mtlSamplerDesc = [MTLSamplerDescriptor new];
    mtlSamplerDesc.minFilter = MTLSamplerMinMagFilterLinear;
    mtlSamplerDesc.magFilter = MTLSamplerMinMagFilterLinear;
    id<MTLSamplerState> mtlSamplerState = [mtlDevice newSamplerStateWithDescriptor:mtlSamplerDesc];
    [mtlSamplerDesc release];

    // Create Uniform Buffers
    const uint32_t MAX_NUM_FRAMES_IN_FLIGHT = 2;
    id<MTLBuffer> uniformBuffers[MAX_NUM_FRAMES_IN_FLIGHT];
    uniformBuffers[0] = [mtlDevice newBufferWithLength:sizeof(float4x4)
                                   options:MTLResourceCPUCacheModeWriteCombined];
    uniformBuffers[1] = [mtlDevice newBufferWithLength:sizeof(float4x4)
                                   options:MTLResourceCPUCacheModeWriteCombined];
    int currentUniformBufferIndex = 0;

    dispatch_semaphore_t uniformBufferSemaphore = dispatch_semaphore_create(MAX_NUM_FRAMES_IN_FLIGHT);

    // Create vertex descriptor
    MTLVertexDescriptor* vertDesc = [MTLVertexDescriptor new];
    vertDesc.attributes[VertexAttributeIndex_Position].format = MTLVertexFormatFloat2;
    vertDesc.attributes[VertexAttributeIndex_Position].offset = 0;
    vertDesc.attributes[VertexAttributeIndex_Position].bufferIndex = VertexBufferIndex_Attributes;
    vertDesc.attributes[VertexAttributeIndex_TexCoords].format = MTLVertexFormatFloat2;
    vertDesc.attributes[VertexAttributeIndex_TexCoords].offset = 2 * sizeof(float);
    vertDesc.attributes[VertexAttributeIndex_TexCoords].bufferIndex = VertexBufferIndex_Attributes;
    vertDesc.layouts[VertexBufferIndex_Attributes].stride = 4 * sizeof(float);
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
        GameActionMoveCamFwd,
        GameActionMoveCamBack,
        GameActionMoveCamLeft,
        GameActionMoveCamRight,
        GameActionTurnCamLeft,
        GameActionTurnCamRight,
        GameActionLookUp,
        GameActionLookDown,
        GameActionRaiseCam,
        GameActionLowerCam,
        GameActionCount
    };
    bool keyIsDown[GameActionCount] = {};

    // Camera
    float3 cameraPos = {0, 0, 2};
    float3 cameraFwd = {0, 0, -1};
    float cameraPitch = 0.f;
    float cameraYaw = 0.f;

    // NOTE: We don't need to recalculate this because we lock the window's aspect ratio
    float4x4 perspectiveMat = makePerspectiveMat(4.f/3.f, degreesToRadians(84), 0.1f, 1000.f);

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

                        // Move camera with WASD or arrow keys
                        if(event.keyCode == kVK_ANSI_W)
                            keyIsDown[GameActionMoveCamFwd] = isDown;
                        else if(event.keyCode == kVK_ANSI_A)
                            keyIsDown[GameActionMoveCamLeft] = isDown;
                        else if(event.keyCode == kVK_ANSI_S)
                            keyIsDown[GameActionMoveCamBack] = isDown;
                        else if(event.keyCode == kVK_ANSI_D)
                            keyIsDown[GameActionMoveCamRight] = isDown;
                        else if(event.keyCode == kVK_UpArrow)
                            keyIsDown[GameActionLookUp] = isDown;
                        else if(event.keyCode == kVK_DownArrow)
                            keyIsDown[GameActionLookDown] = isDown;
                        else if(event.keyCode == kVK_LeftArrow)
                            keyIsDown[GameActionTurnCamLeft] = isDown;
                        else if(event.keyCode == kVK_RightArrow)
                            keyIsDown[GameActionTurnCamRight] = isDown;
                        else if(event.keyCode == kVK_ANSI_E)
                            keyIsDown[GameActionRaiseCam] = isDown;
                        else if(event.keyCode == kVK_ANSI_Q)
                            keyIsDown[GameActionLowerCam] = isDown;

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
        
        // Update camera
        float3 camFwdXZ = normalise((float3){cameraFwd.x, 0, cameraFwd.z});
        float3 cameraRightXZ = cross(camFwdXZ, (float3){0, 1, 0});

        const float CAM_MOVE_SPEED = 5.f; // in metres per second
        const float CAM_MOVE_AMOUNT = CAM_MOVE_SPEED * dt;
        if(keyIsDown[GameActionMoveCamFwd])
            cameraPos += camFwdXZ * CAM_MOVE_AMOUNT;
        if(keyIsDown[GameActionMoveCamBack])
            cameraPos -= camFwdXZ * CAM_MOVE_AMOUNT;
        if(keyIsDown[GameActionMoveCamLeft])
            cameraPos -= cameraRightXZ * CAM_MOVE_AMOUNT;
        if(keyIsDown[GameActionMoveCamRight])
            cameraPos += cameraRightXZ * CAM_MOVE_AMOUNT;
        if(keyIsDown[GameActionRaiseCam])
            cameraPos.y += CAM_MOVE_AMOUNT;
        if(keyIsDown[GameActionLowerCam])
            cameraPos.y -= CAM_MOVE_AMOUNT;
        
        const float CAM_TURN_SPEED = M_PI; // in radians per second
        const float CAM_TURN_AMOUNT = CAM_TURN_SPEED * dt;
        if(keyIsDown[GameActionTurnCamLeft])
            cameraYaw += CAM_TURN_AMOUNT;
        if(keyIsDown[GameActionTurnCamRight])
            cameraYaw -= CAM_TURN_AMOUNT;
        if(keyIsDown[GameActionLookUp])
            cameraPitch += CAM_TURN_AMOUNT;
        if(keyIsDown[GameActionLookDown])
            cameraPitch -= CAM_TURN_AMOUNT;

        // Clamp yaw to avoid floating-point errors if we turn too far
        while(cameraYaw >= 2*M_PI) 
            cameraYaw -= 2*M_PI;
        while(cameraYaw <= 2*M_PI) 
            cameraYaw += 2*M_PI;

        // Clamp pitch to stop camera flipping upside down
        if(cameraPitch > degreesToRadians(85)) 
            cameraPitch = degreesToRadians(85);
        if(cameraPitch < degreesToRadians(-85)) 
            cameraPitch = degreesToRadians(-85);

        // Calculate view matrix from camera data
        // 
        // float4x4 viewMat = inverse(translationMat(cameraPos) * rotateYMat(cameraYaw) * rotateXMat(cameraPitch));
        // NOTE: We can simplify this calculation to avoid inverse()!
        // Applying the rule inverse(A*B) = inverse(B) * inverse(A) gives:
        // float4x4 viewMat = inverse(rotateXMat(cameraPitch)) * inverse(rotateYMat(cameraYaw)) * inverse(translationMat(cameraPos));
        // The inverse of a rotation/translation is a negated rotation/translation:
        float4x4 viewMat = rotateXMat(-cameraPitch) * rotateYMat(-cameraYaw) * translationMat(-cameraPos);
        cameraFwd = (float3){viewMat.m[2][0], viewMat.m[2][1], -viewMat.m[2][2]};

        // Spin the quad
        float4x4 modelMat = rotateYMat(0.2f * M_PI * currentTimeInSeconds);
        
        // Copy model-view-projection matrix to uniform buffer
        float4x4 modelViewProj = perspectiveMat * viewMat * modelMat;
        memcpy(uniformBuffers[currentUniformBufferIndex].contents, &modelViewProj, 16 * sizeof(float));

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
        [mtlRenderCommandEncoder setFragmentTexture:mtlTexture atIndex:0];
        [mtlRenderCommandEncoder setFragmentSamplerState:mtlSamplerState atIndex:0];
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
