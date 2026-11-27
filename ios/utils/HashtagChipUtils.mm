#import "HashtagChipUtils.h"
#import "EnrichedTextInputView.h"
#import "StyleHeaders.h"

NSAttributedStringKey const HashtagChipKernAttributeName =
    @"EnrichedHashtagChipKern";
NSAttributedStringKey const HashtagChipTextAttributeName =
    @"EnrichedHashtagChipText";
// What a chip replaced, kept so it can be put back when the chip goes away.
static NSAttributedStringKey const kOriginalFontKey =
    @"EnrichedHashtagChipOriginalFont";
static NSAttributedStringKey const kOriginalParagraphStyleKey =
    @"EnrichedHashtagChipOriginalParagraphStyle";
static NSAttributedStringKey const kOriginalBaselineKey =
    @"EnrichedHashtagChipOriginalBaseline";

// The chip the app's post detail draws (openstory-app HashtagChip / web's
// rich-text-view): 14pt medium text in a 26pt pill, 8pt either side, on a 30pt
// line, 4pt more room beside plain text.
static const CGFloat kChipHeight = 26;
static const CGFloat kPadding = 8;
static const CGFloat kTextGap = 4;
static const CGFloat kChipLineHeight = 30;
/** Measured on the sim: chip text sat 1pt under the pill's centre. */
static const CGFloat kPillOffsetY = 1;
static const CGFloat kChipFontScale = 14.0 / 16.0;
static NSString *const kChipFontName = @"Pretendard-Medium";
static const NSUInteger kMaxTagLength = 100;

static NSString *const kRangeKey = @"range";
static NSString *const kTextBeforeKey = @"textBefore";
static NSString *const kTextAfterKey = @"textAfter";

static UIColor *ChipBackgroundColor(void) {
  return [UIColor colorWithRed:0xE3 / 255.0
                         green:0xE6 / 255.0
                          blue:0xF0 / 255.0
                         alpha:1];
}
static UIColor *ChipTextColor(void) {
  return [UIColor colorWithRed:0x4B / 255.0
                         green:0x50 / 255.0
                          blue:0x61 / 255.0
                         alpha:1];
}

@implementation HashtagChipLayoutDelegate

- (BOOL)layoutManager:(NSLayoutManager *)layoutManager
    shouldSetLineFragmentRect:(inout CGRect *)lineFragmentRect
         lineFragmentUsedRect:(inout CGRect *)lineFragmentUsedRect
               baselineOffset:(inout CGFloat *)baselineOffset
              inTextContainer:(NSTextContainer *)textContainer
                forGlyphRange:(NSRange)glyphRange {
  EnrichedTextInputView *input = self.input;
  NSTextStorage *storage = layoutManager.textStorage;
  if (input == nil || !input->hashtagChipsEnabled || glyphRange.length == 0) {
    return NO;
  }
  NSRange chars = [layoutManager characterRangeForGlyphRange:glyphRange
                                            actualGlyphRange:NULL];
  if (![HashtagChipUtils hasChipIn:storage range:chars]) {
    return NO;
  }

  // Only a line that holds a chip is 30pt, its text centred, as on web, where
  // the chip's own line-height sets the line box. The other lines of the same
  // paragraph (wrapped or not) keep the body's line height.
  CGFloat chipLine = [HashtagChipUtils chipLineHeightIn:input];
  if (chipLine > lineFragmentRect->size.height) {
    lineFragmentRect->size.height = chipLine;
    lineFragmentUsedRect->size.height =
        MAX(lineFragmentUsedRect->size.height, chipLine);
    UIFont *body = [input->config primaryFont];
    CGFloat glyphBox = body != nil ? body.ascender - body.descender : 0;
    if (glyphBox > 0) {
      *baselineOffset = (chipLine - glyphBox) / 2 + body.ascender;
    }
  }

  NSUInteger index = chars.location;
  if ([storage.string characterAtIndex:index] == '#' &&
      [storage attribute:HashtagChipTextAttributeName
                 atIndex:index
          effectiveRange:NULL] != nil) {
    // The chip's paragraph carries a matching tail indent, so the moved line
    // still ends inside the container.
    lineFragmentRect->origin.x += kPadding;
    lineFragmentUsedRect->origin.x += kPadding;
  }
  return YES;
}

