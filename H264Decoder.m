#import "VideoFileParser.h"
#import "H264Decoder.h"
#import <VideoToolbox/VideoToolbox.h>


@interface H264Decoder()
{
    uint8_t *_sps;
    NSInteger _spsSize;
    uint8_t *_pps;
    NSInteger _ppsSize;
    VTDecompressionSessionRef _decoderSession;
    CMVideoFormatDescriptionRef _decoderFormatDescription;
    
    AAPLEAGLLayer *_glLayer;
}
@end

static void didDecompress( void *decompressionOutputRefCon, void *sourceFrameRefCon, OSStatus status, VTDecodeInfoFlags infoFlags, CVImageBufferRef pixelBuffer, CMTime presentationTimeStamp, CMTime presentationDuration ){
    
    CVPixelBufferRef *outputPixelBuffer = (CVPixelBufferRef *)sourceFrameRefCon;
    *outputPixelBuffer = CVPixelBufferRetain(pixelBuffer);
}

@implementation H264Decoder

-(void)setGlLayer:(AAPLEAGLLayer*)glLayer
{
     
    _glLayer = glLayer;
}

-(BOOL)initDecoder {
     
    if(_decoderSession) {
        return YES;
    }
    
    const uint8_t* const parameterSetPointers[2] = { _sps, _pps };
    const size_t parameterSetSizes[2] = { _spsSize, _ppsSize };
    OSStatus status = CMVideoFormatDescriptionCreateFromH264ParameterSets(kCFAllocatorDefault,
                                                                          2, //param count
                                                                          parameterSetPointers,
                                                                          parameterSetSizes,
                                                                          4, //nal start code size
                                                                          &_decoderFormatDescription);
    
    if(status == noErr) {
        CFDictionaryRef attrs = NULL;
        const void *keys[] = { kCVPixelBufferPixelFormatTypeKey };
        //      kCVPixelFormatType_420YpCbCr8Planar is YUV420
        //      kCVPixelFormatType_420YpCbCr8BiPlanarFullRange is NV12
        uint32_t v = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange;
        const void *values[] = { CFNumberCreate(NULL, kCFNumberSInt32Type, &v) };
        attrs = CFDictionaryCreate(NULL, keys, values, 1, NULL, NULL);
        
        VTDecompressionOutputCallbackRecord callBackRecord;
        callBackRecord.decompressionOutputCallback = didDecompress;
        callBackRecord.decompressionOutputRefCon = NULL;
        
        status = VTDecompressionSessionCreate(kCFAllocatorDefault,
                                              _decoderFormatDescription,
                                              NULL, attrs,
                                              &callBackRecord,
                                              &_decoderSession);
        CFRelease(attrs);
    } else {
        JYCarLog(@"IOS8VT: reset decoder session failed status=%d", (int)status);
    }

    return YES;
}

- (void)clearH264Deocder {
     
    if(_decoderSession) {
        JYCarLog(@"_decoderSession.......前..%@",_decoderSession);
        VTDecompressionSessionInvalidate(_decoderSession);
        JYCarLog(@"_decoderSession.......后...%@",_decoderSession);
        CFRelease(_decoderSession);
        _decoderSession = NULL;
    }
    
    if(_decoderFormatDescription) {
        JYCarLog(@"_decoderFormatDescription..........");
        CFRelease(_decoderFormatDescription);
        _decoderFormatDescription = NULL;
    }
    
    free(_sps);
    _sps = NULL;
    free(_pps);
    _pps = NULL;
    _spsSize = _ppsSize = 0;
    JYCarLog(@"_spsSize  last..........");
}

-(CVPixelBufferRef)decode:(uint8_t*)buffer bufferSize:(NSInteger)size {
     
    CVPixelBufferRef outputPixelBuffer = NULL;
    
    CMBlockBufferRef blockBuffer = NULL;
    OSStatus status  = CMBlockBufferCreateWithMemoryBlock(kCFAllocatorDefault,
                                                          (void*)buffer, size,
                                                          kCFAllocatorNull,
                                                          NULL, 0, size,
                                                          0, &blockBuffer);
    if(status == kCMBlockBufferNoErr) {
        CMSampleBufferRef sampleBuffer = NULL;
        const size_t sampleSizeArray[] = {size};
        status = CMSampleBufferCreateReady(kCFAllocatorDefault,
                                           blockBuffer,
                                           _decoderFormatDescription ,
                                           1, 0, NULL, 1, sampleSizeArray,
                                           &sampleBuffer);
        if (status == kCMBlockBufferNoErr && sampleBuffer) {
            
            VTDecodeFrameFlags flags = 0;
            VTDecodeInfoFlags flagOut = 0;
            OSStatus decodeStatus = VTDecompressionSessionDecodeFrame(_decoderSession,
                                                                      sampleBuffer,
                                                                      flags,
                                                                      &outputPixelBuffer,
                                                                      &flagOut);
            
            if(decodeStatus == kVTInvalidSessionErr) {
                JYCarLog(@"IOS8VT: Invalid session, reset decoder session");
                //                [self resetH264Decoder];
            } else if(decodeStatus == kVTVideoDecoderBadDataErr) {
                JYCarLog(@"IOS8VT: decode failed status=%d(Bad data)", (int)decodeStatus);
                //                [self resetH264Decoder];
            } else if(decodeStatus != noErr) {
                JYCarLog(@"IOS8VT: decode failed status=%d", (int)decodeStatus);
                                [self initDecoder];
            }
            
            CFRelease(sampleBuffer);
        }
        CFRelease(blockBuffer);
    }
    
    return outputPixelBuffer;
}

