package com.swmansion.enriched.textinput.spans

import com.swmansion.enriched.common.spans.EnrichedIndentSpan
import com.swmansion.enriched.textinput.spans.interfaces.EnrichedInputSpan
import com.swmansion.enriched.textinput.styles.HtmlStyle

class EnrichedInputIndentSpan(
  level: Int,
  isBullet: Boolean,
  htmlStyle: HtmlStyle,
) : EnrichedIndentSpan(level, isBullet, htmlStyle),
  EnrichedInputSpan {
  override val dependsOnHtmlStyle: Boolean = true

  override fun rebuildWithStyle(htmlStyle: HtmlStyle): EnrichedInputIndentSpan = EnrichedInputIndentSpan(level, isBullet, htmlStyle)
}
