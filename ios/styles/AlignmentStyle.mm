#import "AlignmentUtils.h"
#import "StyleHeaders.h"
#import "TextListsUtils.h"

@implementation AlignmentStyle

+ (StyleType)getType {
  return Alignment;
}

- (NSString *)getValue {
  return @"EnrichedAlignmentNatural";
}

- (NSString *)getMarkerPrefix {
  return @"EnrichedAlignment";
}

- (BOOL)isParagraph {
  return YES;
}

- (BOOL)appliesStylingToTyping {
  return YES;
}

- (void)toggle:(NSRange)range {
  // no-op for alignments
}

- (void)applyStyling:(NSRange)range {
  [self.host.textView.textStorage
      enumerateAttribute:NSParagraphStyleAttributeName
                 inRange:range
                 options:0
              usingBlock:^(id _Nullable value, NSRange subRange,
                           BOOL *_Nonnull stop) {
                NSMutableParagraphStyle *pStyle =
                    [(NSParagraphStyle *)value mutableCopy];

                NSString *marker =
                    [TextListsUtils
                        firstTextListWithPrefix:[self getMarkerPrefix]
                                        inArray:pStyle.textLists]
                        .markerFormat;
                NSTextAlignment alignment =
                    [AlignmentUtils markerToAlignment:marker];
                pStyle.alignment = alignment;
                [self.host.textView.textStorage
                    addAttribute:NSParagraphStyleAttributeName
                           value:pStyle
                           range:subRange];
              }];
}

- (NSRange)actualUsedRange:(NSRange)range {
  NSRange paragraphRange =
      [self.host.textView.textStorage.string paragraphRangeForRange:range];
  return [self expandRangeToContiguousList:paragraphRange];
}

- (void)addAlignment:(NSTextAlignment)alignment
               range:(NSRange)range
          withTyping:(BOOL)withTyping
      withDirtyRange:(BOOL)withDirtyRange {
  NSString *value = [AlignmentUtils alignmentToMarker:alignment];

  [self add:range
           withValue:value
          withTyping:withTyping
      withDirtyRange:withDirtyRange];
}

- (BOOL)styleCondition:(id)value range:(NSRange)range {
  NSParagraphStyle *pStyle = (NSParagraphStyle *)value;
  if (pStyle == nil)
    return NO;
  return [TextListsUtils textLists:pStyle.textLists
                    containsPrefix:[self getMarkerPrefix]];
}

- (void)reapplyFromStylePair:(StylePair *)pair {
  NSRange range = [pair.rangeValue rangeValue];
  NSParagraphStyle *savedPStyle = pair.styleValue;
  NSString *markerFormat =
      [TextListsUtils firstTextListWithPrefix:[self getMarkerPrefix]
                                      inArray:savedPStyle.textLists]
          .markerFormat;
  if (markerFormat == nil)
    return;

  [self add:range withValue:markerFormat withTyping:NO withDirtyRange:NO];
}

- (NSString *)getStyleState {
  UITextView *textView = self.host.textView;
  NSParagraphStyle *paraStyle =
      textView.typingAttributes[NSParagraphStyleAttributeName];

  NSString *marker =
      [TextListsUtils firstTextListWithPrefix:[self getMarkerPrefix]
                                      inArray:paraStyle.textLists]
          .markerFormat;

  NSTextAlignment currentAlignment = [AlignmentUtils markerToAlignment:marker];
  return [AlignmentUtils alignmentToString:currentAlignment];
}

- (void)applyStylingToTypingAttrs:(NSMutableDictionary *)attributes {
  NSMutableParagraphStyle *pStyle =
      [attributes[NSParagraphStyleAttributeName] mutableCopy];
  if (pStyle == nil)
    return;
  NSString *marker =
      [TextListsUtils firstTextListWithPrefix:[self getMarkerPrefix]
                                      inArray:pStyle.textLists]
          .markerFormat;
  NSTextAlignment alignment = [AlignmentUtils markerToAlignment:marker];
  pStyle.alignment = alignment;
  attributes[NSParagraphStyleAttributeName] = pStyle;
}

