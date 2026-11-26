typedef NS_ENUM(NSInteger, TextBlockTapKind) {
  TextBlockTapKindNone = 0,
  TextBlockTapKindCheckbox,
  // OpenStory: the delete button of a hashtag chip (HashtagChipUtils).
  TextBlockTapKindHashtagDelete,
};

@class EnrichedTextInputView;

@interface TextBlockTapGestureRecognizer : UITapGestureRecognizer
- (instancetype _Nonnull)initWithInput:(id _Nonnull)input
                                action:(SEL _Nonnull)action;

@property(nonatomic, weak) EnrichedTextInputView *input;

@property(nonatomic, assign, readonly) TextBlockTapKind tapKind;
@property(nonatomic, assign, readonly) NSInteger characterIndex;
/** For `TextBlockTapKindHashtagDelete`: the chip and its space. */
@property(nonatomic, assign, readonly) NSRange deleteRange;

@end
