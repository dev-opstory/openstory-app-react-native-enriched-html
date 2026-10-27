package com.swmansion.enriched.textinput.watchers

import android.text.Editable
import android.text.Spannable
import android.text.TextWatcher
import com.facebook.react.bridge.ReactContext
import com.facebook.react.uimanager.UIManagerHelper
import com.swmansion.enriched.common.CustomStyle
import com.swmansion.enriched.common.EnrichedConstants
import com.swmansion.enriched.textinput.EnrichedTextInputView
import com.swmansion.enriched.textinput.events.OnChangeTextEvent
import com.swmansion.enriched.textinput.spans.EnrichedInputAlignmentSpan
import com.swmansion.enriched.textinput.spans.EnrichedInputCustomStyleSpan
import com.swmansion.enriched.textinput.spans.EnrichedSpans
import com.swmansion.enriched.textinput.styles.IndentStyles

class EnrichedTextWatcher(
  private val view: EnrichedTextInputView,
) : TextWatcher {
  private var endCursorPosition: Int = 0
  private var startCursorPosition: Int = 0
  private var previousTextLength: Int = 0

  private var deletedText: String = ""
  private var anchorAlignmentToRestore: String? = null
  private var deletedIndentAnchor: IndentStyles.ParagraphIndent? = null

  // Inline and custom spans over a range the IME is about to replace. Samsung Keyboard and
  // Gboard re-send the whole composing word on every keystroke ("Dramat" -> "Dramati"),
  // which the framework reports as one big replacement. Without this the inline styles
  // logic treats the whole word as newly typed text and strips every style that is not
  // armed at the caret.
  private class StyleSnapshot(
    val inline: List<Triple<String, Int, Int>>,
    val custom: List<Triple<CustomStyle, Int, Int>>,
  )

  private var styleSnapshot: StyleSnapshot? = null

  private fun snapshotStyles(
    s: Spannable,
    start: Int,
    end: Int,
  ): StyleSnapshot {
    val inline = mutableListOf<Triple<String, Int, Int>>()
    for ((name, config) in EnrichedSpans.inlineSpans) {
      for (span in s.getSpans(start, end, config.clazz)) {
        inline += Triple(name, s.getSpanStart(span), s.getSpanEnd(span))
      }
    }
    val custom = mutableListOf<Triple<CustomStyle, Int, Int>>()
    for (span in s.getSpans(start, end, EnrichedInputCustomStyleSpan::class.java)) {
      custom += Triple(span.toCustomStyle(), s.getSpanStart(span), s.getSpanEnd(span))
    }
    return StyleSnapshot(inline, custom)
  }

  /**
   * Re-apply the snapshot to the characters the replacement left untouched and return the
   * range that is genuinely new, which is all the caret-state style logic should see.
   */
  private fun restoreUnchangedStyles(
    snapshot: StyleSnapshot,
    inserted: String,
  ): Pair<Int, Int> {
    val prefix = deletedText.commonPrefixWith(inserted).length
    val suffix = deletedText.substring(prefix).commonSuffixWith(inserted.substring(prefix)).length
    if (prefix == 0 && suffix == 0) return startCursorPosition to endCursorPosition

    val oldStart = startCursorPosition
    val oldEnd = oldStart + deletedText.length
    val shift = endCursorPosition - oldEnd

    fun restoreRange(
      from: Int,
      to: Int,
      apply: (Int, Int) -> Unit,
    ) {
      if (prefix > 0) {
        val a = maxOf(from, oldStart)
        val b = minOf(to, oldStart + prefix)
        if (a < b) apply(a, b)
      }
      if (suffix > 0) {
        val a = maxOf(from, oldEnd - suffix)
        val b = minOf(to, oldEnd)
        if (a < b) apply(a + shift, b + shift)
      }
    }

    for ((name, from, to) in snapshot.inline) {
      restoreRange(from, to) { a, b -> view.inlineStyles?.restoreStyleOnRange(name, a, b) }
    }
    for ((style, from, to) in snapshot.custom) {
      restoreRange(from, to) { a, b -> view.customStyles?.restoreStyleOnRange(a, b, style) }
    }

    return (startCursorPosition + prefix) to (endCursorPosition - suffix)
  }

  override fun beforeTextChanged(
    s: CharSequence?,
    start: Int,
    count: Int,
    after: Int,
  ) {
    previousTextLength = s?.length ?: 0
    deletedText = if (count > 0 && s != null) s.substring(start, start + count) else ""
    styleSnapshot =
      if (count > 0 && after > 0 && s is Spannable && !view.isDuringTransaction) {
        snapshotStyles(s, start, start + count)
      } else {
        null
      }

    anchorAlignmentToRestore = null
    deletedIndentAnchor =
      if (deletedText == EnrichedConstants.ZWS_STRING && s is Spannable) {
        view.indentStyles?.indentAnchoredAt(s, start)
      } else {
        null
      }

    // When a ZWS is being deleted, check whether it was anchoring a list or paragraph
    // style. If so, capture the co-located alignment value so AlignmentStyles can
    // re-anchor it after the deletion completes.
    if (deletedText == EnrichedConstants.ZWS_STRING && s is Spannable) {
      val isBlockAnchor =
        EnrichedSpans.listSpans.values
          .any { config -> s.getSpans(start, start + 1, config.clazz).isNotEmpty() } ||
          EnrichedSpans.paragraphSpans.values
            .any { config -> s.getSpans(start, start + 1, config.clazz).isNotEmpty() }

      if (isBlockAnchor) {
        anchorAlignmentToRestore =
          s
            .getSpans(start, start + 1, EnrichedInputAlignmentSpan::class.java)
            .firstOrNull()
            ?.cssValue
      }
    }
  }

  override fun onTextChanged(
    s: CharSequence?,
    start: Int,
    before: Int,
    count: Int,
  ) {
    startCursorPosition = start
    endCursorPosition = start + count
    view.layoutManager.invalidateLayout()
    view.isRemovingMany = !view.isDuringTransaction && before > count + 1
  }

  override fun afterTextChanged(s: Editable?) {
    if (s == null) return
    emitEvents(s)

    if (view.isDuringTransaction) return
    val inserted = s.substring(startCursorPosition.coerceAtMost(s.length), endCursorPosition.coerceAtMost(s.length))
    applyStyles(s, inserted)
    view.layoutManager.invalidateLayout()
  }

  private fun applyStyles(
    s: Editable,
    inserted: String,
  ) {
    val snapshot = styleSnapshot
    styleSnapshot = null
    val (newStart, newEnd) =
      if (snapshot != null) {
        restoreUnchangedStyles(snapshot, inserted)
      } else {
        startCursorPosition to endCursorPosition
      }
    view.inlineStyles?.afterTextChanged(s, newStart, newEnd)
    view.customStyles?.afterTextChanged(s, newStart, newEnd)
    view.paragraphStyles?.afterTextChanged(s, endCursorPosition, previousTextLength)
    view.listStyles?.afterTextChanged(s, endCursorPosition, previousTextLength)
    // A deleted indent anchor is the indent's to handle: alignment's own ZWS backspace would
    // join the line to a centred one above.
    if (deletedIndentAnchor == null) {
      view.alignmentStyles?.afterTextChanged(s, endCursorPosition, deletedText, anchorAlignmentToRestore)
    }
    view.indentStyles?.afterTextChanged(s, startCursorPosition, endCursorPosition, deletedText, deletedIndentAnchor)
    view.shortcutsHandler?.afterTextChanged(s, endCursorPosition, previousTextLength)
    view.parametrizedStyles?.afterTextChanged(s, startCursorPosition, endCursorPosition)
  }

  private fun emitChangeText(editable: Editable) {
    if (!view.shouldEmitOnChangeText) {
      return
    }
    val context = view.context as ReactContext
    val surfaceId = UIManagerHelper.getSurfaceId(context)
    val dispatcher = UIManagerHelper.getEventDispatcherForReactTag(context, view.id)
    dispatcher?.dispatchEvent(
      OnChangeTextEvent(
        surfaceId,
        view.id,
        editable,
        view.experimentalSynchronousEvents,
      ),
    )
  }

  private fun emitEvents(s: Editable) {
    emitChangeText(s)
    view.spanWatcher?.emitEvent(s, null)
  }
}
