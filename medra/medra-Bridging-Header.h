//
//  medra-Bridging-Header.h
//  medra
//
//  Created by admin on 2025/11/19.
//

#import "MozJPEGEncoder.h"
#include "zopfli/zopfli.h"
#include "zopflipng/zopflipng_lib.h" // 如果用 PNG 压缩
#import "PNGQuantBridge.h"

#if __has_include("../Pods/libavif/include/avif/avif.h")
#include "../Pods/libavif/include/avif/avif.h"
#endif
