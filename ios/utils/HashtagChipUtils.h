#pragma once
#import <UIKit/UIKit.h>

@class EnrichedTextInputView;

NS_ASSUME_NONNULL_BEGIN

/**
 * OpenStory: hashtags in a community post body drawn as chips while composing.
 *
 * Decoration only. The text stays plain `#tag`, so the HTML the input emits is
 * unchanged. The chip looks like the one the app's post detail draws: a pill
 * behind the token, the tag in a 14pt medium font, its line 30pt tall with the
 * text centred. Font, paragraph style and baseline offset are swapped on the
 * token's characters with the originals saved under marker keys, the colour
 * is painted at draw time from a marker the parser ignores, and `NSKern` on the
 * characters either side makes room for the padding. That kern carries
 * `HashtagChipKernAttributeName` so it can be told apart from the epsilon kern
 * ZeroWidthSpaceUtils puts on zero-width spaces.
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

/**
 * Moves a line that starts with a chip right by the chip's left padding, so the
 * pill begins at the text's edge with the `#` inside it, as in the post detail.
 * Kern cannot do it: it widens the character before the chip, and a line start
 * has none. Set as the input's layout manager delegate while chips are on.
 */
@interface HashtagChipLayoutDelegate : NSObject <NSLayoutManagerDelegate>
@property(nonatomic, weak) EnrichedTextInputView *input;
@end

@interface HashtagChipUtils : NSObject

+ (UIColor *)chipTextColor;

/** Recomputes the chips and their spacing. No-op while IME composition is
 * active. */
+ (void)refreshInInput:(EnrichedTextInputView *)input;

/** Removes every chip attribute, for when the prop is switched off. */
+ (void)clearInInput:(EnrichedTextInputView *)input;

/** Draws the pills that intersect `visibleCharRange`. */
+ (void)drawChipsInInput:(EnrichedTextInputView *)input
           layoutManager:(NSLayoutManager *)layoutManager
                  origin:(CGPoint)origin
        visibleCharRange:(NSRange)visibleCharRange;

@end

NS_ASSUME_NONNULL_END
