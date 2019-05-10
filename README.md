# Handmade-Metal-Programming

Starter code for Metal graphics programming in the Handmade style (see: Casey Muratori with the [Handmade Hero](https://handmadehero.org/) series and the [Handmade Network](https://handmade.network/)).

Released into the public domain under the Unlicense, see License.txt

## What do you mean 'Handmade'?
The Handmade manifesto: https://handmade.network/manifesto

In this context, I wanted to write Metal rendering code in a much simpler style than all the other samples I found online. The key points are:

* Using a Procedural style instead of Object-Oriented MVC design. Instead of scattering code across several files/classes (like Apple's [official Metal sample code](https://developer.apple.com/documentation/metal/using_a_render_pipeline_to_render_primitives?language=objc)) I just wrote each program in a simple main() function. Having everything happen in a straight linear flow makes it much easier for me to follow when learning a new API.

* Interacting with CoreAnimation/Quartz directly instead of using the MetalKit framework. Apple recommends using MetalKit, creating a special view to house all your Metal code. This is an ugly design pattern for high-performance realtime rendering applications, and it really doesn't give much of a benefit in code simplicity. My 'Hello Triangle' code is tiny compared to [the official Apple sample application](https://developer.apple.com/documentation/metal/using_a_render_pipeline_to_render_primitives?language=objc).

* Building without XCode. XCode adds a lot of bloat that is unnecessary for game programming (Storyboards and Interface Builder files mostly), and I find using a simple build script or Makefile much simpler and faster. For debugging I mostly use [VSCode](https://code.visualstudio.com/), but it is also possible to [set up an XCode project to debug an externally built executable](https://forums.developer.apple.com/thread/65025).

If you're bothered by any of these decisions I recommend that you check out the resources I used when writing this code below!

## Building the source code

Make sure you have the XCode Command Line Tools installed by running the following command in your terminal:
```
xcode-select --install
```

Then simply run the build.sh file in each folder to compile.
```
// While in a directory containing 'build.sh'
./build.sh
```

This will create an executable in a `build` directory that you can then run.

## Resources
These are online resources I found helpful when learning the basics of Metal/OSX programming.

* [Office Metal Documentation](https://developer.apple.com/documentation/metal?language=objc)

* [Archived Metal Programming Guide](https://developer.apple.com/library/archive/documentation/Miscellaneous/Conceptual/MetalProgrammingGuide/Introduction/Introduction.html?language=objc#//apple_ref/doc/uid/TP40014221) (No longer being updated but has useful tidbits)

* [Archive Metal Best Practices Guide](https://developer.apple.com/library/archive/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/index.html?language=objc#//apple_ref/doc/uid/TP40016642) (No longer being updated but has useful tidbits)

* http://metalbyexample.com/

* [Warren Moore's Metal By Example repository](https://github.com/metal-by-example/sample-code/)

* [n-yoda's Metal Without XCode repository](https://github.com/n-yoda/metal-without-xcode)

* [Jeff Buck's OSX Handmade Hero port](https://github.com/itfrombit/osx_handmade)
