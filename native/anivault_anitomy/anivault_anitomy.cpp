#include <anitomy.hpp>
#include <anitomy/detail/format.hpp>

#include <cstdlib>
#include <cstring>
#include <map>
#include <string>
#include <vector>

#if defined(_WIN32)
#if defined(ANIVAULT_ANITOMY_EXPORTS)
#define ANIVAULT_ANITOMY_API __declspec(dllexport)
#else
#define ANIVAULT_ANITOMY_API __declspec(dllimport)
#endif
#else
#define ANIVAULT_ANITOMY_API __attribute__((visibility("default"))) __attribute__((used))
#endif

namespace {

std::string escape_json(const std::string& value) {
  std::string output;
  output.reserve(value.size() + 8);
  for (const unsigned char ch : value) {
    switch (ch) {
      case '"':
        output += "\\\"";
        break;
      case '\\':
        output += "\\\\";
        break;
      case '\b':
        output += "\\b";
        break;
      case '\f':
        output += "\\f";
        break;
      case '\n':
        output += "\\n";
        break;
      case '\r':
        output += "\\r";
        break;
      case '\t':
        output += "\\t";
        break;
      default:
        if (ch < 0x20) {
          constexpr char digits[] = "0123456789abcdef";
          output += "\\u00";
          output.push_back(digits[(ch >> 4) & 0x0F]);
          output.push_back(digits[ch & 0x0F]);
        } else {
          output.push_back(static_cast<char>(ch));
        }
        break;
    }
  }
  return output;
}

char* copy_to_c_string(const std::string& value) {
  auto* result = static_cast<char*>(std::malloc(value.size() + 1));
  if (result == nullptr) return nullptr;
  std::memcpy(result, value.c_str(), value.size() + 1);
  return result;
}

std::string elements_to_json(const std::vector<anitomy::Element>& elements) {
  std::map<std::string, std::vector<std::string>> grouped;
  for (const auto& element : elements) {
    grouped[std::string{anitomy::detail::to_string(element.kind)}].push_back(
        element.value);
  }

  std::string output = "{";
  bool first_key = true;
  for (const auto& [key, values] : grouped) {
    if (!first_key) output += ",";
    first_key = false;
    output += "\"" + escape_json(key) + "\":";
    if (values.size() == 1) {
      output += "\"" + escape_json(values.front()) + "\"";
    } else {
      output += "[";
      for (size_t i = 0; i < values.size(); ++i) {
        if (i != 0) output += ",";
        output += "\"" + escape_json(values[i]) + "\"";
      }
      output += "]";
    }
  }
  output += "}";
  return output;
}

}  // namespace

extern "C" {

ANIVAULT_ANITOMY_API char* anivault_anitomy_parse_json(const char* input) {
  if (input == nullptr) return copy_to_c_string("{}");
  const auto elements = anitomy::parse(input);
  return copy_to_c_string(elements_to_json(elements));
}

ANIVAULT_ANITOMY_API void anivault_anitomy_free(char* value) {
  std::free(value);
}

}  // extern "C"
