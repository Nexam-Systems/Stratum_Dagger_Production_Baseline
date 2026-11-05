#include "FF1.h"

#include "AES128.h"

#include <cmath>
#include <cstring>

namespace {

using DeviceInfoV2::aes128EncryptBlock;

struct Params {
    int n;
    int t;
    int u;
    int v;
    int b;
    int d;
};

Params computeParams(size_t n, size_t t, uint32_t radix)
{
    Params p;
    p.n = static_cast<int>(n);
    p.t = static_cast<int>(t);
    p.u = static_cast<int>(n / 2);
    p.v = static_cast<int>(n - p.u);
    const int vbits = static_cast<int>(std::ceil(p.v * std::log2(static_cast<double>(radix))));
    p.b = static_cast<int>(std::ceil(vbits / 8.0));
    p.d = 4 * static_cast<int>(std::ceil(p.b / 4.0)) + 4;
    return p;
}

uint64_t numOf(const std::vector<uint8_t>& numerals, uint32_t radix)
{
    uint64_t x = 0;
    for (const uint8_t digit : numerals) {
        x = x * radix + digit;
    }
    return x;
}

std::vector<uint8_t> strOf(uint64_t x, uint32_t radix, int m)
{
    std::vector<uint8_t> out(static_cast<size_t>(m), 0);
    for (int i = m - 1; i >= 0; --i) {
        out[static_cast<size_t>(i)] = static_cast<uint8_t>(x % radix);
        x /= radix;
    }
    return out;
}

uint64_t ipow(uint32_t base, int exp)
{
    uint64_t result = 1;
    for (int i = 0; i < exp; ++i) {
        result *= base;
    }
    return result;
}

// CBC-MAC with a zero IV (the FF1 PRF). data length is a multiple of 16.
void prf(const uint8_t key[16], const std::vector<uint8_t>& data, uint8_t out[16])
{
    uint8_t y[16] = {0};
    for (size_t off = 0; off < data.size(); off += 16) {
        uint8_t block[16];
        for (int k = 0; k < 16; ++k) {
            block[k] = static_cast<uint8_t>(y[k] ^ data[off + static_cast<size_t>(k)]);
        }
        aes128EncryptBlock(key, block, y);
    }
    std::memcpy(out, y, 16);
}

// Computes the FF1 round value Y for the given half (NIST SP 800-38G, Alg. 7/8 step 6).
uint64_t computeY(const uint8_t key[16], const uint8_t* tweak, size_t t, uint32_t radix,
                  const Params& p, const std::vector<uint8_t>& half, int round)
{
    std::vector<uint8_t> data;
    data.reserve(static_cast<size_t>(16 + t + 16 + 1 + p.b));

    // P block (16 bytes).
    data.push_back(1);
    data.push_back(2);
    data.push_back(1);
    data.push_back(static_cast<uint8_t>((radix >> 16) & 0xFF));
    data.push_back(static_cast<uint8_t>((radix >> 8) & 0xFF));
    data.push_back(static_cast<uint8_t>(radix & 0xFF));
    data.push_back(10);
    data.push_back(static_cast<uint8_t>(p.u & 0xFF));
    const uint32_t nn = static_cast<uint32_t>(p.n);
    data.push_back(static_cast<uint8_t>((nn >> 24) & 0xFF));
    data.push_back(static_cast<uint8_t>((nn >> 16) & 0xFF));
    data.push_back(static_cast<uint8_t>((nn >> 8) & 0xFF));
    data.push_back(static_cast<uint8_t>(nn & 0xFF));
    const uint32_t tt = static_cast<uint32_t>(t);
    data.push_back(static_cast<uint8_t>((tt >> 24) & 0xFF));
    data.push_back(static_cast<uint8_t>((tt >> 16) & 0xFF));
    data.push_back(static_cast<uint8_t>((tt >> 8) & 0xFF));
    data.push_back(static_cast<uint8_t>(tt & 0xFF));

    // Q block: tweak | zero pad | round | NUM(half) as b bytes big-endian.
    for (size_t i = 0; i < t; ++i) {
        data.push_back(tweak[i]);
    }
    const int pad = (((-p.t - p.b - 1) % 16) + 16) % 16;
    for (int i = 0; i < pad; ++i) {
        data.push_back(0);
    }
    data.push_back(static_cast<uint8_t>(round));
    const uint64_t halfNum = numOf(half, radix);
    for (int i = p.b - 1; i >= 0; --i) {
        data.push_back(static_cast<uint8_t>((halfNum >> (8 * i)) & 0xFF));
    }

    uint8_t r[16];
    prf(key, data, r);

    std::vector<uint8_t> s(r, r + 16);
    uint32_t j = 1;
    while (static_cast<int>(s.size()) < p.d) {
        uint8_t block[16];
        std::memcpy(block, r, 16);
        block[12] ^= static_cast<uint8_t>((j >> 24) & 0xFF);
        block[13] ^= static_cast<uint8_t>((j >> 16) & 0xFF);
        block[14] ^= static_cast<uint8_t>((j >> 8) & 0xFF);
        block[15] ^= static_cast<uint8_t>(j & 0xFF);
        uint8_t enc[16];
        aes128EncryptBlock(key, block, enc);
        s.insert(s.end(), enc, enc + 16);
        ++j;
    }

    uint64_t y = 0;
    for (int i = 0; i < p.d; ++i) {
        y = (y << 8) | s[static_cast<size_t>(i)];
    }
    return y;
}

} // namespace

namespace DeviceInfoV2 {

std::vector<uint8_t> ff1Encrypt(const uint8_t key[16], const uint8_t* tweak, size_t tweakLen,
                                const std::vector<uint8_t>& numerals, uint32_t radix)
{
    const Params p = computeParams(numerals.size(), tweakLen, radix);
    std::vector<uint8_t> a(numerals.begin(), numerals.begin() + p.u);
    std::vector<uint8_t> b(numerals.begin() + p.u, numerals.end());

    for (int i = 0; i < 10; ++i) {
        const uint64_t y = computeY(key, tweak, tweakLen, radix, p, b, i);
        const int m = (i % 2 == 0) ? p.u : p.v;
        const uint64_t modulus = ipow(radix, m);
        const uint64_t c = (numOf(a, radix) + (y % modulus)) % modulus;
        a = b;
        b = strOf(c, radix, m);
    }

    std::vector<uint8_t> out = a;
    out.insert(out.end(), b.begin(), b.end());
    return out;
}

std::vector<uint8_t> ff1Decrypt(const uint8_t key[16], const uint8_t* tweak, size_t tweakLen,
                                const std::vector<uint8_t>& numerals, uint32_t radix)
{
    const Params p = computeParams(numerals.size(), tweakLen, radix);
    std::vector<uint8_t> a(numerals.begin(), numerals.begin() + p.u);
    std::vector<uint8_t> b(numerals.begin() + p.u, numerals.end());

    for (int i = 9; i >= 0; --i) {
        const uint64_t y = computeY(key, tweak, tweakLen, radix, p, a, i);
        const int m = (i % 2 == 0) ? p.u : p.v;
        const uint64_t modulus = ipow(radix, m);
        const uint64_t yMod = y % modulus;
        const uint64_t c = ((numOf(b, radix) % modulus) + modulus - yMod) % modulus;
        b = a;
        a = strOf(c, radix, m);
    }

    std::vector<uint8_t> out = a;
    out.insert(out.end(), b.begin(), b.end());
    return out;
}

} // namespace DeviceInfoV2
