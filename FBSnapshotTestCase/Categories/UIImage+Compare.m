//
//  Created by Gabriel Handford on 3/1/09.
//  Copyright 2009-2013. All rights reserved.
//  Created by John Boiles on 10/20/11.
//  Copyright (c) 2011. All rights reserved
//  Modified by Felix Schulze on 2/11/13.
//  Copyright 2013. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person
//  obtaining a copy of this software and associated documentation
//  files (the "Software"), to deal in the Software without
//  restriction, including without limitation the rights to use,
//  copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the
//  Software is furnished to do so, subject to the following
//  conditions:
//
//  The above copyright notice and this permission notice shall be
//  included in all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
//  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
//  OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
//  NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
//  HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
//  WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
//  OTHER DEALINGS IN THE SOFTWARE.
//

#import <FBSnapshotTestCase/UIImage+Compare.h>

// This makes debugging much more fun
typedef union {
    uint32_t raw;
    unsigned char bytes[4];
    struct {
        char red;
        char green;
        char blue;
        char alpha;
    } __attribute__((packed)) pixels;
} FBComparePixel;

@implementation UIImage (Compare)

- (BOOL)fb_compareWithImage:(UIImage *)image pixelTolerance:(CGFloat)pixelTolerance tolerance:(CGFloat)tolerance
{
    NSAssert(CGSizeEqualToSize(self.size, image.size), @"Images must be same size.");

    CGSize referenceImageSize = CGSizeMake(CGImageGetWidth(self.CGImage), CGImageGetHeight(self.CGImage));
    CGSize imageSize = CGSizeMake(CGImageGetWidth(image.CGImage), CGImageGetHeight(image.CGImage));

    // The images have the equal size, so we could use the smallest amount of bytes because of byte padding
    size_t minBytesPerRow = MIN(CGImageGetBytesPerRow(self.CGImage), CGImageGetBytesPerRow(image.CGImage));
    size_t referenceImageSizeBytes = referenceImageSize.height * minBytesPerRow;
    void *referenceImagePixels = calloc(1, referenceImageSizeBytes);
    void *imagePixels = calloc(1, referenceImageSizeBytes);

    if (!referenceImagePixels || !imagePixels) {
        free(referenceImagePixels);
        free(imagePixels);
        return NO;
    }

    CGContextRef referenceImageContext = CGBitmapContextCreate(referenceImagePixels,
                                                               referenceImageSize.width,
                                                               referenceImageSize.height,
                                                               CGImageGetBitsPerComponent(self.CGImage),
                                                               minBytesPerRow,
                                                               CGImageGetColorSpace(self.CGImage),
                                                               (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGContextRef imageContext = CGBitmapContextCreate(imagePixels,
                                                      imageSize.width,
                                                      imageSize.height,
                                                      CGImageGetBitsPerComponent(image.CGImage),
                                                      minBytesPerRow,
                                                      CGImageGetColorSpace(image.CGImage),
                                                      (CGBitmapInfo)kCGImageAlphaPremultipliedLast);

    if (!referenceImageContext || !imageContext) {
        CGContextRelease(referenceImageContext);
        CGContextRelease(imageContext);
        free(referenceImagePixels);
        free(imagePixels);
        return NO;
    }

    CGContextDrawImage(referenceImageContext, CGRectMake(0, 0, referenceImageSize.width, referenceImageSize.height), self.CGImage);
    CGContextDrawImage(imageContext, CGRectMake(0, 0, imageSize.width, imageSize.height), image.CGImage);

    CGContextRelease(referenceImageContext);
    CGContextRelease(imageContext);

    BOOL imageEqual = YES;
    FBComparePixel *p1 = referenceImagePixels;
    FBComparePixel *p2 = imagePixels;

    // Do a fast compare if we can
    if (tolerance == 0 && pixelTolerance == 0) {
        imageEqual = (memcmp(referenceImagePixels, imagePixels, referenceImageSizeBytes) == 0);
    } else {
        const NSInteger pixelCount = referenceImageSize.width * referenceImageSize.height;
        // Go through each pixel in turn and see if it is different
        imageEqual = [self comparePixelWithPixelTolerance:pixelTolerance
                                                tolerance:tolerance
                                               pixelCount:pixelCount
                                          referencePixels:p1
                                              imagePixels:p2];
    }

    free(referenceImagePixels);
    free(imagePixels);

    return imageEqual;
}

- (BOOL)comparePixelWithPixelTolerance:(CGFloat)pixelTolerance
                        referencePixel:(FBComparePixel*)referencePixel
                            imagePixel:(FBComparePixel*)imagePixel
{
    if (referencePixel->raw == imagePixel->raw) {
        return YES;
    } else if (pixelTolerance == 0) {
        return NO;
    }

    CGFloat redPercentDiff = [self calculatePercentDifferenceForReferencePixelComponent:referencePixel->pixels.red
                                                                    imagePixelComponent:imagePixel->pixels.red];
    CGFloat greenPercentDiff = [self calculatePercentDifferenceForReferencePixelComponent:referencePixel->pixels.green
                                                                      imagePixelComponent:imagePixel->pixels.green];
    CGFloat bluePercentDiff = [self calculatePercentDifferenceForReferencePixelComponent:referencePixel->pixels.blue
                                                                     imagePixelComponent:imagePixel->pixels.blue];
    CGFloat alphaPercentDiff = [self calculatePercentDifferenceForReferencePixelComponent:referencePixel->pixels.alpha
                                                                      imagePixelComponent:imagePixel->pixels.alpha];

    return !(redPercentDiff > pixelTolerance ||
             greenPercentDiff > pixelTolerance ||
             bluePercentDiff > pixelTolerance ||
             alphaPercentDiff > pixelTolerance);
}

- (CGFloat)calculatePercentDifferenceForReferencePixelComponent:(char)p1
                                            imagePixelComponent:(char)p2
{
    int referencePixelComponent = (unsigned char)p1;
    int imagePixelComponent = (unsigned char)p2;
    int componentDifference = abs(referencePixelComponent - imagePixelComponent);
    return (CGFloat)componentDifference/256;
}

- (BOOL)comparePixelWithPixelTolerance:(CGFloat)pixelTolerance
                             tolerance:(CGFloat)tolerance
                            pixelCount:(NSInteger)pixelCount
                       referencePixels:(FBComparePixel*)referencePixel
                           imagePixels:(FBComparePixel*)imagePixel
{
    NSInteger numDiffPixels = 0;
    for (int n = 0; n < pixelCount; ++n) {
        // If this pixel is different, increment the pixel diff count and see
        // if we have hit our limit.
        if (![self comparePixelWithPixelTolerance:pixelTolerance referencePixel:referencePixel imagePixel:imagePixel]) {
            numDiffPixels ++;

            CGFloat percent = (CGFloat)numDiffPixels / pixelCount;
            if (percent > tolerance) {
                return NO;
                break;
            }
        }

        referencePixel++;
        imagePixel++;
    }
    return YES;
}

@end