@end

@implementation HashtagChipUtils

+ (UIColor *)chipTextColor {
  return ChipTextColor();
}

+ (CGFloat)chipLineHeightIn:(EnrichedTextInputView *)input {
  EnrichedConfig *config = input->config;
  CGFloat primary = [config primaryLineHeight];
  CGFloat scaled = [config scaledPrimaryLineHeight];
  return kChipLineHeight * (primary > 0 ? scaled / primary : 1);
}

+ (BOOL)hasChipIn:(NSAttributedString *)text range:(NSRange)range {
  if (range.length == 0 || NSMaxRange(range) > text.length) {
    return NO;
  }
  __block BOOL found = NO;
  [text
      enumerateAttribute:HashtagChipTextAttributeName
                 inRange:range
                 options:
                     NSAttributedStringEnumerationLongestEffectiveRangeNotRequired
              usingBlock:^(id value, NSRange r, BOOL *stop) {
                if (value != nil) {
                  found = YES;
                  *stop = YES;
                }
              }];
  return found;
}

+ (CGFloat)extraHeightFor:(NSAttributedString *)text
                    width:(CGFloat)width
                    input:(EnrichedTextInputView *)input {
  if (!input->hashtagChipsEnabled || input->hashtagChips.count == 0) {
    return 0;
  }
  // Lays the text out as `boundingRectWithSize:` does (no delegate) and adds
  // what HashtagChipLayoutDelegate adds to each line that holds a chip.
  NSTextStorage *storage =
      [[NSTextStorage alloc] initWithAttributedString:text];
  NSLayoutManager *layoutManager = [NSLayoutManager new];
  NSTextContainer *container =
      [[NSTextContainer alloc] initWithSize:CGSizeMake(width, CGFLOAT_MAX)];
  container.lineFragmentPadding = 0;
  [layoutManager addTextContainer:container];
  [storage addLayoutManager:layoutManager];
  [layoutManager ensureLayoutForTextContainer:container];

  CGFloat chipLine = [self chipLineHeightIn:input];
  __block CGFloat extra = 0;
  NSRange all = [layoutManager glyphRangeForTextContainer:container];
  [layoutManager
      enumerateLineFragmentsForGlyphRange:all
                               usingBlock:^(CGRect rect, CGRect usedRect,
                                            NSTextContainer *c,
                                            NSRange lineGlyphs, BOOL *stop) {
                                 NSRange chars = [layoutManager
                                     characterRangeForGlyphRange:lineGlyphs
                                                actualGlyphRange:NULL];
                                 if ([self hasChipIn:storage range:chars]) {
                                   extra += MAX(0, chipLine - rect.size.height);
                                 }
                               }];
  return extra;
}

+ (NSRegularExpression *)tokenRegex {
  static NSRegularExpression *regex;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    regex = [NSRegularExpression
        regularExpressionWithPattern:@"(^|\\s)(#\\S+)"
                             options:NSRegularExpressionAnchorsMatchLines
                               error:nil];
  });
  return regex;
}

+ (BOOL)isValidTag:(NSString *)tag {
  NSString *withoutHashes =
      [tag stringByTrimmingCharactersInSet:
               [NSCharacterSet characterSetWithCharactersInString:@"#"]];
  if (withoutHashes.length == 0) {
    return NO;
  }
  NSUInteger codePoints =
      [tag lengthOfBytesUsingEncoding:NSUTF32StringEncoding] / 4;
  return codePoints <= kMaxTagLength;
}

