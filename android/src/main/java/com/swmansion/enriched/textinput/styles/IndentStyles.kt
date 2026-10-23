package com.swmansion.enriched.textinput.styles

import android.text.Editable
import android.text.Spannable
import android.text.SpannableStringBuilder
import com.swmansion.enriched.common.EnrichedConstants
import com.swmansion.enriched.common.EnrichedSpanFlags
import com.swmansion.enriched.common.spans.EnrichedIndentSpan
import com.swmansion.enriched.textinput.EnrichedTextInputView
import com.swmansion.enriched.textinput.spans.EnrichedInputAlignmentSpan
import com.swmansion.enriched.textinput.spans.EnrichedInputIndentSpan
import com.swmansion.enriched.textinput.utils.getParagraphBounds
import com.swmansion.enriched.textinput.utils.getSafeSpanBoundaries
import com.swmansion.enriched.textinput.utils.safelyInsertZWS

/**
 * Paragraph indent levels 1-3 and bullets, the Android half of the iOS IndentStyle.
 *
 * Each formatted paragraph is anchored by a ZWS at its start, like alignment, so an empty
 * bullet has a character to hold its span and Backspace at the visual start of a line
 * deletes that ZWS instead of joining the line to the one above.
 */
class IndentStyles(
  private val view: EnrichedTextInputView,
) {
  data class ParagraphIndent(
    val level: Int,
    val isBullet: Boolean,
  )

  /** Raise or lower every touched paragraph by one level. Centred paragraphs take no indent. */
  fun changeIndent(delta: Int) {
    val spannable = view.text as? SpannableStringBuilder ?: return
    // Back to front, so the ZWS a paragraph gains or loses never shifts one still to visit.
    for ((paraStart, paraEnd) in touchedParagraphs(spannable).asReversed()) {
      if (isCentered(spannable, paraStart, paraEnd)) continue
      val current = indentOf(spannable, paraStart, paraEnd)
      // a bullet only moves between levels 1-3; outdenting level 1 keeps it
      setIndent(spannable, paraStart, paraEnd, current.level + delta, current.isBullet)
    }
  }

  /** Bullet every touched paragraph, or remove the bullets when all have one. */
  fun toggleBullet() {
    val spannable = view.text as? SpannableStringBuilder ?: return
    val paragraphs =
      touchedParagraphs(spannable).filter { (paraStart, paraEnd) ->
        !isCentered(spannable, paraStart, paraEnd)
      }
    if (paragraphs.isEmpty()) return

    val allBulleted = paragraphs.all { (paraStart, paraEnd) -> indentOf(spannable, paraStart, paraEnd).isBullet }
    // Removing a bullet keeps the line's level; adding one to an unindented line starts it
    // at level 1.
    for ((paraStart, paraEnd) in paragraphs.asReversed()) {
      val current = indentOf(spannable, paraStart, paraEnd)
      setIndent(spannable, paraStart, paraEnd, current.level, !allBulleted)
    }
  }

  /** Centring drops indent and bullets; the alignment keeps the paragraph's ZWS. */
  fun removeIndentSpans(
    spannable: Spannable,
    paraStart: Int,
    paraEnd: Int,
  ) {
    for (span in spannable.getSpans(paraStart, paraEnd, EnrichedInputIndentSpan::class.java)) {
      val sStart = spannable.getSpanStart(span)
      val sEnd = spannable.getSpanEnd(span)
      spannable.removeSpan(span)
      // Keep the parts of a span that spill into neighbouring paragraphs.
      if (sStart < paraStart) {
        val topEnd = if (paraStart > 0 && spannable[paraStart - 1] == '\n') paraStart - 1 else paraStart
        if (sStart < topEnd) setIndentSpan(spannable, span.level, span.isBullet, sStart, topEnd)
      }
      if (sEnd > paraEnd) {
        val bottomStart = if (paraEnd < spannable.length && spannable[paraEnd] == '\n') paraEnd + 1 else paraEnd
        if (bottomStart < sEnd) setIndentSpan(spannable, span.level, span.isBullet, bottomStart, sEnd)
      }
    }
  }

  /** The indent of the ZWS at [index], read before a deletion removes it. */
  fun indentAnchoredAt(
    spannable: Spannable,
    index: Int,
  ): ParagraphIndent? {
    if (index !in 0 until spannable.length || spannable[index] != EnrichedConstants.ZWS) return null
    val isParagraphStart = index == 0 || spannable[index - 1] == '\n'
    if (!isParagraphStart) return null
    val span = spannable.getSpans(index, index + 1, EnrichedInputIndentSpan::class.java).firstOrNull() ?: return null
    return ParagraphIndent(span.level, span.isBullet)
  }

  fun afterTextChanged(
    s: Editable,
    start: Int,
    cursorPosition: Int,
    deletedText: String,
    deletedAnchor: ParagraphIndent?,
  ) {
    val ssb = s as? SpannableStringBuilder ?: return
    val inserted = if (cursorPosition > start) ssb.substring(start, cursorPosition) else ""

    when {
      deletedAnchor != null && deletedText == EnrichedConstants.ZWS_STRING -> {
        view.runAsATransaction { handleAnchorBackspace(ssb, cursorPosition, deletedAnchor) }
      }

      inserted == "\t" -> {
        view.runAsATransaction {
          ssb.delete(start, cursorPosition)
          val (paraStart, paraEnd) = ssb.getParagraphBounds(start)
          if (!isCentered(ssb, paraStart, paraEnd)) {
            val current = indentOf(ssb, paraStart, paraEnd)
            setIndent(ssb, paraStart, paraEnd, current.level + 1, current.isBullet)
          }
        }
      }

      deletedText.isEmpty() && inserted.endsWith("\n") -> {
        view.runAsATransaction { handleNewline(ssb, cursorPosition) }
      }

      else -> {
        view.runAsATransaction { stretchToParagraph(ssb, cursorPosition, deletedText.contains('\n')) }
      }
    }
  }

  // Backspace removed the ZWS at the start of an indented line: a bullet drops its marker
  // and keeps its level, a plain line steps out one level.
  private fun handleAnchorBackspace(
    ssb: SpannableStringBuilder,
    cursorPosition: Int,
    anchor: ParagraphIndent,
  ) {
    val (paraStart, paraEnd) = ssb.getParagraphBounds(cursorPosition)
    removeIndentSpans(ssb, paraStart, paraEnd)
    if (anchor.isBullet) {
      setIndent(ssb, paraStart, paraEnd, anchor.level, false)
    } else if (anchor.level > 1) {
      setIndent(ssb, paraStart, paraEnd, anchor.level - 1, false)
    }
  }

  private fun handleNewline(
    ssb: SpannableStringBuilder,
    cursorPosition: Int,
  ) {
    val newlineIndex = cursorPosition - 1
    val (prevStart, prevEnd) = ssb.getParagraphBounds(newlineIndex)
    val previous = indentOf(ssb, prevStart, prevEnd)
    if (previous.level == 0 && !previous.isBullet) return

    // Enter on an empty bullet steps it out one level, and off at level 1, instead of
    // making a new line.
    if (previous.isBullet && isParagraphEmpty(ssb, prevStart, prevEnd)) {
      ssb.delete(newlineIndex, cursorPosition)
      val (paraStart, paraEnd) = ssb.getParagraphBounds(newlineIndex)
      if (previous.level > 1) {
        setIndent(ssb, paraStart, paraEnd, previous.level - 1, true)
      } else {
        setIndent(ssb, paraStart, paraEnd, 0, false)
      }
      return
    }

    // The new paragraph carries on the previous one's level and bullet.
    val (nextStart, nextEnd) = ssb.getParagraphBounds(cursorPosition)
    removeIndentSpans(ssb, nextStart, nextEnd)
    setIndent(ssb, prevStart, prevEnd, previous.level, previous.isBullet)
    setIndent(ssb, nextStart, nextEnd, previous.level, previous.isBullet)
  }

  // Keep exactly one span over the caret's paragraph, stretched to its bounds as it is typed
  // into. After a merge the upper paragraph's format wins.
  private fun stretchToParagraph(
    ssb: SpannableStringBuilder,
    cursorPosition: Int,
    isMerge: Boolean,
  ) {
    val (paraStart, paraEnd) = ssb.getParagraphBounds(cursorPosition.coerceIn(0, ssb.length))
    val spans =
      ssb
        .getSpans(paraStart, paraEnd, EnrichedInputIndentSpan::class.java)
        .sortedBy { ssb.getSpanStart(it) }
    if (spans.isEmpty()) return

    val dominant =
      if (isMerge) spans.firstOrNull { ssb.getSpanStart(it) < cursorPosition } else spans.first()
    removeIndentSpans(ssb, paraStart, paraEnd)
    if (dominant != null) {
      setIndentSpan(ssb, dominant.level, dominant.isBullet, paraStart, paraEnd)
    }
  }

  /** Put one paragraph at [level] with or without a bullet, adding or dropping its ZWS. */
  private fun setIndent(
    ssb: SpannableStringBuilder,
    paraStart: Int,
    paraEnd: Int,
    level: Int,
    isBullet: Boolean,
  ) {
    val clamped = level.coerceIn(if (isBullet) 1 else 0, EnrichedIndentSpan.MAX_LEVEL)
    removeIndentSpans(ssb, paraStart, paraEnd)

    if (clamped == 0) {
      // The ZWS stays when an alignment still anchors on it.
      val anchorsAlignment = ssb.getSpans(paraStart, paraEnd, EnrichedInputAlignmentSpan::class.java).isNotEmpty()
      if (!anchorsAlignment && paraStart < ssb.length && ssb[paraStart] == EnrichedConstants.ZWS) {
        ssb.delete(paraStart, paraStart + 1)
      }
      return
    }

    val shift = if (ssb.safelyInsertZWS(paraStart)) 1 else 0
    setIndentSpan(ssb, clamped, isBullet, paraStart, paraEnd + shift)
  }

  private fun setIndentSpan(
    spannable: Spannable,
    level: Int,
    isBullet: Boolean,
    start: Int,
    end: Int,
  ) {
    val (safeStart, safeEnd) = spannable.getSafeSpanBoundaries(start, end)
    if (safeStart == safeEnd) return
    val span = EnrichedInputIndentSpan(level, isBullet, view.htmlStyle)
    spannable.setSpan(span, safeStart, safeEnd, EnrichedSpanFlags.forSpan(span, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE))
  }

  private fun indentOf(
    spannable: Spannable,
    paraStart: Int,
    paraEnd: Int,
  ): ParagraphIndent {
    val span =
      spannable
        .getSpans(paraStart, paraEnd, EnrichedInputIndentSpan::class.java)
        .firstOrNull { spannable.getSpanStart(it) <= paraStart || paraStart == paraEnd }
        ?: spannable.getSpans(paraStart, paraEnd, EnrichedInputIndentSpan::class.java).firstOrNull()
        ?: return ParagraphIndent(0, false)
    return ParagraphIndent(span.level, span.isBullet)
  }

  private fun isCentered(
    spannable: Spannable,
    paraStart: Int,
    paraEnd: Int,
  ): Boolean =
    spannable
      .getSpans(paraStart, paraEnd, EnrichedInputAlignmentSpan::class.java)
      .any { it.cssValue == "center" }

  private fun isParagraphEmpty(
    spannable: Spannable,
    paraStart: Int,
    paraEnd: Int,
  ): Boolean = (paraStart until paraEnd).all { spannable[it] == EnrichedConstants.ZWS }

  // Paragraphs a selection acts on, the same rule as iOS: a range touches a line it covers
  // at least one character of; an empty line counts when the range starts at or before it
  // and runs past its start. A collapsed caret acts on its own line.
  private fun touchedParagraphs(spannable: Spannable): List<Pair<Int, Int>> {
    val selStart = view.selectionStart.coerceIn(0, spannable.length)
    val selEnd = view.selectionEnd.coerceIn(selStart, spannable.length)
    val first = spannable.getParagraphBounds(selStart)
    if (selStart == selEnd) return listOf(first)

    val result = mutableListOf<Pair<Int, Int>>()
    var (paraStart, paraEnd) = first
    while (true) {
      val isEmpty = paraStart == paraEnd
      val touched =
        if (isEmpty) {
          selStart <= paraStart && selEnd > paraStart
        } else {
          selStart < paraEnd && selEnd > paraStart
        }
      if (touched) result.add(Pair(paraStart, paraEnd))
      if (paraEnd >= selEnd || paraEnd >= spannable.length) break
      val next = spannable.getParagraphBounds(paraEnd + 1)
      paraStart = next.first
      paraEnd = next.second
    }
    return result
  }
}
