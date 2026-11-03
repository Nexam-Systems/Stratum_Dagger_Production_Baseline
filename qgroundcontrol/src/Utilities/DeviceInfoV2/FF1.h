#pragma once

#include <cstdint>
#include <vector>

// AES-FF1 format-preserving encryption (NIST SP 800-38G) over AES-128.
//
// Direct port of the verified Python reference (scripts/device_info_v2/ff1.py).
// Constrained to parameter ranges where each half fits in 64 bits (radix^ceil(n/2)
// <= 2^64 and d <= 8), which covers the Device Information Protocol V2 use
// (radix 2, 64 numerals) and the NIST FF1-AES128 sample vectors (radix 10).

namespace DeviceInfoV2 {

// numerals: digits in [0, radix). Returns the 10-round FF1 permutation.
std::vector<uint8_t> ff1Encrypt(const uint8_t key[16], const uint8_t* tweak, size_t tweakLen,
                                const std::vector<uint8_t>& numerals, uint32_t radix);

std::vector<uint8_t> ff1Decrypt(const uint8_t key[16], const uint8_t* tweak, size_t tweakLen,
                                const std::vector<uint8_t>& numerals, uint32_t radix);

} // namespace DeviceInfoV2