/** Whether `text` holds anything but whitespace in `range`. */
+ (BOOL)hasVisibleCharacters:(NSString *)text inRange:(NSRange)range {
  if (range.length == 0) {
    return NO;
  }
  NSRange found = [text
      rangeOfCharacterFromSet:[[NSCharacterSet whitespaceAndNewlineCharacterSet]
                                  invertedSet]
                      options:0
                        range:range];
  return found.location != NSNotFound;
}

+ (NSArray<NSDictionary *> *)findChipsInInput:(EnrichedTextInputView *)input {
  UITextView *textView = input->textView;
  NSString *text = textView.textStorage.string;
  if (text.length == 0) {
    return @[];
  }

  BOOL isTyping =
      textView.isFirstResponder && textView.selectedRange.length == 0;
  NSUInteger caret = textView.selectedRange.location;
  LinkStyle *linkStyle = (LinkStyle *)input->stylesDict[@([LinkStyle getType])];

  NSMutableArray<NSValue *> *tokens = [NSMutableArray array];
  for (NSTextCheckingResult *match in
       [[self tokenRegex] matchesInString:text
                                  options:0
                                    range:NSMakeRange(0, text.length)]) {
    NSRange token = [match rangeAtIndex:2];
    NSString *tag = [text
        substringWithRange:NSMakeRange(token.location + 1, token.length - 1)];
    if (![self isValidTag:tag]) {
      continue;
    }
    // Still being typed: the caret sits inside the token or right after it.
    if (isTyping && caret > token.location && caret <= NSMaxRange(token)) {
      continue;
    }
    if (linkStyle != nullptr && [linkStyle all:token].count > 0) {
      continue;
    }
    [tokens addObject:[NSValue valueWithRange:token]];
  }

  // Which sides have plain text on the same line, as the detail decides its
  // 4pt text gap: a neighbouring chip or the line's edge does not count.
  NSMutableArray<NSDictionary *> *chips = [NSMutableArray array];
  for (NSUInteger i = 0; i < tokens.count; i++) {
    NSRange token = tokens[i].rangeValue;
    NSRange line = [text lineRangeForRange:NSMakeRange(token.location, 0)];
    NSUInteger before = line.location;
    if (i > 0) {
      NSRange previous = tokens[i - 1].rangeValue;
      if (NSMaxRange(previous) > before) {
        before = NSMaxRange(previous);
      }
    }
    NSUInteger after = NSMaxRange(line);
    if (i + 1 < tokens.count) {
      NSRange next = tokens[i + 1].rangeValue;
      if (next.location < after) {
        after = next.location;
      }
    }
    BOOL textBefore = [self
        hasVisibleCharacters:text
                     inRange:NSMakeRange(before, token.location - before)];
    BOOL textAfter =
        [self hasVisibleCharacters:text
                           inRange:NSMakeRange(NSMaxRange(token),
                                               after - NSMaxRange(token))];
    [chips addObject:@{
      kRangeKey : [NSValue valueWithRange:token],
      kTextBeforeKey : @(textBefore),
      kTextAfterKey : @(textAfter),
    }];
  }
  return chips;
}

#pragma mark - Saving and restoring what a chip changes

/** Saves `key`'s runs in `range` under `marker` (NSNull for none) unless saved
 * already. */
+ (void)save:(NSAttributedStringKey)key
       under:(NSAttributedStringKey)marker
     inRange:(NSRange)range
          in:(NSTextStorage *)storage {
  NSMutableArray<NSArray *> *runs = [NSMutableArray array];
  [storage enumerateAttribute:key
                      inRange:range
                      options:0
                   usingBlock:^(id value, NSRange run, BOOL *stop) {
                     [runs addObject:@[
                       [NSValue valueWithRange:run], value ?: [NSNull null]
                     ]];
                   }];
  for (NSArray *run in runs) {
    NSRange runRange = [(NSValue *)run[0] rangeValue];
    if ([storage attribute:marker
                   atIndex:runRange.location
            effectiveRange:NULL] == nil) {
      [storage addAttribute:marker value:run[1] range:runRange];
    }
  }
}

