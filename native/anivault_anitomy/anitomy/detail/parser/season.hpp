#pragma once

#include <ranges>
#include <regex>
#include <span>
#include <tuple>
#include <vector>

#include <anitomy/detail/token.hpp>
#include <anitomy/detail/util.hpp>
#include <anitomy/element.hpp>

namespace anitomy::detail {

inline std::vector<Element> parse_season(std::span<Token> tokens) noexcept {
  using window_t = std::tuple<Token&, Token&, Token&>;

  std::vector<Element> elements;

  {
    static constexpr auto is_season_keyword = [](const Token& token) {
      return token.keyword && token.keyword->kind == KeywordKind::Season;
    };

    static constexpr auto starts_with_season_keyword = [](window_t tokens) {
      return is_season_keyword(std::get<0>(tokens)) &&   //
             is_delimiter_token(std::get<1>(tokens)) &&  //
             is_free_token(std::get<2>(tokens));
    };

    static constexpr auto ends_with_season_keyword = [](window_t tokens) {
      return is_season_keyword(std::get<2>(tokens)) &&   //
             is_delimiter_token(std::get<1>(tokens)) &&  //
             is_free_token(std::get<0>(tokens));
    };

    for (size_t i = 0; i + 2 < tokens.size(); ++i) {
      auto& t0 = tokens[i];
      auto& t1 = tokens[i+1];
      auto& t2 = tokens[i+2];
      window_t view = std::tie(t0, t1, t2);

      // Check previous token for a number (e.g. `2nd Season`)
      if (ends_with_season_keyword(view)) {
        if (auto number = from_ordinal_number(t0.value); !number.empty()) {
          t0.element_kind = ElementKind::Season;
          t2.element_kind = ElementKind::Season;
          elements.emplace_back(ElementKind::Season, std::string{number}, t0.position);
          break;
        }
      }
      // Check next token for a number (e.g. `Season 2`, `Season II`)
      if (starts_with_season_keyword(view)) {
        std::string value;
        if (is_numeric_token(t2)) {
          value = t2.value;
        } else if (auto number = from_roman_number(t2.value); !number.empty()) {
          value = number;
        }
        if (!value.empty()) {
          t0.element_kind = ElementKind::Season;
          t2.element_kind = ElementKind::Season;
          elements.emplace_back(ElementKind::Season, value, t2.position);
          break;
        }
      }
    }
  }

  // Season pattern (e.g. `S2`, `S01-02`)
  {
    static constexpr auto match_season = [](const Token& token, std::smatch& matches) {
      static const std::regex pattern{"S(\\d{1,2})"};
      return std::regex_match(token.value, matches, pattern);
    };

    std::smatch matches;

    for (size_t i = 0; i < tokens.size(); ++i) {
      auto& token = tokens[i];
      if (!is_free_token(token)) continue;
      if (!match_season(token, matches)) continue;

      token.element_kind = ElementKind::Season;
      elements.emplace_back(ElementKind::Season, matches.str(1),
                            token.position + matches.position(1));

      if (i + 1 >= tokens.size()) continue;
      auto& next = tokens[i+1];
      if (!is_dash_token(next)) continue;
      if (i + 2 >= tokens.size()) continue;
      auto& next_next = tokens[i+2];

      if (is_free_token(next_next) && is_numeric_token(next_next)) {
        next_next.element_kind = ElementKind::Season;
        elements.emplace_back(ElementKind::Season, next_next.value, next_next.position);
        break;
      }
    }
  }

  // Japanese counter pattern (e.g. `第2期`)
  if (elements.empty()) {
    static constexpr auto match_japanese_counter = [](const Token& token, std::smatch& matches) {
      static const std::regex pattern{"(?:第)?(\\d{1,2})期"};
      return std::regex_match(token.value, matches, pattern);
    };

    std::smatch matches;

    for (auto& token : tokens) {
      if (is_free_token(token) && match_japanese_counter(token, matches)) {
        token.element_kind = ElementKind::Season;
        elements.emplace_back(ElementKind::Season, matches.str(1),
                              token.position + matches.position(1));
        break;
      }
    }
  }

  return elements;
}

}  // namespace anitomy::detail
