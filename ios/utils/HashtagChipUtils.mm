#import "HashtagChipUtils.h"
#import "EnrichedTextInputView.h"
#import "StyleHeaders.h"

NSAttributedStringKey const HashtagChipKernAttributeName =
    @"EnrichedHashtagChipKern";
NSAttributedStringKey const HashtagChipTextAttributeName =
    @"EnrichedHashtagChipText";

// Web's editor chip (openstory-web rich-text-view + hashtagChipEditing), drawn
// inside the body's own 160% line instead of on a taller one: `measureSize:`
// sizes the input from the attributed string alone, so a per-line height from
// the layout manager would be drawn but never measured.
static const CGFloat kChipHeight = 24;
static const CGFloat kPaddingLeft = 8;
static const CGFloat kPaddingRight = 5;
static const CGFloat kDeleteGap = 8;
static const CGFloat kDeleteSize = 16;
static const CGFloat kDeleteGlyphSpan = 6;
static const CGFloat kDeleteGlyphStroke = 1.5;
/** A chip beside plain text keeps this much more room on that side. */
static const CGFloat kTextGap = 4;
/** Right part of the chip that counts as the delete button, as on web. */
static const CGFloat kDeleteHitWidth =
    kPaddingRight + kDeleteSize + kDeleteGap / 2;
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
static UIColor *DeleteBackgroundColor(void) {
  return [UIColor colorWithRed:0xCC / 255.0
                         green:0xD1 / 255.0
                          blue:0xE1 / 255.0
                         alpha:1];
}

@implementation HashtagChipUtils

+ (UIColor *)chipTextColor {
  return ChipTextColor();
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

  // Which sides have plain text on the same line, the way web decides its 4px
  // text gap: a neighbouring chip or the line's edge does not count.
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

+ (void)removeChipTextMarkerIn:(NSTextStorage *)storage {
  [storage removeAttribute:HashtagChipTextAttributeName
                     range:NSMakeRange(0, storage.length)];
}

+ (void)removeChipKernIn:(NSTextStorage *)storage {
  NSRange whole = NSMakeRange(0, storage.length);
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

+ (void)addKern:(CGFloat)kern
        atIndex:(NSUInteger)index
             in:(NSTextStorage *)storage {
  NSRange range = NSMakeRange(index, 1);
  [storage addAttribute:NSKernAttributeName value:@(kern) range:range];
  [storage addAttribute:HashtagChipKernAttributeName value:@(YES) range:range];
}

+ (void)stripChipKernFromTypingAttributes:(UITextView *)textView {
  NSDictionary *current = textView.typingAttributes;
  if (current[HashtagChipKernAttributeName] == nil &&
      current[HashtagChipTextAttributeName] == nil) {
    return;
  }
  NSMutableDictionary *typing = [current mutableCopy];
  if (typing[HashtagChipKernAttributeName] != nil) {
    [typing removeObjectForKey:NSKernAttributeName];
    [typing removeObjectForKey:HashtagChipKernAttributeName];
  }
  [typing removeObjectForKey:HashtagChipTextAttributeName];
  textView.typingAttributes = typing;
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
  [self removeChipKernIn:storage];
  [self removeChipTextMarkerIn:storage];
  for (NSDictionary *chip in chips) {
    NSRange token = [(NSValue *)chip[kRangeKey] rangeValue];
    BOOL textBefore = [chip[kTextBeforeKey] boolValue];
    BOOL textAfter = [chip[kTextAfterKey] boolValue];
    // Kern widens the character it sits on, so room before the chip goes on the
    // whitespace in front of it. At a line start there is none; the pill's left
    // padding then reaches past the text's edge (clipsToBounds is off).
    if (token.location > 0 &&
        ![newlines
            characterIsMember:[text characterAtIndex:token.location - 1]]) {
      [self addKern:kPaddingLeft + (textBefore ? kTextGap : 0)
            atIndex:token.location - 1
                 in:storage];
    }
    [self addKern:kPaddingRight + kDeleteGap + kDeleteSize +
                  (textAfter ? kTextGap : 0)
          atIndex:NSMaxRange(token) - 1
               in:storage];
    // A marker the parser does not know, so the colour stays render-only: the
    // layout manager paints marked glyphs in the chip colour
    // (LayoutManagerExtension). A real foreground colour would be rewritten by
    // dirty-range styling and carried into typing.
    [storage addAttribute:HashtagChipTextAttributeName
                    value:@(YES)
                    range:token];
  }
  [storage endEditing];
  [self stripChipKernFromTypingAttributes:textView];

  input->hashtagChips = chips;
  [textView.layoutManager
      invalidateDisplayForCharacterRange:NSMakeRange(0, text.length)];
}

+ (void)clearInInput:(EnrichedTextInputView *)input {
  UITextView *textView = input->textView;
  NSTextStorage *storage = textView.textStorage;
  [storage beginEditing];
  [self removeChipKernIn:storage];
  [self removeChipTextMarkerIn:storage];
  [storage endEditing];
  [self stripChipKernFromTypingAttributes:textView];
  input->hashtagChips = @[];
}

/**
 * Calls `block` with each pill rect of each chip, in text container
 * coordinates. A token too long for one line wraps, so a chip can have several
 * rects; only its last one carries the delete button.
 */
+ (void)enumeratePillsInInput:(EnrichedTextInputView *)input
                layoutManager:(NSLayoutManager *)layoutManager
                      inRange:(NSRange)charRange
                   usingBlock:(void (^)(NSRange token, CGRect pill,
                                        BOOL isLast))block {
  NSTextStorage *storage = input->textView.textStorage;
  for (NSDictionary *chip in input->hashtagChips) {
    NSRange token = [(NSValue *)chip[kRangeKey] rangeValue];
    if (NSMaxRange(token) > storage.length ||
        NSIntersectionRange(token, charRange).length == 0) {
      continue;
    }
    BOOL textAfter = [chip[kTextAfterKey] boolValue];
    UIFont *font = [storage attribute:NSFontAttributeName
                              atIndex:token.location
                       effectiveRange:NULL];
    NSRange glyphs = [layoutManager glyphRangeForCharacterRange:token
                                           actualCharacterRange:NULL];
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
                                   // last character: right padding, delete
                                   // button and gap.
                                   CGRect bounds = [layoutManager
                                       boundingRectForGlyphRange:part
                                                 inTextContainer:container];
                                   CGFloat left = CGRectGetMinX(bounds) -
                                                  (isFirst ? kPaddingLeft : 0);
                                   CGFloat right =
                                       CGRectGetMaxX(bounds) -
                                       (isLast && textAfter ? kTextGap : 0);
                                   CGPoint glyphOrigin = [layoutManager
                                       locationForGlyphAtIndex:part.location];
                                   CGFloat baseline =
                                       rect.origin.y + glyphOrigin.y;
                                   CGFloat center =
                                       font != nil
                                           ? baseline - (font.ascender +
                                                         font.descender) /
                                                            2
                                           : CGRectGetMidY(rect);
                                   block(token,
                                         CGRectMake(left,
                                                    center - kChipHeight / 2,
                                                    right - left, kChipHeight),
                                         isLast);
                                 }];
  }
}

