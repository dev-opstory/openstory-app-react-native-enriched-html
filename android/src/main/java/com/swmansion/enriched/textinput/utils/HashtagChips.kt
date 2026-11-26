package com.swmansion.enriched.textinput.utils

import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.text.Editable
import android.text.Spannable
import android.text.TextPaint
import android.text.style.ForegroundColorSpan
import android.text.style.LineHeightSpan
import android.text.style.MetricAffectingSpan
import android.text.style.ReplacementSpan
import com.facebook.react.views.text.ReactTypefaceUtils.applyStyles
import com.facebook.react.views.text.ReactTypefaceUtils.parseFontStyle
import com.facebook.react.views.text.ReactTypefaceUtils.parseFontWeight
import com.swmansion.enriched.common.pixelFromSpOrDp
import com.swmansion.enriched.textinput.EnrichedTextInputView
import com.swmansion.enriched.textinput.spans.EnrichedInputLinkSpan
import java.util.regex.Pattern
import kotlin.math.roundToInt

/**
 * OpenStory: hashtags in a community post body drawn as chips while composing.
 *
 * Decoration only. The text stays plain `#tag`, so the HTML is unchanged: the
 * span watcher and the parser ignore every span used here (none is an
 * `EnrichedInputSpan`). The chip looks like the one the app's post detail
 * draws: [FontSpan] sets the 14dp medium text, [EdgeSpan] widens the token's
 * first and last character for the pill's padding, [ColorSpan] colours it,
 * [LineSpan] makes its line 30dp, and [draw] paints the pills under the text.
 *
 * Recognition matches the server's (openstory-web rich-text-core) and the iOS
 * side: a `#` at the start of a line or after whitespace, then everything up to
 * the next whitespace; at least one character other than `#`; at most 100 code
 * points. A token holding the caret while the input is focused is still being
 * typed and stays plain, and a token inside a link keeps the link.
 */
