package com.swmansion.enriched.textinput

import com.facebook.react.bridge.Arguments

class EnrichedTextInputViewLayoutManager(
  private val view: EnrichedTextInputView,
) {
  private var forceHeightRecalculationCounter: Int = 0

  fun invalidateLayout() {
    val text = view.text
    val paint = view.paint
    // `TextView` draws the hint only while the text is empty; measure it on the same terms.
    val hint = if (text.isNullOrEmpty()) view.hint else null

    val needUpdate = MeasurementStore.store(view.id, text, paint, hint)
    if (!needUpdate) return

    val counter = forceHeightRecalculationCounter
    forceHeightRecalculationCounter++
    val state = Arguments.createMap()
    state.putInt("forceHeightRecalculationCounter", counter)
    view.stateWrapper?.updateState(state)
  }

  fun releaseMeasurementStore() {
    MeasurementStore.release(view.id)
  }
}
