#pragma once

#include <string>
#include <utility>

namespace anitomy {

enum class ElementKind {
  AudioTerm,
  Device,
  Episode,
  EpisodeTitle,
  FileChecksum,
  FileExtension,
  Language,
  Other,
  Part,
  ReleaseGroup,
  ReleaseInformation,
  ReleaseVersion,
  Season,
  Source,
  Subtitles,
  Title,
  Type,
  VideoResolution,
  VideoTerm,
  Volume,
  Year,
};

struct Element {
  Element(ElementKind kind, std::string value, size_t position)
      : kind(kind), value(std::move(value)), position(position) {}

  ElementKind kind;
  std::string value;
  size_t position;
};

}  // namespace anitomy