/** Puts back what `marker` saved for `key`, and drops the marker. */
+ (void)restore:(NSAttributedStringKey)key
           from:(NSAttributedStringKey)marker
             in:(NSTextStorage *)storage {
  NSMutableArray<NSArray *> *runs = [NSMutableArray array];
  [storage
      enumerateAttribute:marker
                 inRange:NSMakeRange(0, storage.length)
                 options:0
              usingBlock:^(id value, NSRange run, BOOL *stop) {
                if (value != nil) {
                  [runs addObject:@[ [NSValue valueWithRange:run], value ]];
                }
              }];
  for (NSArray *run in runs) {
    NSRange range = [(NSValue *)run[0] rangeValue];
    if (run[1] == [NSNull null]) {
      [storage removeAttribute:key range:range];
    } else {
      [storage addAttribute:key value:run[1] range:range];
    }
    [storage removeAttribute:marker range:range];
  }
}

+ (void)removeAllChipAttributesIn:(NSTextStorage *)storage {
  [self restore:NSFontAttributeName from:kOriginalFontKey in:storage];
  [self restore:NSParagraphStyleAttributeName
           from:kOriginalParagraphStyleKey
             in:storage];
  [self restore:NSBaselineOffsetAttributeName
           from:kOriginalBaselineKey
             in:storage];

  NSRange whole = NSMakeRange(0, storage.length);
  [storage removeAttribute:HashtagChipTextAttributeName range:whole];
  // Only our kern: ZeroWidthSpaceUtils puts its own on zero-width spaces.
  NSMutableArray<NSValue *> *kerned = [NSMutableArray array];
  [storage enumerateAttribute:HashtagChipKernAttributeName
                      inRange:whole
                      options:0
                   usingBlock:^(id value, NSRange range, BOOL *stop) {
                     if (value != nil) {
                       [kerned addObject:[NSValue valueWithRange:range]];
                     }
                   }];
  for (NSValue *value in kerned) {
    [storage removeAttribute:NSKernAttributeName range:value.rangeValue];
    [storage removeAttribute:HashtagChipKernAttributeName
                       range:value.rangeValue];
  }
}

/** New text typed next to a chip must not pick up what the chip set. */
+ (void)cleanTypingAttributes:(UITextView *)textView {
  NSMutableDictionary *typing = [textView.typingAttributes mutableCopy];
  BOOL changed = NO;
  NSArray *pairs = @[
    @[ kOriginalFontKey, NSFontAttributeName ],
    @[ kOriginalParagraphStyleKey, NSParagraphStyleAttributeName ],
    @[ kOriginalBaselineKey, NSBaselineOffsetAttributeName ],
  ];
  for (NSArray *pair in pairs) {
    id original = typing[pair[0]];
    if (original == nil) {
      continue;
    }
    if (original == [NSNull null]) {
      [typing removeObjectForKey:pair[1]];
    } else {
      typing[pair[1]] = original;
    }
    [typing removeObjectForKey:pair[0]];
    changed = YES;
  }
  if (typing[HashtagChipKernAttributeName] != nil) {
    [typing removeObjectForKey:NSKernAttributeName];
    [typing removeObjectForKey:HashtagChipKernAttributeName];
    changed = YES;
  }
  if (typing[HashtagChipTextAttributeName] != nil) {
    [typing removeObjectForKey:HashtagChipTextAttributeName];
    changed = YES;
  }
  if (changed) {
    textView.typingAttributes = typing;
  }
}

#pragma mark - Applying

+ (void)addKern:(CGFloat)kern
        atIndex:(NSUInteger)index
             in:(NSTextStorage *)storage {
  NSRange range = NSMakeRange(index, 1);
  [storage addAttribute:NSKernAttributeName value:@(kern) range:range];
  [storage addAttribute:HashtagChipKernAttributeName value:@(YES) range:range];
}

/** Chip text in the chip font. The parser serializes styles' meta keys, not
 * fonts. */
