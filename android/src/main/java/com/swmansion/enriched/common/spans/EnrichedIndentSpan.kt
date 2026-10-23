package com.swmansion.enriched.common.spans

import android.graphics.Canvas
import android.graphics.Paint
import android.text.Layout
import android.text.Spanned
import android.text.TextPaint
import android.text.style.LeadingMarginSpan
import android.text.style.MetricAffectingSpan
import com.facebook.react.uimanager.PixelUtil
import com.swmansion.enriched.common.EnrichedStyle
import com.swmansion.enriched.common.spans.interfaces.EnrichedZeroWidthSpaceSpan
import kotlin.math.max
import kotlin.math.roundToInt

/**
 * Paragraph indent (levels 1-3) with an optional bullet, serialized as `data-indent` and
 * `data-bullet` on `<p>`. A plain paragraph indents its first line only; a bulleted one
 * indents every line and draws its marker in the last indent slot of the first line.
 */
open class EnrichedIndentSpan(
  val level: Int,
  val isBullet: Boolean,
  private val enrichedStyle: EnrichedStyle,
) : MetricAffectingSpan(),
  LeadingMarginSpan,
  EnrichedZeroWidthSpaceSpan {
  private val unitPx = PixelUtil.toPixelFromDIP(INDENT_UNIT_DP)

  // No metrics change, but only a metric-affecting span makes the layout re-wrap the
  // paragraph when it is added or removed. A bare LeadingMarginSpan left the old line
  // breaks in place, so indented text ran past the right edge.
  override fun updateMeasureState(textPaint: TextPaint) {}

  override fun updateDrawState(textPaint: TextPaint?) {}

  override fun getLeadingMargin(first: Boolean): Int = if (first || isBullet) (level * unitPx).roundToInt() else 0

  override fun drawLeadingMargin(
    canvas: Canvas,
    paint: Paint,
    x: Int,
    dir: Int,
    top: Int,
    baseline: Int,
    bottom: Int,
    text: CharSequence,
    start: Int,
    end: Int,
    first: Boolean,
    layout: Layout?,
  ) {
    if (!isBullet || (text as Spanned).getSpanStart(this) != start) return

    val size = enrichedStyle.ulBulletSize.toFloat()
    val fm = paint.fontMetricsInt
    val centerX = x + dir * (level - 0.5f) * unitPx
    val centerY = baseline + (fm.ascent + fm.descent) / 2f

    val oldStyle = paint.style
    val oldColor = paint.color
    val oldStrokeWidth = paint.strokeWidth
    paint.color = enrichedStyle.ulBulletColor

    when (level) {
      2 -> {
        val strokeWidth = max(PixelUtil.toPixelFromDIP(1f), size / 6)
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = strokeWidth
        canvas.drawCircle(centerX, centerY, (size - strokeWidth) / 2, paint)
      }
      3 -> {
        // a touch smaller than the disc so both read as the same weight
        val half = size * 0.4f
        paint.style = Paint.Style.FILL
        canvas.drawRect(centerX - half, centerY - half, centerX + half, centerY + half, paint)
      }
      else -> {
        paint.style = Paint.Style.FILL
        canvas.drawCircle(centerX, centerY, size / 2, paint)
      }
    }

    paint.style = oldStyle
    paint.color = oldColor
    paint.strokeWidth = oldStrokeWidth
  }

  companion object {
    // Matches web's RICH_TEXT_INDENT_UNIT_PX and the iOS editor.
    const val INDENT_UNIT_DP = 18f
    const val MAX_LEVEL = 3
  }
}
