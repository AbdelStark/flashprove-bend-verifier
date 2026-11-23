#pragma once
#include <cstdint>
extern "C" {
bool bend_has_work(std::uint64_t first_word, unsigned bits);
std::uint64_t bend_position(std::uint64_t next_word, unsigned bits);
bool bend_field_candidate(std::uint64_t next_word);
}