+ (void)applyChipFontIn:(NSTextStorage *)storage range:(NSRange)token {
  [self save:NSFontAttributeName
        under:kOriginalFontKey
      inRange:token
           in:storage];
  NSMutableArray<NSArray *> *runs = [NSMutableArray array];
  [storage
      enumerateAttribute:kOriginalFontKey
                 inRange:token
                 options:0
              usingBlock:^(id value, NSRange range, BOOL *stop) {
                if ([value isKindOfClass:[UIFont class]]) {
                  [runs addObject:@[ [NSValue valueWithRange:range], value ]];
                }
              }];
  for (NSArray *run in runs) {
    CGFloat size = ((UIFont *)run[1]).pointSize * kChipFontScale;
    UIFont *chipFont = [UIFont fontWithName:kChipFontName size:size]
                           ?: [UIFont systemFontOfSize:size
                                                weight:UIFontWeightMedium];
    [storage addAttribute:NSFontAttributeName
                    value:chipFont
                    range:[(NSValue *)run[0] rangeValue]];
  }
}

/**
 * Room for a line that starts with a chip to move right by the chip's padding.
 * The 30pt height of a line holding a chip is set per line by
 * HashtagChipLayoutDelegate, not here: a paragraph style would raise every
 * line of the paragraph, wrapped text-only lines included.
 */
+ (void)applyChipLineIn:(NSTextStorage *)storage
              paragraph:(NSRange)paragraph
                  input:(EnrichedTextInputView *)input {
  [self save:NSParagraphStyleAttributeName
        under:kOriginalParagraphStyleKey
      inRange:paragraph
           in:storage];

  NSMutableArray<NSArray *> *styles = [NSMutableArray array];
  [storage
      enumerateAttribute:kOriginalParagraphStyleKey
                 inRange:paragraph
                 options:0
              usingBlock:^(id value, NSRange range, BOOL *stop) {
                if (value != nil) {
                  [styles addObject:@[ [NSValue valueWithRange:range], value ]];
                }
              }];
  for (NSArray *entry in styles) {
    NSParagraphStyle *original =
        entry[1] == [NSNull null] ? nil : (NSParagraphStyle *)entry[1];
    NSMutableParagraphStyle *style = original != nil
                                         ? [original mutableCopy]
                                         : [NSMutableParagraphStyle new];
    // Room for a line that starts with a chip to move right by the chip's
    // padding (HashtagChipLayoutDelegate). Wrapping is measured with it.
    style.tailIndent -= kPadding;
    [storage addAttribute:NSParagraphStyleAttributeName
                    value:style
                    range:[(NSValue *)entry[0] rangeValue]];
  }
}

+ (void)refreshInInput:(EnrichedTextInputView *)input {
  if (!input->hashtagChipsEnabled) {
    return;
  }
  UITextView *textView = input->textView;
  // Restyling marked text ends the composition (Korean, Japanese). The chip
  // that composition may create is picked up once it commits.
  if (textView.markedTextRange != nullptr) {
    return;
  }

  NSArray<NSDictionary *> *chips = [self findChipsInInput:input];
  NSTextStorage *storage = textView.textStorage;
  NSString *text = storage.string;
  NSCharacterSet *newlines = [NSCharacterSet newlineCharacterSet];

  [storage beginEditing];
  [self removeAllChipAttributesIn:storage];

  NSMutableSet<NSValue *> *paragraphs = [NSMutableSet set];
  for (NSDictionary *chip in chips) {
    NSRange token = [(NSValue *)chip[kRangeKey] rangeValue];
    BOOL textBefore = [chip[kTextBeforeKey] boolValue];
    BOOL textAfter = [chip[kTextAfterKey] boolValue];
    // Kern widens the character it sits on, so the room before the chip goes on
    // the whitespace in front of it. A line that starts with the chip is moved
    // instead (HashtagChipLayoutDelegate).
    if (token.location > 0 &&
        ![newlines
            characterIsMember:[text characterAtIndex:token.location - 1]]) {
      [self addKern:kPadding + (textBefore ? kTextGap : 0)
            atIndex:token.location - 1
                 in:storage];
    }
    [self addKern:kPadding + (textAfter ? kTextGap : 0)
          atIndex:NSMaxRange(token) - 1
               in:storage];
    // A marker the parser does not know, so the colour stays render-only: the
    // layout manager paints marked glyphs in the chip colour
    // (LayoutManagerExtension).
    [storage addAttribute:HashtagChipTextAttributeName
                    value:@(YES)
                    range:token];
    [self applyChipFontIn:storage range:token];
    [paragraphs
        addObject:[NSValue valueWithRange:[text paragraphRangeForRange:token]]];
  }
  for (NSValue *paragraph in paragraphs) {
    [self applyChipLineIn:storage paragraph:paragraph.rangeValue input:input];
  }
  [storage endEditing];
  [self cleanTypingAttributes:textView];

  input->hashtagChips = chips;
  [textView.layoutManager
      invalidateDisplayForCharacterRange:NSMakeRange(0, text.length)];
}