- (NSRange)expandRangeToContiguousList:(NSRange)range {
  NSString *text = self.host.textView.textStorage.string;
  if (text.length == 0)
    return range;

  NSArray<StyleBase *> *listStyles = @[
    self.host.stylesDict[@([UnorderedListStyle getType])],
    self.host.stylesDict[@([OrderedListStyle getType])],
    self.host.stylesDict[@([CheckboxListStyle getType])]
  ];

  NSRange expandedRange = range;

  // Expand Backward
  NSRange startParagraph =
      [text paragraphRangeForRange:NSMakeRange(range.location, 0)];

  // Find which list style is active at the start
  StyleBase *activeStartStyle = nil;
  for (StyleBase *style in listStyles) {
    if ([style detect:startParagraph]) {
      activeStartStyle = style;
      break;
    }
  }

  // If we found a list style, walk backwards until it stops
  if (activeStartStyle) {
    NSRange currentPara = startParagraph;
    while (currentPara.location > 0) {
      // Check the paragraph before the current one
      NSRange prevPara = [text
          paragraphRangeForRange:NSMakeRange(currentPara.location - 1, 0)];

      if ([activeStartStyle detect:prevPara]) {
        // It's still the same list -> Expand our range.
        expandedRange = NSUnionRange(expandedRange, prevPara);
        currentPara = prevPara;
      } else {
        // The list ended here.
        break;
      }
    }
  }

  // Expand forward, we check the paragraph at the end of the current selection
  NSUInteger endLoc =
      (range.length > 0) ? (NSMaxRange(range) - 1) : range.location;
  NSRange endParagraph = [text paragraphRangeForRange:NSMakeRange(endLoc, 0)];

  // Find which list style is active at the end
  StyleBase *activeEndStyle = nil;
  for (StyleBase *style in listStyles) {
    if ([style detect:endParagraph]) {
      activeEndStyle = style;
      break;
    }
  }

  // If we found a list style, walk forwards until it stops
  if (activeEndStyle) {
    NSRange currentPara = endParagraph;
    while (NSMaxRange(currentPara) < text.length) {
      // Check the paragraph after the current one
      NSRange nextPara =
          [text paragraphRangeForRange:NSMakeRange(NSMaxRange(currentPara), 0)];

      if ([activeEndStyle detect:nextPara]) {
        // It's still the same list -> expand our range.
        expandedRange = NSUnionRange(expandedRange, nextPara);
        currentPara = nextPara;
      } else {
        break;
      }
    }
  }

  return expandedRange;
}

@end

// MARK: - Indent and bullet

static NSString *const kIndentMarkerPrefix = @"EnrichedIndent";
static NSString *const kBulletMarker = @"EnrichedBullet";
static NSString *const kCenterMarker = @"EnrichedAlignmentCenter";
static const NSInteger kMaxIndentLevel = 3;

@implementation IndentStyle

+ (StyleType)getType {
  return Indent;
}

- (NSString *)getValue {
  return @"EnrichedIndent1";
}

- (NSString *)getMarkerPrefix {
  return kIndentMarkerPrefix;
}

- (BOOL)isParagraph {
  return YES;
}

- (BOOL)appliesStylingToTyping {
  return YES;
}

- (void)toggle:(NSRange)range {
  // levels change through changeLevelBy:inRange: only
}

+ (NSInteger)levelInParagraphStyle:(NSParagraphStyle *)pStyle {
  NSString *marker =
      [TextListsUtils firstTextListWithPrefix:kIndentMarkerPrefix
                                      inArray:pStyle.textLists]
          .markerFormat;
  if (marker == nil) {
    return 0;
  }
  NSInteger level =
      [[marker substringFromIndex:kIndentMarkerPrefix.length] integerValue];
  return MAX(0, MIN(level, kMaxIndentLevel));
}

+ (BOOL)isBulletInParagraphStyle:(NSParagraphStyle *)pStyle {
  return [TextListsUtils textLists:pStyle.textLists
                     containsValue:kBulletMarker];
}

+ (BOOL)isCenteredParagraphStyle:(NSParagraphStyle *)pStyle {
  return [TextListsUtils textLists:pStyle.textLists
                     containsValue:kCenterMarker];
}

// Two characters of the base font per level, whatever size the line's own text
// is.
- (CGFloat)indentWidth {
  return 2 * [[self.host.config primaryFontSize] floatValue];
}

- (void)applyIndentTo:(NSMutableParagraphStyle *)pStyle {
  CGFloat indent =
      [IndentStyle levelInParagraphStyle:pStyle] * [self indentWidth];
  pStyle.headIndent = indent;
  pStyle.firstLineHeadIndent = indent;
}

