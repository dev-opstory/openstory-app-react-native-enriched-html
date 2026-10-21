#import "EnrichedTextTextView.h"
#import "EnrichedTextTouchHandler.h"
#import "EnrichedTextView.h"
#import "HtmlParser.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@implementation EnrichedTextTextView

// A non-scrolling UITextView sizes its container to its own bounds, and TextKit
// truncates whatever does not fit that height. Yoga hands the view its measured
// height through float32 layout, so a box measured at exactly two lines can
// arrive a few ten-thousandths of a point short — enough for TextKit to drop
// the second line behind an ellipsis, depending only on where the view sits on
// the page. The box already has the height measureSize asked for, and
// maximumNumberOfLines does the truncating the numberOfLines prop asks for, so
// the container height does nothing but add that failure. Unbound it.
- (void)layoutSubviews {
  [super layoutSubviews];
  NSTextContainer *container = self.textContainer;
  if (container.size.height != CGFLOAT_MAX) {
    container.size = CGSizeMake(container.size.width, CGFLOAT_MAX);
  }
}

- (void)copy:(id)sender {
  EnrichedTextView *host = self.host;
  if (host == nullptr) {
    return;
  }

  // remove zero width spaces before copying the text
  NSString *plainText = [host.textView.textStorage.string
      substringWithRange:host.textView.selectedRange];
  NSString *fixedPlainText =
      [plainText stringByReplacingOccurrencesOfString:@"\u200B" withString:@""];

  NSString *parsedHtml =
      [HtmlParser parseToHtmlFromRange:host.textView.selectedRange host:host];

  NSMutableAttributedString *attrStr = [[host.textView.textStorage
      attributedSubstringFromRange:host.textView.selectedRange] mutableCopy];
  NSRange fullAttrStrRange = NSMakeRange(0, attrStr.length);
  [attrStr.mutableString replaceOccurrencesOfString:@"\u200B"
                                         withString:@""
                                            options:0
                                              range:fullAttrStrRange];

  NSData *rtfData =
      [attrStr dataFromRange:NSMakeRange(0, attrStr.length)
          documentAttributes:@{
            NSDocumentTypeDocumentAttribute : NSRTFTextDocumentType
          }
                       error:nullptr];

  UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
  [pasteboard setItems:@[ @{
                UTTypeUTF8PlainText.identifier : fixedPlainText,
                UTTypeHTML.identifier : parsedHtml,
                UTTypeRTF.identifier : rtfData
              } ]];
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
  if (touches.count == 1) {
    UITouch *touch = touches.anyObject;
    CGPoint point = [touch locationInView:self];
    [self.touchHandler handleTouchBeganAtPoint:point];
  }
  [super touchesBegan:touches withEvent:event];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
  if (touches.count == 1) {
    UITouch *touch = touches.anyObject;
    CGPoint point = [touch locationInView:self];
    [self.touchHandler handleTouchEndedAtPoint:point];
  }
  [super touchesEnded:touches withEvent:event];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches
               withEvent:(UIEvent *)event {
  [self.touchHandler handleTouchCancelled];
  [super touchesCancelled:touches withEvent:event];
}

@end