+ (void)clearInInput:(EnrichedTextInputView *)input {
  UITextView *textView = input->textView;
  NSTextStorage *storage = textView.textStorage;
  [storage beginEditing];
  [self removeAllChipAttributesIn:storage];
  [storage endEditing];
  [self cleanTypingAttributes:textView];
  input->hashtagChips = @[];
}

#pragma mark - Drawing

+ (void)drawChipsInInput:(EnrichedTextInputView *)input
           layoutManager:(NSLayoutManager *)layoutManager
                  origin:(CGPoint)origin
        visibleCharRange:(NSRange)visibleCharRange {
  if (!input->hashtagChipsEnabled || input->hashtagChips.count == 0) {
    return;
  }
  NSUInteger length = input->textView.textStorage.length;
  [ChipBackgroundColor() setFill];

  for (NSDictionary *chip in input->hashtagChips) {
    NSRange token = [(NSValue *)chip[kRangeKey] rangeValue];
    if (NSMaxRange(token) > length ||
        NSIntersectionRange(token, visibleCharRange).length == 0) {
      continue;
    }
    BOOL textAfter = [chip[kTextAfterKey] boolValue];
    NSRange glyphs = [layoutManager glyphRangeForCharacterRange:token
                                           actualCharacterRange:NULL];
    // A token too long for one line wraps, so a chip can have several pieces.
    [layoutManager
        enumerateLineFragmentsForGlyphRange:glyphs
                                 usingBlock:^(CGRect rect, CGRect usedRect,
                                              NSTextContainer *container,
                                              NSRange lineGlyphs, BOOL *stop) {
                                   NSRange part =
                                       NSIntersectionRange(lineGlyphs, glyphs);
                                   if (part.length == 0) {
                                     return;
                                   }
                                   BOOL isFirst =
                                       part.location == glyphs.location;
                                   BOOL isLast =
                                       NSMaxRange(part) == NSMaxRange(glyphs);
                                   // The bounds include the kern on the token's
                                   // last character: right padding and gap.
                                   CGRect bounds = [layoutManager
                                       boundingRectForGlyphRange:part
                                                 inTextContainer:container];
                                   CGFloat left = CGRectGetMinX(bounds) -
                                                  (isFirst ? kPadding : 0);
                                   CGFloat right =
                                       CGRectGetMaxX(bounds) -
                                       (isLast && textAfter ? kTextGap : 0);
                                   // Centred in its 30pt line like the text,
                                   // nudged down so the smaller chip glyphs
                                   // (sharing the body's baseline) sit centred
                                   // in it as they do in the detail.
                                   CGRect pill = CGRectMake(
                                       left + origin.x,
                                       CGRectGetMidY(rect) - kChipHeight / 2 +
                                           kPillOffsetY + origin.y,
                                       right - left, kChipHeight);
                                   [[UIBezierPath
                                       bezierPathWithRoundedRect:pill
                                                    cornerRadius:kChipHeight /
                                                                 2] fill];
                                 }];
  }
}

@end
