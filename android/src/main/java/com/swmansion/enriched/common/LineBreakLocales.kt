package com.swmansion.enriched.common

import android.os.LocaleList
import java.util.Locale

// Samsung (seen on One UI 5.1 / Android 13) wraps text tagged as Korean by whole word, and
// Android 13 cannot opt out: LINE_BREAK_WORD_STYLE_NONE is also its default. Retagging Korean as
// "und-Kore" drops the language the device keys on but keeps the script, so font fallback still
// picks the Korean font, and text breaks between syllables like iOS. No region: minikin runs
// addLikelySubtags, which turns "und-Kore-KR" back into "ko-Kore-KR" and leaves only a bare
// script alone.
private val KOREAN_SCRIPT_ONLY: Locale = Locale.Builder().setScript("Kore").build()

internal fun lineBreakSafeLocales(locales: LocaleList = LocaleList.getDefault()): LocaleList {
  // LocaleList rejects duplicates, and two Korean entries map to the same locale.
  val mapped =
    (0 until locales.size())
      .map { i -> locales[i].let { if (it.language == "ko") KOREAN_SCRIPT_ONLY else it } }
      .distinct()
  return LocaleList(*mapped.toTypedArray())
}