- (void)applyStyling:(NSRange)range {
  NSTextStorage *storage = self.host.textView.textStorage;
  [storage enumerateAttribute:NSParagraphStyleAttributeName
                      inRange:range
                      options:0
                   usingBlock:^(id _Nullable value, NSRange subRange,
                                BOOL *_Nonnull stop) {
                     NSMutableParagraphStyle *pStyle =
                         [(NSParagraphStyle *)value mutableCopy];
                     if (pStyle == nil)
                       return;
                     [self applyIndentTo:pStyle];
                     [storage addAttribute:NSParagraphStyleAttributeName
                                     value:pStyle
                                     range:subRange];
                   }];
}

- (void)applyStylingToTypingAttrs:(NSMutableDictionary *)attributes {
  NSMutableParagraphStyle *pStyle =
      [attributes[NSParagraphStyleAttributeName] mutableCopy];
  if (pStyle == nil)
    return;
  [self applyIndentTo:pStyle];
  attributes[NSParagraphStyleAttributeName] = pStyle;
}

- (BOOL)styleCondition:(id)value range:(NSRange)range {
  NSParagraphStyle *pStyle = (NSParagraphStyle *)value;
  return pStyle != nil && [TextListsUtils textLists:pStyle.textLists
                                     containsPrefix:kIndentMarkerPrefix];
}

- (void)reapplyFromStylePair:(StylePair *)pair {
  NSParagraphStyle *savedPStyle = pair.styleValue;
  NSString *marker =
      [TextListsUtils firstTextListWithPrefix:kIndentMarkerPrefix
                                      inArray:savedPStyle.textLists]
          .markerFormat;
  if (marker == nil)
    return;
  [self add:[pair.rangeValue rangeValue]
       withValue:marker
      withTyping:NO
  withDirtyRange:NO];
}

// The trailing empty paragraph has no characters, so typing attributes are the
// only place its style lives.
- (NSParagraphStyle *)paragraphStyleOf:(NSRange)paragraph {
  UITextView *textView = self.host.textView;
  if (paragraph.length > 0) {
    return [textView.textStorage attribute:NSParagraphStyleAttributeName
                                   atIndex:paragraph.location
                            effectiveRange:nil];
  }
  return textView.typingAttributes[NSParagraphStyleAttributeName];
}

// Paragraphs a selection acts on. A range only touches a line it covers at
// least one character of; an empty line counts when the range starts at or
// before it and runs past its start. A collapsed caret acts on its own line.
- (NSArray<NSValue *> *)paragraphsTouchedBy:(NSRange)range {
  NSString *string = self.host.textView.textStorage.string;
  NSRange first =
      [string paragraphRangeForRange:NSMakeRange(range.location, 0)];
  if (range.length == 0) {
    return @[ [NSValue valueWithRange:first] ];
  }

  NSMutableArray<NSValue *> *result = [NSMutableArray array];
  NSRange paragraph = first;
  while (YES) {
    NSUInteger contentEnd = NSMaxRange(paragraph);
    while (contentEnd > paragraph.location &&
           [[NSCharacterSet newlineCharacterSet]
               characterIsMember:[string characterAtIndex:contentEnd - 1]]) {
      contentEnd--;
    }
    BOOL isEmpty = contentEnd == paragraph.location;
    BOOL touched =
        isEmpty ? (range.location <= paragraph.location &&
                   NSMaxRange(range) > paragraph.location)
                : (range.location < contentEnd &&
                   NSMaxRange(range) > paragraph.location);
    if (touched) {
      [result addObject:[NSValue valueWithRange:paragraph]];
    }
    if (NSMaxRange(paragraph) >= NSMaxRange(range) ||
        NSMaxRange(paragraph) >= string.length) {
      break;
    }
    paragraph = [string
        paragraphRangeForRange:NSMakeRange(NSMaxRange(paragraph), 0)];
  }
  return result;
}

