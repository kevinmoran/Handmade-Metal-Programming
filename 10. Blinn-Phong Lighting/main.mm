
#include <stdio.h>

#include <Cocoa/Cocoa.h>
#include <Metal/Metal.h>
#include <QuartzCore/CAMetalLayer.h>
#include <mach/mach_time.h>

#include "OSX_Keycodes.h"
#include "3DMaths.h"
#include "ShaderInterface.h"
#include "ObjLoading.h"
#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"

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

id<MTLTexture> osxCreateDepthTexture(id<MTLDevice> mtlDevice, int width, int height)
{
    MTLTextureDescriptor* mtlDepthTexDesc = 
        [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatDepth32Float 
        width:width 
        height:height 
        mipmapped:NO];
    mtlDepthTexDesc.storageMode = MTLStorageModePrivate;
    mtlDepthTexDesc.usage = MTLTextureUsageRenderTarget;
    id<MTLTexture> mtlDepthTexture = [mtlDevice newTextureWithDescriptor:mtlDepthTexDesc];
    [mtlDepthTexDesc release];
    mtlDepthTexture.label = @"Depth Buffer";

    return mtlDepthTexture;
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
    mainWindow.title = @"Blinn-Phong Lighting";
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
        return 1;
    }
    id<MTLFunction> blinnPhongVertFunc = [mtlLibrary newFunctionWithName:@"blinnPhongVert"];
    id<MTLFunction> blinnPhongFragFunc = [mtlLibrary newFunctionWithName:@"blinnPhongFrag"];
    id<MTLFunction> mvpVertFunc = [mtlLibrary newFunctionWithName:@"mvpVert"];
    id<MTLFunction> uniformColorFunc = [mtlLibrary newFunctionWithName:@"uniformColorFrag"];
    [mtlLibrary release];

    LoadedObj cubeObj = loadObj("cube.obj");

    id<MTLBuffer> cubeVertexBuffer = [mtlDevice newBufferWithBytes:cubeObj.vertexBuffer 
                                                length:cubeObj.numVertices * sizeof(VertexData)
                                                options:MTLResourceOptionCPUCacheModeDefault];
    cubeVertexBuffer.label = @"CubeVertexBuffer";
    id<MTLBuffer> cubeIndexBuffer = [mtlDevice newBufferWithBytes:cubeObj.indexBuffer 
                                               length:cubeObj.numIndices * sizeof(uint16_t)
                                               options:MTLResourceOptionCPUCacheModeDefault];
    cubeIndexBuffer.label = @"CubeIndexBuffer";

    free(cubeObj.vertexBuffer);
    free(cubeObj.indexBuffer);

    // Load Image
    int texWidth, texHeight, texNumChannels;
    int texForceNumChannels = 4;
    unsigned char* testTextureBytes = stbi_load("test.png", &texWidth, &texHeight,
                                                &texNumChannels, texForceNumChannels);
    assert(testTextureBytes);
    int texBytesPerRow = 4 * texWidth;

    // Create Texture
    MTLTextureDescriptor* mtlTextureDescriptor =
        [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                                 width:texWidth
                                                                 height:texHeight
                                                                 mipmapped:NO];
    id<MTLTexture> mtlTexture = [mtlDevice newTextureWithDescriptor:mtlTextureDescriptor];
    mtlTexture.label = @"CubeDiffuse";
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
    
    // Create Depth/Stencil State
    MTLDepthStencilDescriptor* mtlDepthStencilDesc = [MTLDepthStencilDescriptor new];
    mtlDepthStencilDesc.depthCompareFunction = MTLCompareFunctionLess;
    mtlDepthStencilDesc.depthWriteEnabled = YES;
    mtlDepthStencilDesc.label = @"DepthStencilState";
    id<MTLDepthStencilState> mtlDepthStencilState = [mtlDevice newDepthStencilStateWithDescriptor:mtlDepthStencilDesc];
    [mtlDepthStencilDesc release];

    // Create Depth Buffer
    id<MTLTexture> mtlDepthTexture;
    mtlDepthTexture = osxCreateDepthTexture(mtlDevice, 
                                           caMetalLayer.frame.size.width,
                                           caMetalLayer.frame.size.height);

    // Create Uniform Buffers
    const uint32_t MAX_NUM_FRAMES_IN_FLIGHT = 2;
    const uint32_t NUM_VS_UNIFORM_SLOTS = 6; 
    const size_t VS_UNIFORM_BUFFER_SLOT_SIZE = 256; // NOTE: Constant buffer offsets must be aligned to 256 bytes
    const size_t VS_UNIFORM_BUFFER_TOTAL_SIZE = NUM_VS_UNIFORM_SLOTS * VS_UNIFORM_BUFFER_SLOT_SIZE;
    id<MTLBuffer> vsUniformBuffers[MAX_NUM_FRAMES_IN_FLIGHT];
    vsUniformBuffers[0] = [mtlDevice newBufferWithLength:VS_UNIFORM_BUFFER_TOTAL_SIZE
                                     options:MTLResourceCPUCacheModeWriteCombined];
    vsUniformBuffers[1] = [mtlDevice newBufferWithLength:VS_UNIFORM_BUFFER_TOTAL_SIZE
                                     options:MTLResourceCPUCacheModeWriteCombined];
    vsUniformBuffers[0].label = @"VSUniformBuffer0";
    vsUniformBuffers[1].label = @"VSUniformBuffer1";
    
    const size_t FS_UNIFORM_BUFFER_SIZE = sizeof(FSUniforms);
    id<MTLBuffer> fsUniformBuffers[MAX_NUM_FRAMES_IN_FLIGHT];
    fsUniformBuffers[0] = [mtlDevice newBufferWithLength:FS_UNIFORM_BUFFER_SIZE
                                     options:MTLResourceCPUCacheModeWriteCombined];
    fsUniformBuffers[1] = [mtlDevice newBufferWithLength:FS_UNIFORM_BUFFER_SIZE
                                     options:MTLResourceCPUCacheModeWriteCombined];
    fsUniformBuffers[0].label = @"FSUniformBuffer0";
    fsUniformBuffers[1].label = @"FSUniformBuffer1";

    size_t uniformDataBufferSize = NUM_VS_UNIFORM_SLOTS * VS_UNIFORM_BUFFER_SLOT_SIZE;
    uint8_t* uniformDataBuffer = (uint8_t*)malloc(uniformDataBufferSize);

    int currentUniformBufferIndex = 0;
    dispatch_semaphore_t inFlightSemaphore = dispatch_semaphore_create(MAX_NUM_FRAMES_IN_FLIGHT);

    // Create vertex descriptor
    MTLVertexDescriptor* vertDesc = [MTLVertexDescriptor new];
    vertDesc.attributes[VertexAttributeIndex_Position].format = MTLVertexFormatFloat3;
    vertDesc.attributes[VertexAttributeIndex_Position].offset = 0;
    vertDesc.attributes[VertexAttributeIndex_Position].bufferIndex = ShaderBufferIndex_Attributes;
    vertDesc.attributes[VertexAttributeIndex_TexCoords].format = MTLVertexFormatFloat2;
    vertDesc.attributes[VertexAttributeIndex_TexCoords].offset = 3 * sizeof(float);
    vertDesc.attributes[VertexAttributeIndex_TexCoords].bufferIndex = ShaderBufferIndex_Attributes;
    vertDesc.attributes[VertexAttributeIndex_Normal].format = MTLVertexFormatFloat3;
    vertDesc.attributes[VertexAttributeIndex_Normal].offset = 5 * sizeof(float);
    vertDesc.attributes[VertexAttributeIndex_Normal].bufferIndex = ShaderBufferIndex_Attributes;
    vertDesc.layouts[ShaderBufferIndex_Attributes].stride = 8 * sizeof(float);
    vertDesc.layouts[ShaderBufferIndex_Attributes].stepRate = 1;
    vertDesc.layouts[ShaderBufferIndex_Attributes].stepFunction = MTLVertexStepFunctionPerVertex;

    // Create Render Pipeline States
    MTLRenderPipelineDescriptor* mtlRenderPipelineDesc = [MTLRenderPipelineDescriptor new];
    mtlRenderPipelineDesc.vertexFunction = blinnPhongVertFunc;
    mtlRenderPipelineDesc.fragmentFunction = blinnPhongFragFunc;
    mtlRenderPipelineDesc.vertexDescriptor = vertDesc;
    mtlRenderPipelineDesc.colorAttachments[0].pixelFormat = caMetalLayer.pixelFormat;
    mtlRenderPipelineDesc.depthAttachmentPixelFormat = mtlDepthTexture.pixelFormat;
    mtlRenderPipelineDesc.label = @"BlinnPhongRenderPipelineState";
    
    id<MTLRenderPipelineState> blinnPhongRenderPipelineState = [mtlDevice newRenderPipelineStateWithDescriptor:mtlRenderPipelineDesc error:&error];
    if (!blinnPhongRenderPipelineState) {
        printf("Failed to create pipeline state. Error: %s\n", error.localizedDescription.UTF8String);
        return 1;
    }

    mtlRenderPipelineDesc.vertexFunction = mvpVertFunc;
    mtlRenderPipelineDesc.fragmentFunction = uniformColorFunc;
    mtlRenderPipelineDesc.label = @"LightRenderPipelineState";

    id<MTLRenderPipelineState> lightRenderPipelineState = [mtlDevice newRenderPipelineStateWithDescriptor:mtlRenderPipelineDesc error:&error];
    if (!lightRenderPipelineState) {
        printf("Failed to create pipeline state. Error: %s\n", error.localizedDescription.UTF8String);
        return 1;
    }

    [blinnPhongVertFunc release];
    [blinnPhongFragFunc release];
    [mvpVertFunc release];
    [uniformColorFunc release];
    [vertDesc release];
    [mtlRenderPipelineDesc release];

    id<MTLCommandQueue> mtlCommandQueue = [mtlDevice newCommandQueue];
    mtlCommandQueue.label = @"CommandQueue";

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
    float3 cameraPos = {0, 1, 3};
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
        dispatch_semaphore_wait(inFlightSemaphore, DISPATCH_TIME_FOREVER);

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

            [mtlDepthTexture release];
            mtlDepthTexture = osxCreateDepthTexture(mtlDevice, 
                                                    caMetalLayer.frame.size.width,
                                                    caMetalLayer.frame.size.height);

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
        float4x4 viewMat = rotateXMat(-cameraPitch) * rotateYMat(-cameraYaw) * translationMat(-cameraPos);
        float4x4 inverseViewMat = translationMat(cameraPos) * rotateYMat(cameraYaw) * rotateXMat(cameraPitch);
        cameraFwd = (float3){viewMat.m[2][0], viewMat.m[2][1], -viewMat.m[2][2]};

        // Calculate model matrices for cubes
        const int numCubes = 3;
        float4x4 cubeModelViewMats[numCubes];
        float4x4 cubeInverseModelViewMats[numCubes];
        float3 cubePositions[numCubes] = {
            {0,0,0},
            {-3, 0, -1.5},
            {4.5, 0.2, -3}
        };

        float modelRotation = 0.2f * M_PI * currentTimeInSeconds;
        for(int i=0; i<numCubes; ++i)
        {
            modelRotation += 0.6f*i; // Add an offset so cubes have different phases
            cubeModelViewMats[i] = viewMat * translationMat(cubePositions[i]) * rotateYMat(modelRotation);
            cubeInverseModelViewMats[i] = rotateYMat(-modelRotation) * translationMat(-cubePositions[i]) * inverseViewMat;
        }

        // Calculate uniform data for point lights
        const int numLights = 2;
        float3 initialPointLightPositions[numLights] = {
            {1, 0.5f, 0},
            {-1, 0.7f, -1.2f}
        };
        float4 pointLightColors[numLights] = {
            {0.1, 0.4, 0.9, 1},
            {0.9, 0.1, 0.6, 1}
        };
        float4x4 lightModelViewMats[numLights];
        float4 pointLightPosEye[numLights];

        float lightRotation = -0.3f * M_PI * currentTimeInSeconds;
        for(int i=0; i<numLights; ++i)
        {
            lightRotation += 0.5f*i; // Add an offset so lights have different phases
            lightModelViewMats[i] = viewMat * rotateYMat(lightRotation) * translationMat(initialPointLightPositions[i]) * scaleMat(0.2f);
            pointLightPosEye[i] = {lightModelViewMats[i].m[3][0], lightModelViewMats[i].m[3][1], lightModelViewMats[i].m[3][2], 1};
        }
        
        // Copy data to uniform buffers
        assert(numCubes + numLights <= NUM_VS_UNIFORM_SLOTS);
        for(int i=0; i<numCubes; ++i)
        {
            VSUniforms* cubeUniforms = (VSUniforms*)(uniformDataBuffer + (VS_UNIFORM_BUFFER_SLOT_SIZE*i));
            cubeUniforms->modelView = cubeModelViewMats[i];
            cubeUniforms->modelViewProj = perspectiveMat * cubeModelViewMats[i];
            cubeUniforms->normalMatrix = float4x4ToFloat3x3(transpose(cubeInverseModelViewMats[i]));
        }
        for(int i=0; i<numLights; ++i)
        {
            VSUniforms* lightUniforms = (VSUniforms*)(uniformDataBuffer + (VS_UNIFORM_BUFFER_SLOT_SIZE*(numCubes+i)));
            lightUniforms->modelViewProj = perspectiveMat * lightModelViewMats[i];
        }

        memcpy(vsUniformBuffers[currentUniformBufferIndex].contents, uniformDataBuffer, uniformDataBufferSize);


        FSUniforms fsUniforms = {};
        fsUniforms.dirLight.dirEye = normalise(viewMat * (float4){1, 1, -1});
        fsUniforms.dirLight.color = {0.7, 0.8, 0.2, 1};

        for(int i=0; i<numLights; ++i){
            fsUniforms.pointLights[i].posEye = pointLightPosEye[i];
            fsUniforms.pointLights[i].color = pointLightColors[i];
        }
        memcpy(fsUniformBuffers[currentUniformBufferIndex].contents, &fsUniforms, sizeof(FSUniforms));

        @autoreleasepool {
        id<CAMetalDrawable> caMetalDrawable = [caMetalLayer nextDrawable];
        if(!caMetalDrawable) continue;

        MTLRenderPassDescriptor* mtlRenderPassDescriptor = [MTLRenderPassDescriptor new];
        mtlRenderPassDescriptor.colorAttachments[0].texture = caMetalDrawable.texture;
        mtlRenderPassDescriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
        mtlRenderPassDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
        mtlRenderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0.1, 0.2, 0.6, 1.0);
        mtlRenderPassDescriptor.depthAttachment.texture = mtlDepthTexture;
        mtlRenderPassDescriptor.depthAttachment.clearDepth = 1.0;
        mtlRenderPassDescriptor.depthAttachment.loadAction = MTLLoadActionClear;
        mtlRenderPassDescriptor.depthAttachment.storeAction = MTLStoreActionDontCare;

        id<MTLCommandBuffer> mtlCommandBuffer = [mtlCommandQueue commandBuffer];
        mtlCommandBuffer.label = @"Command Buffer";

        id<MTLRenderCommandEncoder> mtlRenderCommandEncoder = 
            [mtlCommandBuffer renderCommandEncoderWithDescriptor:mtlRenderPassDescriptor];
        [mtlRenderPassDescriptor release];
        mtlRenderCommandEncoder.label = @"RenderCommandEncoder";

        [mtlRenderCommandEncoder setViewport:(MTLViewport){0, 0, 
                                                           caMetalLayer.drawableSize.width,
                                                           caMetalLayer.drawableSize.height,
                                                           0, 1}];
        [mtlRenderCommandEncoder setDepthStencilState:mtlDepthStencilState];
        [mtlRenderCommandEncoder setFrontFacingWinding:MTLWindingCounterClockwise];
        [mtlRenderCommandEncoder setCullMode:MTLCullModeBack];

        [mtlRenderCommandEncoder setRenderPipelineState:blinnPhongRenderPipelineState];
        [mtlRenderCommandEncoder setVertexBuffer:cubeVertexBuffer offset:0 atIndex:ShaderBufferIndex_Attributes];
        [mtlRenderCommandEncoder setFragmentTexture:mtlTexture atIndex:0];
        [mtlRenderCommandEncoder setFragmentSamplerState:mtlSamplerState atIndex:0];
        [mtlRenderCommandEncoder setFragmentBuffer:fsUniformBuffers[currentUniformBufferIndex] offset:0 atIndex:ShaderBufferIndex_Uniforms];
        [mtlRenderCommandEncoder setVertexBuffer:vsUniformBuffers[currentUniformBufferIndex] offset:0 atIndex:ShaderBufferIndex_Uniforms];

        for(int i=0; i<numCubes; ++i)
        {
            [mtlRenderCommandEncoder setVertexBufferOffset:i*VS_UNIFORM_BUFFER_SLOT_SIZE
                                     atIndex:ShaderBufferIndex_Uniforms];
            [mtlRenderCommandEncoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                                 indexCount:cubeIndexBuffer.length / sizeof(uint16_t)
                                 indexType:MTLIndexTypeUInt16
                                 indexBuffer:cubeIndexBuffer
                                 indexBufferOffset:0];
        }

        [mtlRenderCommandEncoder setRenderPipelineState:lightRenderPipelineState];
        for(int i=0; i<numLights; ++i)
        {
            [mtlRenderCommandEncoder setVertexBufferOffset:(numCubes+i) * VS_UNIFORM_BUFFER_SLOT_SIZE atIndex:ShaderBufferIndex_Uniforms];
            [mtlRenderCommandEncoder setFragmentBytes:&pointLightColors[i] length:sizeof(float4) atIndex:ShaderBufferIndex_Uniforms];
            
            [mtlRenderCommandEncoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                                    indexCount:cubeIndexBuffer.length / sizeof(uint16_t)
                                    indexType:MTLIndexTypeUInt16
                                    indexBuffer:cubeIndexBuffer
                                    indexBufferOffset:0];
        }
        [mtlRenderCommandEncoder endEncoding];

        [mtlCommandBuffer presentDrawable:caMetalDrawable];

        [mtlCommandBuffer addCompletedHandler:^(id<MTLCommandBuffer> mtlCommandBuffer) {
            dispatch_semaphore_signal(inFlightSemaphore);
        }];
        
        [mtlCommandBuffer commit];

        } // autoreleasepool

        currentUniformBufferIndex = (currentUniformBufferIndex+1) % MAX_NUM_FRAMES_IN_FLIGHT;
    }
    return 0;
}
