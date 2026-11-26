package com.swmansion.enriched.textinput.utils

import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.text.Editable
import android.text.Spannable
import android.text.style.ForegroundColorSpan
import android.text.style.ReplacementSpan
import com.swmansion.enriched.textinput.EnrichedTextInputView
import com.swmansion.enriched.textinput.spans.EnrichedInputLinkSpan
import java.util.regex.Pattern
import kotlin.math.roundToInt

/**
 * OpenStory: hashtags in a community post body drawn as chips while composing.
 *
 * Decoration only. The text stays plain `#tag`, so the HTML is unchanged: the
 * span watcher and the parser ignore both spans used here (neither is an
 * `EnrichedInputSpan`). [EdgeSpan] widens the token's first and last character
 * to make room for the pill's padding and delete button, [ColorSpan] sets the
 * chip text colour, and [draw] paints the pills under the text.
 *
 * Recognition matches the server's (openstory-web rich-text-core) and the iOS
 * side: a `#` at the start of a line or after whitespace, then everything up to
 * the next whitespace; at least one character other than `#`; at most 100 code
 * points. A token holding the caret while the input is focused is still being
 * typed and stays plain, and a token inside a link keeps the link.
 *
 * The pill fits inside the body's own 160% line (web pins chip lines to 30px):
 * a taller line would need its own line height span, and the composer's line
 * probes measure every line at the body's leading.
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

  var enabled: Boolean = false
    private set

  var chips: List<Chip> = emptyList()
    private set

  private val density = view.resources.displayMetrics.density
  private val chipHeight = CHIP_HEIGHT * density
  private val paddingLeft = PADDING_LEFT * density
  private val paddingRight = PADDING_RIGHT * density
  private val deleteGap = DELETE_GAP * density
  private val deleteSize = DELETE_SIZE * density
  private val deleteGlyphSpan = DELETE_GLYPH_SPAN * density
  private val textGap = TEXT_GAP * density
  private val deleteHitWidth = (PADDING_RIGHT + DELETE_SIZE + DELETE_GAP / 2) * density

  private val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
  private val crossPaint =
    Paint(Paint.ANTI_ALIAS_FLAG).apply {
      style = Paint.Style.STROKE
      strokeWidth = DELETE_GLYPH_STROKE * density
      strokeCap = Paint.Cap.ROUND
      color = TEXT_COLOR
    }
  private val rect = RectF()

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
    for (chip in next) {
      val left = paddingLeft + if (chip.textBefore) textGap else 0f
      val right = paddingRight + deleteGap + deleteSize + if (chip.textAfter) textGap else 0f
      if (chip.end - chip.start == 1) {
        text.setSpan(EdgeSpan(left, right, TEXT_COLOR), chip.start, chip.end, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
      } else {
        text.setSpan(EdgeSpan(left, 0f, TEXT_COLOR), chip.start, chip.start + 1, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
        text.setSpan(EdgeSpan(0f, right, TEXT_COLOR), chip.end - 1, chip.end, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
      }
      if (chip.end - chip.start > 2) {
        text.setSpan(ColorSpan(TEXT_COLOR), chip.start + 1, chip.end - 1, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
      }
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
      fillPaint.color = CHIP_COLOR
      canvas.drawRoundRect(rect, rect.height() / 2, rect.height() / 2, fillPaint)

      val cx = rect.right - paddingRight - deleteSize / 2
      val cy = rect.centerY()
      fillPaint.color = DELETE_COLOR
      canvas.drawCircle(cx, cy, deleteSize / 2, fillPaint)
      val half = deleteGlyphSpan / 2
      canvas.drawLine(cx - half, cy - half, cx + half, cy + half, crossPaint)
      canvas.drawLine(cx + half, cy - half, cx - half, cy + half, crossPaint)
    }
    canvas.restore()
  }

  /**
   * The range to delete when (x, y) in view coordinates hits a chip's delete
   * button: the token and one adjacent space. Null when nothing was hit.
   */
  fun deleteRangeAt(
    x: Float,
    y: Float,
  ): IntRange? {
    if (!enabled || chips.isEmpty()) return null
    val text = view.text ?: return null
    val lx = x - view.totalPaddingLeft + view.scrollX
    val ly = y - view.totalPaddingTop + view.scrollY
    for (chip in chips) {
      if (chip.end > text.length || !pillRect(chip, rect)) continue
      if (lx >= rect.right - deleteHitWidth && lx <= rect.right && ly >= rect.top && ly <= rect.bottom) {
        if (chip.end < text.length && isSpace(text[chip.end])) return chip.start until chip.end + 1
        if (chip.start > 0 && isSpace(text[chip.start - 1])) return chip.start - 1 until chip.end
        return chip.start until chip.end
      }
    }
    return null
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
    // already holds the padding and the delete button; only the text gaps are outside.
    val left = layout.getPrimaryHorizontal(chip.start) + if (chip.textBefore) textGap else 0f
    val end =
      if (layout.getLineForOffset(chip.end) == line) {
        layout.getPrimaryHorizontal(chip.end)
      } else {
        layout.getLineRight(line)
      }
    val right = end - if (chip.textAfter) textGap else 0f

    val metrics = view.paint.fontMetrics
    val center = layout.getLineBaseline(line) + (metrics.ascent + metrics.descent) / 2
    out.set(left, center - chipHeight / 2, right, center + chipHeight / 2)
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
  }

  private fun isSpace(c: Char): Boolean = c != '\n' && Character.isWhitespace(c)

  companion object {
    // `UNICODE_CHARACTER_CLASS` so `\s` covers what JS and ICU count as whitespace
    // (no-break and ideographic spaces), not just ASCII.
    private val TOKEN = Pattern.compile("(^|\\s)(#\\S+)", Pattern.MULTILINE or Pattern.UNICODE_CHARACTER_CLASS)
    private const val MAX_TAG_LENGTH = 100

    // Web's editor chip (openstory-web rich-text-view + hashtagChipEditing), in dp.
    private const val CHIP_HEIGHT = 24f
    private const val PADDING_LEFT = 8f
    private const val PADDING_RIGHT = 5f
    private const val DELETE_GAP = 8f
    private const val DELETE_SIZE = 16f
    private const val DELETE_GLYPH_SPAN = 6f
    private const val DELETE_GLYPH_STROKE = 1.5f
    private const val TEXT_GAP = 4f

    private val CHIP_COLOR = Color.parseColor("#E3E6F0")
    private val TEXT_COLOR = Color.parseColor("#4B5061")
    private val DELETE_COLOR = Color.parseColor("#CCD1E1")
  }
}
