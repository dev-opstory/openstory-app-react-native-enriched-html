#include "GumboParser.hpp"

// C functions defined in GumboNormalizer.c (compiled as C)
extern "C" {
char *normalize_html(const char *html, size_t len);
char *normalize_html_openstory(const char *html, size_t len);
void free_normalized_html(char *result);
}

static std::string takeNormalized(char *raw) {
  if (!raw)
    return {};
  std::string result(raw);
  free_normalized_html(raw);
  return result;
}

std::string GumboParser::normalizeHtml(const std::string &html) {
  return takeNormalized(normalize_html(html.c_str(), html.size()));
}

std::string GumboParser::normalizeOpenStoryHtml(const std::string &html) {
  return takeNormalized(normalize_html_openstory(html.c_str(), html.size()));
}
