#pragma once
#import <UIKit/UIKit.h>

@class EnrichedTextInputView;

NS_ASSUME_NONNULL_BEGIN

/**
 * OpenStory: hashtags in a community post body drawn as chips while composing.
 *
 * Decoration only. The text stays plain `#tag`, so the HTML the input emits is
 * unchanged: the chip is a pill drawn behind the token, a render-only text
 * colour (a marker attribute the layout manager paints, see
 * LayoutManagerExtension), and `NSKern` on the characters
 * either side to make room for the pill's padding and its delete button. That
 * kern carries `HashtagChipKernAttributeName` so it can be told apart from the
 * epsilon kern ZeroWidthSpaceUtils puts on zero-width spaces.
 *
 * Recognition matches the server's (openstory-web rich-text-core): a `#` at the
 * start of a line or after whitespace, then everything up to the next
 * whitespace; at least one character other than `#`; at most 100 code points.
 * A token that holds the caret while the input is focused is still being typed
 * and stays plain, and a token inside a link keeps the link.
 */
extern NSAttributedStringKey const HashtagChipKernAttributeName;
/** Marks a chip's characters; the layout manager paints them in
 * `chipTextColor`. */
extern NSAttributedStringKey const HashtagChipTextAttributeName;

@interface HashtagChipUtils : NSObject

+ (UIColor *)chipTextColor;

/** Recomputes the chips and their spacing. No-op while IME composition is
 * active. */
+ (void)refreshInInput:(EnrichedTextInputView *)input;

/** Removes every chip attribute, for when the prop is switched off. */
+ (void)clearInInput:(EnrichedTextInputView *)input;

/** Draws the pills (and their delete buttons) that intersect
 * `visibleCharRange`. */
+ (void)drawChipsInInput:(EnrichedTextInputView *)input
           layoutManager:(NSLayoutManager *)layoutManager
                  origin:(CGPoint)origin
        visibleCharRange:(NSRange)visibleCharRange;

/**
 * The character range to delete when `point` (text view coordinates) hits a
 * chip's delete button: the token plus one adjacent space. `NSNotFound`
 * location when nothing was hit.
 */
+ (NSRange)deleteRangeAtPoint:(CGPoint)point
                      inInput:(EnrichedTextInputView *)input;

@end

NS_ASSUME_NONNULL_END
