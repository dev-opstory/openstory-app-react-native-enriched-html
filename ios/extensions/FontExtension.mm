#import "FontExtension.h"
#import <React/RCTLog.h>

@implementation UIFont (FontExtension)

- (BOOL)isBold {
  return (self.fontDescriptor.symbolicTraits & UIFontDescriptorTraitBold) ==
         UIFontDescriptorTraitBold;
}

- (UIFont *)setBold {
  if ([self isBold]) {
    return self;
  }
  UIFontDescriptorSymbolicTraits newTraits =
      (self.fontDescriptor.symbolicTraits | UIFontDescriptorTraitBold);
  UIFontDescriptor *fontDescriptor =
      [self.fontDescriptor fontDescriptorWithSymbolicTraits:newTraits];
  if (fontDescriptor != nullptr) {
    return [UIFont fontWithDescriptor:fontDescriptor size:0];
  } else {
    RCTLogWarn(@"[EnrichedTextInput]: Couldn't apply bold trait to the font.");
    return self;
  }
}

- (BOOL)isItalic {
  return (self.fontDescriptor.symbolicTraits & UIFontDescriptorTraitItalic) ==
         UIFontDescriptorTraitItalic;
}

// Slant used when a font family ships no italic face and the italic trait
// cannot be resolved, matching the ~15° oblique other platforms synthesize.
static const CGFloat kEnrichedSyntheticObliqueDegrees = 15.0;

static UIFont *EnrichedSyntheticObliqueFont(UIFont *font) {
  CGAffineTransform matrix = CGAffineTransformMake(
      1, 0, tan(kEnrichedSyntheticObliqueDegrees * M_PI / 180.0), 1, 0, 0);
  UIFontDescriptor *obliqueDescriptor =
      [UIFontDescriptor fontDescriptorWithName:font.fontName matrix:matrix];
  UIFont *obliqueFont = [UIFont fontWithDescriptor:obliqueDescriptor
                                              size:font.pointSize];
  return obliqueFont != nullptr ? obliqueFont : font;
}

- (UIFont *)setItalic {
  if ([self isItalic]) {
    return self;
  }
  UIFontDescriptorSymbolicTraits newTraits =
      (self.fontDescriptor.symbolicTraits | UIFontDescriptorTraitItalic);
  UIFontDescriptor *fontDescriptor =
      [self.fontDescriptor fontDescriptorWithSymbolicTraits:newTraits];
  if (fontDescriptor != nullptr) {
    UIFont *italicFont = [UIFont fontWithDescriptor:fontDescriptor size:0];
    if (italicFont != nullptr && [italicFont isItalic]) {
      return italicFont;
    }
  }
  // Custom families such as Pretendard have no italic face, so the trait never
  // resolves. Synthesize an oblique instead of silently rendering upright.
  return EnrichedSyntheticObliqueFont(self);
}

- (UIFont *)withFontTraits:(UIFont *)from {
  UIFont *newFont = self;
  if ([from isBold]) {
    newFont = [newFont setBold];
  }
  if ([from isItalic]) {
    newFont = [newFont setItalic];
  }
  return newFont;
}

- (UIFont *)setSize:(CGFloat)size {
  UIFontDescriptor *newFontDescriptor =
      [self.fontDescriptor fontDescriptorWithSize:size];
  if (newFontDescriptor != nullptr) {
    return [UIFont fontWithDescriptor:newFontDescriptor size:0];
  } else {
    RCTLogWarn(
        @"[EnrichedTextInput]: Couldn't apply heading style to the font.");
    return self;
  }
}

@end