-(Boolean)addFrame:(uint8_t*)buffer bufferSize:(NSInteger)size {
     
    uint32_t nalSize = (uint32_t)(size - 4);
    uint8_t *pNalSize = (uint8_t*)(&nalSize);
    
#if true
    buffer[0] = *(pNalSize + 3);
    buffer[1] = *(pNalSize + 2);
    buffer[2] = *(pNalSize + 1);
    buffer[3] = *(pNalSize);
#else
    buffer[0] = *(pNalSize + 0);
    buffer[1] = *(pNalSize + 1);
    buffer[2] = *(pNalSize + 2);
    buffer[3] = *(pNalSize + 3);
#endif
    
    
    CVPixelBufferRef pixelBuffer = NULL;
    int nalType = buffer[4] & 0x1F;
    switch (nalType) {
        case 0x05:
            //            JYCarLog(@"Nal type is IDR frame");
            if([self initDecoder]) {
                pixelBuffer = [self decode:buffer bufferSize:size];
            }
            break;
        case 0x07:
            //            JYCarLog(@"Nal type is SPS");
            /*
             _spsSize = size - 4;
             _sps = malloc(_spsSize);
             memcpy(_sps, buffer + 4, _spsSize);
             */
        {
            int startcode = 0;
            int ppspos = 0;
            for(int i = 0; i < size - 4; i ++ ) {
                startcode = (startcode << 8) | buffer[i];
                if(startcode == 1) {
                    ppspos = i - 3;
                    break;
                }
            }
            if(_sps != NULL) {
                break;
            }
            if (ppspos == 0) {
                _spsSize = size - 4;
                _sps = malloc(_spsSize);
                memcpy(_sps, buffer + 4, _spsSize);
            } else {
                _spsSize = ppspos - 4;
                _sps = malloc(_spsSize);
                memcpy(_sps, buffer + 4, _spsSize);
                if(_pps != NULL) {
                    break;
                }
                _ppsSize = size - ppspos - 4;
                _pps = malloc(_ppsSize);
                memcpy(_pps, buffer + ppspos + 4, _ppsSize);
            }
            //            JYCarLog(@"Nal _spsSize %ld _sps %p _ppsSize %ld _pps %p", (long)_spsSize, _sps, (long)_ppsSize, _pps);
            break;
        }
        case 0x08:
            if(_pps != NULL) {
                break;
            }
            //            JYCarLog(@"Nal type is PPS");
            _ppsSize = size - 4;
            _pps = malloc(_ppsSize);
            memcpy(_pps, buffer + 4, _ppsSize);
            break;
            
        default:
            //JYCarLog(@"Nal type is B/P frame");
            pixelBuffer = [self decode:buffer bufferSize:size];
            break;
    }
    
    if (pixelBuffer) {
        //        JYCarLog(@"任务1");
        if (_glLayer) {
            dispatch_sync(dispatch_get_main_queue(), ^{
                //                JYCarLog(@"任务2");
                _glLayer.pixelBuffer = pixelBuffer;
            });
        }
        //        JYCarLog(@"任务3");
        CVPixelBufferRelease(pixelBuffer);
    }
    
    return nalType == 0x05;
}

- (void)decodeFile:(NSString*)fileName fileExt:(NSString*)fileExt {
     
    NSString *path = [[NSBundle mainBundle] pathForResource:fileName ofType:fileExt];
    VideoFileParser *parser = [VideoFileParser alloc];
    [parser open:path];
    
    VideoPacket *vp = nil;
    while(true) {
        vp = [parser nextPacket];
        if(vp == nil) {
            break;
        }
        /*
         uint32_t nalSize = (uint32_t)(vp.size - 4);
         uint8_t *pNalSize = (uint8_t*)(&nalSize);
         vp.buffer[0] = *(pNalSize + 3);
         vp.buffer[1] = *(pNalSize + 2);
         vp.buffer[2] = *(pNalSize + 1);
         vp.buffer[3] = *(pNalSize);
         [self addFrame: vp.buffer bufferSize:vp.size];*/
        
        JYCarLog(@"Read Nalu size %ld", (long)vp.size);
    }
}

@end
