#pragma once

#include <cstdint>

// Minimal AES-128 block-cipher forward transform (FIPS-197), used only as the
// PRF primitive for FF1 format-preserving encryption. This is a self-contained,
// dependency-free implementation adapted from the public-domain tiny-AES-c
// project (https://github.com/kokke/tiny-AES-c, Unlicense). Only the 128-bit
// ECB forward path is needed: FF1 never calls AES decryption.

namespace DeviceInfoV2 {

// Encrypts a single 16-byte block with a 16-byte key. in and out may alias.
void aes128EncryptBlock(const uint8_t key[16], const uint8_t in[16], uint8_t out[16]);

} // namespace DeviceInfoV2