- (void)setLevel:(NSInteger)level
              bullet:(BOOL)bullet
    inParagraphRange:(NSRange)range {
  NSInteger clamped = MAX(bullet ? 1 : 0, MIN(level, kMaxIndentLevel));
  NSArray<NSTextList *> * (^update)(NSArray<NSTextList *> *) =
      ^NSArray<NSTextList *> *(NSArray<NSTextList *> *lists) {
        lists = [TextListsUtils textListsByRemovingPrefix:kIndentMarkerPrefix
                                                fromArray:lists];
        lists = [TextListsUtils textListsByRemoving:kBulletMarker
                                         withPrefix:nil
                                          fromArray:lists];
        if (clamped > 0) {
          lists = [TextListsUtils
                textListsByAdding:[NSString
                                      stringWithFormat:@"%@%ld",
                                                       kIndentMarkerPrefix,
                                                       (long)clamped]
              withExclusivePrefix:kIndentMarkerPrefix
                          toArray:lists];
        }
        if (bullet) {
          lists = [TextListsUtils textListsByAdding:kBulletMarker
                                withExclusivePrefix:nil
                                            toArray:lists];
        }
        return lists;
      };

  UITextView *textView = self.host.textView;
  if (range.length == 0) {
    NSMutableDictionary *typingAttrs = [textView.typingAttributes mutableCopy];
    NSMutableParagraphStyle *pStyle =
        [typingAttrs[NSParagraphStyleAttributeName] mutableCopy]
            ?: [[NSMutableParagraphStyle alloc] init];
    pStyle.textLists = update(pStyle.textLists);
    [self applyIndentTo:pStyle];
    typingAttrs[NSParagraphStyleAttributeName] = pStyle;
    textView.typingAttributes = typingAttrs;
    return;
  }

  NSTextStorage *storage = textView.textStorage;
  [storage enumerateAttribute:NSParagraphStyleAttributeName
                      inRange:range
                      options:0
                   usingBlock:^(id _Nullable value, NSRange subRange,
                                BOOL *_Nonnull stop) {
                     NSMutableParagraphStyle *pStyle =
                         [(NSParagraphStyle *)value mutableCopy]
                             ?: [[NSMutableParagraphStyle alloc] init];
                     pStyle.textLists = update(pStyle.textLists);
                     [storage addAttribute:NSParagraphStyleAttributeName
                                     value:pStyle
                                     range:subRange];
                   }];
  [self.host.attributesManager addDirtyRange:range];
}

// Markers were written straight into the storage, so the caret's typing
// attributes still carry the old ones; copy them over or the next character
// typed would bring the old level back.
- (void)syncTypingAttributes {
  UITextView *textView = self.host.textView;
  NSRange paragraph = [textView.textStorage.string
      paragraphRangeForRange:NSMakeRange(textView.selectedRange.location, 0)];
  if (paragraph.length == 0) {
    return;
  }
  NSParagraphStyle *stored =
      [textView.textStorage attribute:NSParagraphStyleAttributeName
                              atIndex:paragraph.location
                       effectiveRange:nil];
  NSMutableDictionary *typingAttrs = [textView.typingAttributes mutableCopy];
  NSMutableParagraphStyle *pStyle =
      [typingAttrs[NSParagraphStyleAttributeName] mutableCopy]
          ?: [[NSMutableParagraphStyle alloc] init];
  pStyle.textLists = stored.textLists;
  [self applyIndentTo:pStyle];
  typingAttrs[NSParagraphStyleAttributeName] = pStyle;
  textView.typingAttributes = typingAttrs;
}

- (void)changeLevelBy:(NSInteger)delta inRange:(NSRange)range {
  for (NSValue *value in [self paragraphsTouchedBy:range]) {
    NSRange paragraph = [value rangeValue];
    NSParagraphStyle *pStyle = [self paragraphStyleOf:paragraph];
    // centred paragraphs take no indent
    if ([IndentStyle isCenteredParagraphStyle:pStyle]) {
      continue;
    }
    // a bullet only moves between levels 1-3; outdenting level 1 keeps it
    [self setLevel:[IndentStyle levelInParagraphStyle:pStyle] + delta
                  bullet:[IndentStyle isBulletInParagraphStyle:pStyle]
        inParagraphRange:paragraph];
  }
  [self syncTypingAttributes];
}

- (void)toggleBulletInRange:(NSRange)range {
  NSMutableArray<NSValue *> *paragraphs = [NSMutableArray array];
  BOOL allBulleted = YES;
  for (NSValue *value in [self paragraphsTouchedBy:range]) {
    NSParagraphStyle *pStyle = [self paragraphStyleOf:[value rangeValue]];
    if ([IndentStyle isCenteredParagraphStyle:pStyle]) {
      continue;
    }
    [paragraphs addObject:value];
    allBulleted =
        allBulleted && [IndentStyle isBulletInParagraphStyle:pStyle];
  }
  if (paragraphs.count == 0) {
    return;
  }
  // Removing a bullet keeps the line's level; adding one to an unindented line
  // starts it at level 1.
  for (NSValue *value in paragraphs) {
    NSRange paragraph = [value rangeValue];
    NSParagraphStyle *pStyle = [self paragraphStyleOf:paragraph];
    [self setLevel:[IndentStyle levelInParagraphStyle:pStyle]
                  bullet:!allBulleted
        inParagraphRange:paragraph];
  }
  [self syncTypingAttributes];
}

