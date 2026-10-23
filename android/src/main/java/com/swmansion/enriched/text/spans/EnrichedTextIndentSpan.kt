package com.swmansion.enriched.text.spans

import com.swmansion.enriched.common.spans.EnrichedIndentSpan
import com.swmansion.enriched.text.EnrichedTextStyle
import com.swmansion.enriched.text.spans.interfaces.EnrichedTextSpan

class EnrichedTextIndentSpan(
  level: Int,
  isBullet: Boolean,
  style: EnrichedTextStyle,
) : EnrichedIndentSpan(level, isBullet, style),
  EnrichedTextSpan {
  override val dependsOnHtmlStyle = true

  override fun rebuildWithStyle(style: EnrichedTextStyle) = EnrichedTextIndentSpan(level, isBullet, style)
}
