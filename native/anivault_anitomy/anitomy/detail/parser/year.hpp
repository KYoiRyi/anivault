#pragma once

#include <optional>
#include <ranges>
#include <span>
#include <tuple>

#include <anitomy/detail/token.hpp>
#include <anitomy/element.hpp>

namespace anitomy::detail {

inline std::optional<Element> parse_year(std::span<Token> tokens) noexcept {
  using namespace std::views;
  using window_t = std::tuple<Token&, Token&, Token&>;

  static constexpr auto is_isolated = [](window_t tokens) {
    return std::get<0>(tokens).kind == TokenKind::OpenBracket &&
           std::get<2>(tokens).kind == TokenKind::CloseBracket;
  };

  static constexpr auto is_free_number = [](window_t tokens) {
    auto& token = std::get<1>(tokens);
    return is_free_token(token) && is_numeric_token(token);
  };

  static constexpr auto is_year = [](window_t tokens) {
    const int number = to_int(std::get<1>(tokens).value);
    return 1950 < number && number < 2050;
  };

  for (size_t i = 0; i + 2 < tokens.size(); ++i) {
    auto& t0 = tokens[i];
    auto& t1 = tokens[i+1];
    auto& t2 = tokens[i+2];
    if (t0.kind == TokenKind::OpenBracket && t2.kind == TokenKind::CloseBracket) {
      if (is_free_token(t1) && is_numeric_token(t1)) {
        const int number = to_int(t1.value);
        if (1950 < number && number < 2050) {
          t1.element_kind = ElementKind::Year;
          return element_from_token(ElementKind::Year, t1);
        }
      }
    }
  }
  return {};
}

}  // namespace anitomy::detail