class HashtagChips(
  private val view: EnrichedTextInputView,
) {
  data class Chip(
    val start: Int,
    val end: Int,
    val textBefore: Boolean,
    val textAfter: Boolean,
  )

  /** Widens one character by [before] and [after] px and draws it in the chip colour. */
  class EdgeSpan(
    val before: Float,
    val after: Float,
    private val color: Int,
  ) : ReplacementSpan() {
    override fun getSize(
      paint: Paint,
      text: CharSequence,
      start: Int,
      end: Int,
      fm: Paint.FontMetricsInt?,
    ): Int {
      if (fm != null) {
        paint.getFontMetricsInt(fm)
      }
      return (paint.measureText(text, start, end) + before + after).roundToInt()
    }

    override fun draw(
      canvas: Canvas,
      text: CharSequence,
      start: Int,
      end: Int,
      x: Float,
      top: Int,
      y: Int,
      bottom: Int,
      paint: Paint,
    ) {
      val previousColor = paint.color
      paint.color = color
      canvas.drawText(text, start, end, x + before, y.toFloat(), paint)
      paint.color = previousColor
    }
  }

  class ColorSpan(
    color: Int,
  ) : ForegroundColorSpan(color)

  /** Web's 14px medium chip text against the 16px body, relative so large text scales with it. */
  class FontSpan(
    private val typeface: Typeface,
  ) : MetricAffectingSpan() {
    override fun updateMeasureState(paint: TextPaint) = apply(paint)

    override fun updateDrawState(paint: TextPaint) = apply(paint)

    private fun apply(paint: TextPaint) {
      paint.textSize *= FONT_SCALE
      paint.typeface = typeface
    }
  }

  /**
   * A line holding a chip is 30dp with its text centred, as in the post detail.
   * Absolute, so it does not matter whether the input's own line height span
   * runs before or after it: that one only grows lines shorter than its height.
   */
  class LineSpan(
    private val heightPx: Int,
    private val paint: Paint,
  ) : LineHeightSpan {
    override fun chooseHeight(
      text: CharSequence,
      start: Int,
      end: Int,
      spanstartv: Int,
      v: Int,
      fm: Paint.FontMetricsInt,
    ) {
      val natural = paint.fontMetricsInt
      val extra = heightPx - (natural.descent - natural.ascent)
      if (extra <= 0) return
      fm.ascent = natural.ascent - extra / 2
      fm.descent = natural.descent + (extra - extra / 2)
      fm.top = minOf(fm.top, fm.ascent)
      fm.bottom = maxOf(fm.bottom, fm.descent)
    }
  }

  var enabled: Boolean = false
    private set

  var chips: List<Chip> = emptyList()
    private set

  private val density = view.resources.displayMetrics.density
  private val chipHeight = CHIP_HEIGHT * density
  private val padding = PADDING * density
  private val textGap = TEXT_GAP * density

  private val fillPaint =
    Paint(Paint.ANTI_ALIAS_FLAG).apply {
      style = Paint.Style.FILL
      color = CHIP_COLOR
    }
  private val rect = RectF()
  private val chipTypeface: Typeface by lazy {
    applyStyles(view.typeface, parseFontStyle(null), parseFontWeight(null), FONT_FAMILY, view.context.assets)
  }

  fun setEnabled(value: Boolean) {
    if (enabled == value) return
    enabled = value
    if (value) refresh() else clear()
  }

  /** Recomputes the chips and their spans. */
  fun refresh() {
    if (!enabled) return
    val text = view.text ?: return
    val next = findChips(text)
    if (next == chips && hasSpansFor(text, next)) return

    removeSpans(text)
    val lineHeight = pixelFromSpOrDp(CHIP_LINE_HEIGHT, view.allowFontScaling).toInt()
    val paragraphs = mutableSetOf<Pair<Int, Int>>()
    for (chip in next) {
      val left = padding + if (chip.textBefore) textGap else 0f
      val right = padding + if (chip.textAfter) textGap else 0f
      if (chip.end - chip.start == 1) {
        text.setSpan(EdgeSpan(left, right, TEXT_COLOR), chip.start, chip.end, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
      } else {
        text.setSpan(EdgeSpan(left, 0f, TEXT_COLOR), chip.start, chip.start + 1, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
        text.setSpan(EdgeSpan(0f, right, TEXT_COLOR), chip.end - 1, chip.end, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
      }
      if (chip.end - chip.start > 2) {
        text.setSpan(ColorSpan(TEXT_COLOR), chip.start + 1, chip.end - 1, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
      }
      // Over the whole token, edges included: a ReplacementSpan is measured and
      // drawn with the metric spans of its range already applied.
      text.setSpan(FontSpan(chipTypeface), chip.start, chip.end, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
      val paragraphStart = text.lastIndexOf('\n', chip.start - 1) + 1
      val paragraphEnd = text.indexOf('\n', chip.end).let { if (it == -1) text.length else it }
      paragraphs += paragraphStart to paragraphEnd
    }
    for ((start, end) in paragraphs) {
      text.setSpan(LineSpan(lineHeight, view.paint), start, end, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
    }
    chips = next
    // The edge spans change line widths, so wrapping and height can change with them.
    view.layoutManager.invalidateLayout()
    view.invalidate()
  }

  fun clear() {
    view.text?.let { removeSpans(it) }
    chips = emptyList()
    view.layoutManager.invalidateLayout()
    view.invalidate()
  }

  /** Draws the pills; call before the text is drawn. */
  fun draw(canvas: Canvas) {
    if (!enabled || chips.isEmpty()) return
    val layout = view.layout ?: return
    val textLength = view.text?.length ?: return

    canvas.save()
    canvas.translate(view.totalPaddingLeft.toFloat(), view.totalPaddingTop.toFloat())
    for (chip in chips) {
      if (chip.end > textLength) continue
      if (!pillRect(chip, rect)) continue
      canvas.drawRoundRect(rect, rect.height() / 2, rect.height() / 2, fillPaint)
    }
    canvas.restore()
  }

  /** The pill of a chip in layout coordinates; false when it wraps over lines (not drawn). */
  private fun pillRect(
    chip: Chip,
    out: RectF,
  ): Boolean {
    val layout = view.layout ?: return false
    val line = layout.getLineForOffset(chip.start)
    if (layout.getLineForOffset(chip.end - 1) != line) return false

    // Both edge spans are part of the measured run, so the token's own extent
    // already holds the padding; only the text gaps are outside.
    val left = layout.getPrimaryHorizontal(chip.start) + if (chip.textBefore) textGap else 0f
    val end =
      if (layout.getLineForOffset(chip.end) == line) {
        layout.getPrimaryHorizontal(chip.end)
      } else {
        layout.getLineRight(line)
      }
    val right = end - if (chip.textAfter) textGap else 0f

    // The text is centred in its 30dp line (LineSpan), so the pill is too: 2dp
    // clear above and below.
    val top = (layout.getLineTop(line) + layout.getLineBottom(line) - chipHeight) / 2
    out.set(left, top, right, top + chipHeight)
    return true
  }

  private fun findChips(text: Editable): List<Chip> {
    val typing = view.isFocused && view.selectionStart == view.selectionEnd
    val caret = view.selectionStart
    val tokens = mutableListOf<IntRange>()
    val matcher = TOKEN.matcher(text)
    while (matcher.find()) {
      val start = matcher.start(2)
      val end = matcher.end(2)
      val tag = text.substring(start + 1, end)
      if (tag.trim('#').isEmpty() || tag.codePointCount(0, tag.length) > MAX_TAG_LENGTH) continue
      // Still being typed: the caret sits inside the token or right after it.
      if (typing && caret > start && caret <= end) continue
      if (text.getSpans(start, end, EnrichedInputLinkSpan::class.java).isNotEmpty()) continue
      tokens += start until end
    }

    // Which sides have plain text on the same line, the way web decides its 4px gap:
    // a neighbouring chip or the line's edge does not count.
    return tokens.mapIndexed { i, token ->
      val start = token.first
      val end = token.last + 1
      val lineStart = text.lastIndexOf('\n', start - 1) + 1
      val lineEnd = text.indexOf('\n', end).let { if (it == -1) text.length else it }
      val before = maxOf(lineStart, if (i > 0) tokens[i - 1].last + 1 else lineStart)
      val after = minOf(lineEnd, if (i + 1 < tokens.size) tokens[i + 1].first else lineEnd)
      Chip(
        start = start,
        end = end,
        textBefore = (before until start).any { !Character.isWhitespace(text[it]) },
        textAfter = (end until after).any { !Character.isWhitespace(text[it]) },
      )
    }
  }

  private fun hasSpansFor(
    text: Editable,
    expected: List<Chip>,
  ): Boolean {
    val expectedSpans = expected.fold(0) { count, chip -> count + if (chip.end - chip.start == 1) 1 else 2 }
    return text.getSpans(0, text.length, EdgeSpan::class.java).size == expectedSpans
  }

  private fun removeSpans(text: Editable) {
    for (span in text.getSpans(0, text.length, EdgeSpan::class.java)) text.removeSpan(span)
    for (span in text.getSpans(0, text.length, ColorSpan::class.java)) text.removeSpan(span)
    for (span in text.getSpans(0, text.length, FontSpan::class.java)) text.removeSpan(span)
    for (span in text.getSpans(0, text.length, LineSpan::class.java)) text.removeSpan(span)
  }

  companion object {

    // Android's regex is ICU, so `\s` already covers Unicode whitespace (no-break and
    // ideographic spaces) as on iOS and web. `UNICODE_CHARACTER_CLASS` is not supported
    // there and throws: in this initializer it crashed every input on mount.
    private val TOKEN = Pattern.compile("(^|\\s)(#\\S+)", Pattern.MULTILINE)
    private const val MAX_TAG_LENGTH = 100

    // The chip the app's post detail draws (HashtagChip), in dp.
    private const val CHIP_HEIGHT = 26f
    private const val PADDING = 8f
    private const val TEXT_GAP = 4f
    private const val CHIP_LINE_HEIGHT = 30f
    private const val FONT_SCALE = 14f / 16f
    private const val FONT_FAMILY = "Pretendard-Medium"

    private val CHIP_COLOR = Color.parseColor("#E3E6F0")
    private val TEXT_COLOR = Color.parseColor("#4B5061")
  }
}
