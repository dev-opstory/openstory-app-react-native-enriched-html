/**
 * Cross-platform HTML normalizer powered by Gumbo.
 * Converts arbitrary external HTML (Google Docs, Word, etc.) into a canonical
 * subset that our enriched parser understands.
 */

#pragma once

#include <string>

/**
 * C++ wrapper around the Gumbo-based HTML normalizer.
 */
class GumboParser {
public:
  /**
   * Normalize an HTML string into the canonical subset.
   *
   * @param html  UTF-8 encoded HTML fragment or full document.
   * @return      Canonical HTML string, or empty string on failure.
   */
  static std::string normalizeHtml(const std::string &html);

  /**
   * Normalize pasted HTML into what the OpenStory editor can save: B/I/U/S,
   * links, one large text size, center alignment, and flat bullet/indent
   * paragraphs. See the OpenStory profile in GumboNormalizer.c.
   */
  static std::string normalizeOpenStoryHtml(const std::string &html);
};
