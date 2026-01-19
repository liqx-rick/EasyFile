// Stub implementations for LZMA SDK hardware-accelerated functions
// 这些函数在 AesOpt.c 和 Sha256Opt.c 中实现，但我们不编译这些文件
// 提供空实现以解决链接错误

#include "lzma/C/CpuArch.h"
#include "lzma/C/Aes.h"
#include "lzma/C/Sha256.h"

// AES 硬件加速 stub
void MY_FAST_CALL AesCbc_Encode_HW(UInt32 *ivAes, Byte *data, size_t numBlocks) {
    // 永远不会被调用（因为 CPU_IsSupported_AES() 返回false）
    (void)ivAes;
    (void)data;
    (void)numBlocks;
}

void MY_FAST_CALL AesCbc_Decode_HW(UInt32 *ivAes, Byte *data, size_t numBlocks) {
    (void)ivAes;
    (void)data;
    (void)numBlocks;
}

void MY_FAST_CALL AesCtr_Code_HW(UInt32 *ivAes, Byte *data, size_t numBlocks) {
    (void)ivAes;
    (void)data;
    (void)numBlocks;
}

#ifdef MY_CPU_X86_OR_AMD64
void MY_FAST_CALL AesCbc_Decode_HW_256(UInt32 *ivAes, Byte *data, size_t numBlocks) {
    (void)ivAes;
    (void)data;
    (void)numBlocks;
}

void MY_FAST_CALL AesCtr_Code_HW_256(UInt32 *ivAes, Byte *data, size_t numBlocks) {
    (void)ivAes;
    (void)data;
    (void)numBlocks;
}
#endif

// SHA256 硬件加速 stub
void MY_FAST_CALL Sha256_UpdateBlocks_HW(UInt32 state[8], const Byte *data, size_t numBlocks) {
    (void)state;
    (void)data;
    (void)numBlocks;
}
