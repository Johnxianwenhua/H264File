#include <objc/NSObject.h>
#import "AAPLEAGLLayer.h"

@interface H264Decoder : NSObject

-(void)setGlLayer:(AAPLEAGLLayer*)glLayer;
-(void)decodeFile:(NSString*)fileName fileExt:(NSString*)fileExt;
-(Boolean)addFrame:(uint8_t*)buffer bufferSize:(NSInteger)size;
-(void)clearH264Deocder;

@end

