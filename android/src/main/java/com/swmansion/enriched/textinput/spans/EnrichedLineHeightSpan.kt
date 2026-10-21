package com.swmansion.enriched.textinput.spans

import android.graphics.Paint
import android.text.Spanned
import android.text.TextPaint
import android.text.style.LineHeightSpan
import android.text.style.MetricAffectingSpan
import com.swmansion.enriched.common.pixelFromSpOrDp
import com.swmansion.enriched.common.spans.interfaces.EnrichedHeadingSpan

class EnrichedLineHeightSpan(
  val lineHeight: Float,
  val allowFontScaling: Boolean,
) : MetricAffectingSpan(),
  LineHeightSpan {
  override fun updateDrawState(p0: TextPaint?) {
    // Do nothing but inform TextView that line height should be recalculated
  }

  override fun updateMeasureState(p0: TextPaint) {
    // Do nothing but inform TextView that line height should be recalculated
  }

  override fun chooseHeight(
    text: CharSequence,
    start: Int,
    end: Int,
    spanstartv: Int,
    v: Int,
    fm: Paint.FontMetricsInt,
  ) {
    // `Spanned`, not `Spannable`: a read-only `EnrichedTextView` hands its text to
    // `setText`, which stores it as an immutable `SpannedString`. That failed the
    // `Spannable` cast, so the line height was applied while measuring (a plain
    // `SpannableString` there) but skipped while drawing — the box grew and the lines
    // kept the font's own leading. Only `getSpans` is used here, and it is declared
    // on `Spanned`; the editor's `Editable` still satisfies it.
    val spanned = text as? Spanned ?: return
    // Do not modify line height for headings
    // In the future we may consider adding custom lineHeight support for each paragraph style
    if (spanned.getSpans(start, end, EnrichedHeadingSpan::class.java).isNotEmpty()) return

    val lineHeightPx = pixelFromSpOrDp(lineHeight, allowFontScaling)
    val currentHeight = (fm.descent - fm.ascent).toFloat()
    if (lineHeightPx <= currentHeight) return

    val extra = (lineHeightPx - currentHeight).toInt()
    fm.ascent -= extra
    fm.top = minOf(fm.top, fm.ascent)
  }
}
