-- ============================================================
--  kc_mdt | shared/sh_sha256.lua
--  Pure-Lua SHA-256 implementation.
--  Server-side only — exposed via lib.sha256(string) -> hex
--  Performance: ~1ms pr. hash på moderne hardware. Mere end nok
--  til login/registermdt (hashes ikke i hot path).
-- ============================================================

local band, bor, bxor, bnot = bit32 and bit32.band or function() end, nil, nil, nil
-- Lua 5.4 har bitwise operators built-in; brug dem direkte for performance.

local function rrotate(n, b)
    return ((n >> b) | (n << (32 - b))) & 0xffffffff
end

local function to_hex(num)
    return string.format('%08x', num)
end

local K = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}

local function preprocess(msg)
    local len = #msg
    local bitLen = len * 8
    msg = msg .. '\128'
    -- Pad with zeros until length ≡ 56 (mod 64)
    while (#msg % 64) ~= 56 do
        msg = msg .. '\0'
    end
    -- Append 64-bit big-endian bit length
    for i = 7, 0, -1 do
        msg = msg .. string.char((bitLen >> (i * 8)) & 0xff)
    end
    return msg
end

local function processChunk(chunk, H)
    local w = {}
    for i = 0, 15 do
        local b1, b2, b3, b4 = string.byte(chunk, i*4 + 1, i*4 + 4)
        w[i+1] = (b1 << 24) | (b2 << 16) | (b3 << 8) | b4
    end
    for i = 17, 64 do
        local s0 = rrotate(w[i-15], 7) ~ rrotate(w[i-15], 18) ~ (w[i-15] >> 3)
        local s1 = rrotate(w[i-2], 17) ~ rrotate(w[i-2], 19) ~ (w[i-2] >> 10)
        w[i] = (w[i-16] + s0 + w[i-7] + s1) & 0xffffffff
    end

    local a, b, c, d, e, f, g, h = H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8]

    for i = 1, 64 do
        local S1 = rrotate(e, 6) ~ rrotate(e, 11) ~ rrotate(e, 25)
        local ch = (e & f) ~ ((~e) & 0xffffffff & g)
        local temp1 = (h + S1 + ch + K[i] + w[i]) & 0xffffffff
        local S0 = rrotate(a, 2) ~ rrotate(a, 13) ~ rrotate(a, 22)
        local mj = (a & b) ~ (a & c) ~ (b & c)
        local temp2 = (S0 + mj) & 0xffffffff

        h = g; g = f; f = e
        e = (d + temp1) & 0xffffffff
        d = c; c = b; b = a
        a = (temp1 + temp2) & 0xffffffff
    end

    H[1] = (H[1] + a) & 0xffffffff
    H[2] = (H[2] + b) & 0xffffffff
    H[3] = (H[3] + c) & 0xffffffff
    H[4] = (H[4] + d) & 0xffffffff
    H[5] = (H[5] + e) & 0xffffffff
    H[6] = (H[6] + f) & 0xffffffff
    H[7] = (H[7] + g) & 0xffffffff
    H[8] = (H[8] + h) & 0xffffffff
end

local function sha256(msg)
    local H = {
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
        0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
    }
    msg = preprocess(tostring(msg))
    for i = 1, #msg, 64 do
        processChunk(msg:sub(i, i + 63), H)
    end
    return to_hex(H[1])..to_hex(H[2])..to_hex(H[3])..to_hex(H[4])
        .. to_hex(H[5])..to_hex(H[6])..to_hex(H[7])..to_hex(H[8])
end

-- Expose globally (read by both client and server but only used server-side)
KC_SHA256 = sha256