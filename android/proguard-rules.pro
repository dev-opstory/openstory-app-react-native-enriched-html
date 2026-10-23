# InlineStyles and ParagraphStyles build spans reflectively through
# getDeclaredConstructor(HtmlStyle). Without this, R8 in a minified app inlines or
# strips those constructors and every bold/italic/underline/strikethrough toggle throws.
-keepclassmembers class com.swmansion.enriched.textinput.spans.** {
    <init>(com.swmansion.enriched.textinput.styles.HtmlStyle);
}
