#pragma once

#include <algorithm>
#include <array>
#include <optional>
#include <span>

#include <anitomy/detail/token.hpp>
#include <anitomy/element.hpp>

namespace anitomy::detail {

inline std::optional<Element> parse_file_extension(std::span<Token> tokens) noexcept {
  using namespace std::views;

  static constexpr auto is_file_extension = [](const Token& token) {
    // clang-format off
    static const std::array extensions{
        "3gp",
        "avi",
        "divx",
        "flv",
        "m2ts",
        "m4v",
        "mkv",
        "mov",
        "mp4",
        "mpg",
        "ogm",
        "rm",
        "rmvb",
        "ts",
        "webm",
        "wmv",
    };
    // clang-format on

    return (is_keyword_token(token) || is_text_token(token)) &&
           (std::find(extensions.begin(), extensions.end(), token.value) != extensions.end());
  };

  static constexpr auto is_dot = [](const Token& token) {
    return is_delimiter_token(token) && token.value == ".";
  };

  if (tokens.size() < 2) return {};

  auto& last_token = tokens[tokens.size() - 1];
  auto& prev_token = tokens[tokens.size() - 2];

  if (!is_file_extension(last_token) || !is_dot(prev_token)) return {};

  last_token.kind = TokenKind::Text;  // in case it was previously marked as keyword
  last_token.keyword.reset();
  last_token.element_kind = ElementKind::FileExtension;

  return element_from_token(ElementKind::FileExtension, last_token);
}

}  // namespace anitomy::detail
