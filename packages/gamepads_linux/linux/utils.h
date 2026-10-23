#include <cstdint>
#include <memory>
#include <optional>
#include <stdexcept>
#include <string>
#include <vector>

bool starts_with(const std::string& string, const std::string& prefix);

// The vendor/product pairs in an SDL controller list such as
// "0x2dc8/0x310b,0x28de/0x0000", packed as (vendor << 16) | product. Null when
// [value] is null or empty, so an unset variable can be told from one that
// lists nothing readable.
std::optional<std::vector<uint32_t>> parse_vid_pid_list(const char* value);

// Whether a controller's input should be dropped, following the rules SDL
// applies to the lists Steam Input sets for the apps it launches: [allowed] is
// SDL_GAMECONTROLLER_IGNORE_DEVICES_EXCEPT and [ignored] is
// SDL_GAMECONTROLLER_IGNORE_DEVICES. Steam's virtual controller is always
// kept. Without either list, a real controller is dropped while
// [steam_virtual_present], since Steam is already passing it through.
bool should_ignore_controller(
    int vendor_id,
    int product_id,
    const std::optional<std::vector<uint32_t>>& allowed,
    const std::optional<std::vector<uint32_t>>& ignored,
    bool steam_virtual_present);

bool is_steam_virtual_controller(int vendor_id, int product_id);
