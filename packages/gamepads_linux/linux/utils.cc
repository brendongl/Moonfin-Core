#include "utils.h"

#include <algorithm>
#include <cstdio>
#include <sstream>
#include <string>

bool starts_with(const std::string& str, const std::string& prefix) {
  if (prefix.length() > str.length()) {
    return false;
  }
  return str.compare(0, prefix.length(), prefix) == 0;
}

static uint32_t pack(int vendor_id, int product_id) {
  return (static_cast<uint32_t>(vendor_id & 0xffff) << 16) |
         static_cast<uint32_t>(product_id & 0xffff);
}

std::optional<std::vector<uint32_t>> parse_vid_pid_list(const char* value) {
  if (value == nullptr || *value == '\0') {
    return std::nullopt;
  }
  std::vector<uint32_t> list;
  std::stringstream entries(value);
  std::string entry;
  while (std::getline(entries, entry, ',')) {
    unsigned int vendor = 0;
    unsigned int product = 0;
    if (std::sscanf(entry.c_str(), "%x/%x", &vendor, &product) == 2) {
      list.push_back(pack(vendor, product));
    }
  }
  return list;
}

bool is_steam_virtual_controller(int vendor_id, int product_id) {
  return vendor_id == 0x28de && product_id == 0x11ff;
}

static bool contains(const std::vector<uint32_t>& list,
                     int vendor_id,
                     int product_id) {
  return std::find(list.begin(), list.end(), pack(vendor_id, product_id)) !=
         list.end();
}

bool should_ignore_controller(
    int vendor_id,
    int product_id,
    const std::optional<std::vector<uint32_t>>& allowed,
    const std::optional<std::vector<uint32_t>>& ignored,
    bool steam_virtual_present) {
  if (is_steam_virtual_controller(vendor_id, product_id)) {
    return false;
  }
  if (allowed && !allowed->empty()) {
    return !contains(*allowed, vendor_id, product_id);
  }
  if (ignored) {
    return contains(*ignored, vendor_id, product_id);
  }
  return steam_virtual_present;
}