// Centring drops indent and bullets from the paragraphs it applies to, which
// are the whole paragraphs the range intersects.
- (void)clearInRange:(NSRange)range {
  NSString *string = self.host.textView.textStorage.string;
  NSRange covered = [string paragraphRangeForRange:range];
  NSRange paragraph =
      [string paragraphRangeForRange:NSMakeRange(covered.location, 0)];
  while (YES) {
    [self setLevel:0 bullet:NO inParagraphRange:paragraph];
    if (NSMaxRange(paragraph) >= NSMaxRange(covered) ||
        NSMaxRange(paragraph) >= string.length) {
      break;
    }
    paragraph = [string
        paragraphRangeForRange:NSMakeRange(NSMaxRange(paragraph), 0)];
  }
  [self syncTypingAttributes];
}

- (BOOL)isParagraphEmpty:(NSRange)paragraph {
  NSString *content =
      [self.host.textView.textStorage.string substringWithRange:paragraph];
  NSMutableCharacterSet *blank = [NSMutableCharacterSet newlineCharacterSet];
  [blank addCharactersInString:@"​"];
  return [content stringByTrimmingCharactersInSet:blank].length == 0;
}

- (BOOL)handleKeyInRange:(NSRange)range replacementText:(NSString *)text {
  UITextView *textView = self.host.textView;
  // leave IME composition (Korean, Japanese) to the system
  if (textView.markedTextRange != nil) {
    return NO;
  }
  NSString *string = textView.textStorage.string;
  NSRange selection = textView.selectedRange;

  if ([text isEqualToString:@"\t"]) {
    [self changeLevelBy:1 inRange:selection];
    return YES;
  }

  // Enter on an empty bullet steps it out one level, and off at level 1.
  if ([text isEqualToString:@"\n"]) {
    if (range.length > 0) {
      return NO;
    }
    NSRange paragraph =
        [string paragraphRangeForRange:NSMakeRange(range.location, 0)];
    NSParagraphStyle *pStyle = [self paragraphStyleOf:paragraph];
    if (![IndentStyle isBulletInParagraphStyle:pStyle] ||
        ![self isParagraphEmpty:paragraph]) {
      return NO;
    }
    NSInteger level = [IndentStyle levelInParagraphStyle:pStyle];
    if (level > 1) {
      [self setLevel:level - 1 bullet:YES inParagraphRange:paragraph];
    } else {
      [self setLevel:0 bullet:NO inParagraphRange:paragraph];
    }
    [self syncTypingAttributes];
    return YES;
  }

  // Backspace at the start of an indented line outdents it instead of joining
  // it to the line above. Bullets are left to the zero-width-space handling,
  // which drops the bullet and keeps the level.
  if (text.length == 0 && selection.length == 0) {
    NSUInteger caret = selection.location;
    BOOL atParagraphStart =
        caret == 0 || [[NSCharacterSet newlineCharacterSet]
                          characterIsMember:[string characterAtIndex:caret - 1]];
    if (!atParagraphStart) {
      return NO;
    }
    NSRange paragraph = [string paragraphRangeForRange:NSMakeRange(caret, 0)];
    NSParagraphStyle *pStyle = [self paragraphStyleOf:paragraph];
    NSInteger level = [IndentStyle levelInParagraphStyle:pStyle];
    if ([IndentStyle isBulletInParagraphStyle:pStyle] || level == 0) {
      return NO;
    }
    [self setLevel:level - 1 bullet:NO inParagraphRange:paragraph];
    [self syncTypingAttributes];
    return YES;
  }

  return NO;
}

@end

@implementation BulletStyle

+ (StyleType)getType {
  return Bullet;
}

- (NSString *)getValue {
  return kBulletMarker;
}

- (BOOL)isParagraph {
  return YES;
}

// an empty bullet line still has to show its marker
- (BOOL)needsZWS {
  return YES;
}

- (void)toggle:(NSRange)range {
  // bullets toggle through IndentStyle, which keeps the level in step
}

@end