+ (void)drawChipsInInput:(EnrichedTextInputView *)input
           layoutManager:(NSLayoutManager *)layoutManager
                  origin:(CGPoint)origin
        visibleCharRange:(NSRange)visibleCharRange {
  if (!input->hashtagChipsEnabled || input->hashtagChips.count == 0) {
    return;
  }
  [self enumeratePillsInInput:input
                layoutManager:layoutManager
                      inRange:visibleCharRange
                   usingBlock:^(NSRange token, CGRect pill, BOOL isLast) {
                     CGRect rect = CGRectOffset(pill, origin.x, origin.y);
                     [ChipBackgroundColor() setFill];
                     [[UIBezierPath
                         bezierPathWithRoundedRect:rect
                                      cornerRadius:rect.size.height / 2] fill];
                     if (!isLast) {
                       return;
                     }
                     CGRect circle = CGRectMake(
                         CGRectGetMaxX(rect) - kPaddingRight - kDeleteSize,
                         CGRectGetMidY(rect) - kDeleteSize / 2, kDeleteSize,
                         kDeleteSize);
                     [DeleteBackgroundColor() setFill];
                     [[UIBezierPath bezierPathWithOvalInRect:circle] fill];

                     CGFloat half = kDeleteGlyphSpan / 2;
                     CGPoint c = CGPointMake(CGRectGetMidX(circle),
                                             CGRectGetMidY(circle));
                     UIBezierPath *cross = [UIBezierPath bezierPath];
                     [cross moveToPoint:CGPointMake(c.x - half, c.y - half)];
                     [cross addLineToPoint:CGPointMake(c.x + half, c.y + half)];
                     [cross moveToPoint:CGPointMake(c.x + half, c.y - half)];
                     [cross addLineToPoint:CGPointMake(c.x - half, c.y + half)];
                     cross.lineWidth = kDeleteGlyphStroke;
                     cross.lineCapStyle = kCGLineCapRound;
                     [ChipTextColor() setStroke];
                     [cross stroke];
                   }];
}

+ (NSRange)deleteRangeAtPoint:(CGPoint)point
                      inInput:(EnrichedTextInputView *)input {
  __block NSRange hit = NSMakeRange(NSNotFound, 0);
  if (!input->hashtagChipsEnabled || input->hashtagChips.count == 0) {
    return hit;
  }
  UITextView *textView = input->textView;
  CGPoint inContainer = CGPointMake(point.x - textView.textContainerInset.left,
                                    point.y - textView.textContainerInset.top);
  NSString *text = textView.textStorage.string;
  [self enumeratePillsInInput:input
                layoutManager:textView.layoutManager
                      inRange:NSMakeRange(0, text.length)
                   usingBlock:^(NSRange token, CGRect pill, BOOL isLast) {
                     if (!isLast || hit.location != NSNotFound) {
                       return;
                     }
                     CGRect target =
                         CGRectMake(CGRectGetMaxX(pill) - kDeleteHitWidth,
                                    CGRectGetMinY(pill), kDeleteHitWidth,
                                    CGRectGetHeight(pill));
                     if (!CGRectContainsPoint(target, inContainer)) {
                       return;
                     }
                     hit = token;
                   }];
  if (hit.location == NSNotFound) {
    return hit;
  }

  // The token and one space with it, the one after first, so the text around
  // it does not end up doubly spaced (web does the same).
  NSCharacterSet *spaces = [NSCharacterSet whitespaceCharacterSet];
  if (NSMaxRange(hit) < text.length &&
      [spaces characterIsMember:[text characterAtIndex:NSMaxRange(hit)]]) {
    return NSMakeRange(hit.location, hit.length + 1);
  }
  if (hit.location > 0 &&
      [spaces characterIsMember:[text characterAtIndex:hit.location - 1]]) {
    return NSMakeRange(hit.location - 1, hit.length + 1);
  }
  return hit;
}

@end
