//
//  BTKey+Bitcoinj.m
//  bitheri
//
//  Copyright 2014 http://Bither.net
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.

#import "BTKey+Bitcoinj.h"
#import "NSString+Base58.h"
#import "NSMutableData+Bitcoin.h"
#import "NSData+Bitcoin.h"
#import <CommonCrypto/CommonCrypto.h>
#import <openssl/ecdsa.h>

#define BITCOINJ_SCRYPT_N        16384
#define BITCOINJ_SCRYPT_R        8
#define BITCOINJ_SCRYPT_P        1

// bitwise left rotation, this will typically be compiled into a single instruction
#define rotl(a, b) (((a) << (b)) | ((a) >> (32 - (b))))

// salsa20/8 stream cypher: http://cr.yp.to/snuffle.html
static void salsa20_8(uint32_t b[16])
{
    uint32_t x00 = b[0], x01 = b[1], x02 = b[2], x03 = b[3], x04 = b[4], x05 = b[5], x06 = b[6], x07 = b[7],
            x08 = b[8], x09 = b[9], x10 = b[10], x11 = b[11], x12 = b[12], x13 = b[13], x14 = b[14], x15 = b[15];

    for (int i = 0; i < 8; i += 2) {
        // operate on columns
        x04 ^= rotl(x00 + x12, 7), x08 ^= rotl(x04 + x00, 9), x12 ^= rotl(x08 + x04, 13), x00 ^= rotl(x12 + x08, 18);
        x09 ^= rotl(x05 + x01, 7), x13 ^= rotl(x09 + x05, 9), x01 ^= rotl(x13 + x09, 13), x05 ^= rotl(x01 + x13, 18);
        x14 ^= rotl(x10 + x06, 7), x02 ^= rotl(x14 + x10, 9), x06 ^= rotl(x02 + x14, 13), x10 ^= rotl(x06 + x02, 18);
        x03 ^= rotl(x15 + x11, 7), x07 ^= rotl(x03 + x15, 9), x11 ^= rotl(x07 + x03, 13), x15 ^= rotl(x11 + x07, 18);

        // operate on rows
        x01 ^= rotl(x00 + x03, 7), x02 ^= rotl(x01 + x00, 9), x03 ^= rotl(x02 + x01, 13), x00 ^= rotl(x03 + x02, 18);
        x06 ^= rotl(x05 + x04, 7), x07 ^= rotl(x06 + x05, 9), x04 ^= rotl(x07 + x06, 13), x05 ^= rotl(x04 + x07, 18);
        x11 ^= rotl(x10 + x09, 7), x08 ^= rotl(x11 + x10, 9), x09 ^= rotl(x08 + x11, 13), x10 ^= rotl(x09 + x08, 18);
        x12 ^= rotl(x15 + x14, 7), x13 ^= rotl(x12 + x15, 9), x14 ^= rotl(x13 + x12, 13), x15 ^= rotl(x14 + x13, 18);
    }

    b[0] += x00, b[1] += x01, b[2] += x02, b[3] += x03, b[4] += x04, b[5] += x05, b[6] += x06, b[7] += x07;
    b[8] += x08, b[9] += x09, b[10] += x10, b[11] += x11, b[12] += x12, b[13] += x13, b[14] += x14, b[15] += x15;
}

static void blockmix_salsa8(uint64_t *dest, const uint64_t *src, uint64_t *b, uint32_t r)
{
    memcpy(b, &src[(2*r - 1)*8], 64);

    for (uint32_t i = 0; i < 2*r; i += 2) {
        for (uint32_t j = 0; j < 8; j++) b[j] ^= src[i*8 + j];
        salsa20_8((uint32_t *)b);
        memcpy(&dest[i*4], b, 64);
        for (uint32_t j = 0; j < 8; j++) b[j] ^= src[i*8 + 8 + j];
        salsa20_8((uint32_t *)b);
        memcpy(&dest[i*4 + r*8], b, 64);
    }
}

// scrypt key derivation: http://www.tarsnap.com/scrypt.html
static NSData *scrypt(NSData *password, NSData *salt, int64_t n, uint32_t r, uint32_t p, NSUInteger length)
{
    NSMutableData *d = [NSMutableData secureDataWithLength:length];
    uint8_t b[128*r*p];
    uint64_t x[16*r], y[16*r], z[8], *v = OPENSSL_malloc(128*r*(int)n), m;

    CCKeyDerivationPBKDF(kCCPBKDF2, password.bytes, password.length, salt.bytes, salt.length, kCCPRFHmacAlgSHA256, 1,
            b, sizeof(b));

    for (uint32_t i = 0; i < p; i++) {
        for (uint32_t j = 0; j < 32*r; j++) {
            ((uint32_t *)x)[j] = CFSwapInt32LittleToHost(*(uint32_t *)&b[i*128*r + j*4]);
        }

        for (uint64_t j = 0; j < n; j += 2) {
            memcpy(&v[j*(16*r)], x, 128*r);
            blockmix_salsa8(y, x, z, r);
            memcpy(&v[(j + 1)*(16*r)], y, 128*r);
            blockmix_salsa8(x, y, z, r);
        }

        for (uint64_t j = 0; j < n; j += 2) {
            m = CFSwapInt64LittleToHost(x[(2*r - 1)*8]) & (n - 1);
            for (uint32_t k = 0; k < 16*r; k++) x[k] ^= v[m*(16*r) + k];
            blockmix_salsa8(y, x, z, r);
            m = CFSwapInt64LittleToHost(y[(2*r - 1)*8]) & (n - 1);
            for (uint32_t k = 0; k < 16*r; k++) y[k] ^= v[m*(16*r) + k];
            blockmix_salsa8(x, y, z, r);
        }

        for (uint32_t j = 0; j < 32*r; j++) {
            *(uint32_t *)&b[i*128*r + j*4] = CFSwapInt32HostToLittle(((uint32_t *)x)[j]);
        }
    }

    CCKeyDerivationPBKDF(kCCPBKDF2, password.bytes, password.length, b, sizeof(b), kCCPRFHmacAlgSHA256, 1,
            d.mutableBytes, d.length);

    OPENSSL_cleanse(b, sizeof(b));
    OPENSSL_cleanse(x, sizeof(x));
    OPENSSL_cleanse(y, sizeof(y));
    OPENSSL_cleanse(z, sizeof(z));
    OPENSSL_cleanse(v, (size_t) (128*r*n));
    OPENSSL_free(v);
    OPENSSL_cleanse(&m, sizeof(m));
    return d;
}

@implementation BTKey (Bitcoinj)

+ (instancetype)keyWithBitcoinj:(NSString *)key andPassphrase:(NSString *)passphrase;{
    return [[self alloc] initKeyWithBitcoinj:key andPassphrase:passphrase];
}

- (instancetype)initKeyWithBitcoinj:(NSString *)key andPassphrase:(NSString *)passphrase;{
    NSArray *array = [key componentsSeparatedByString:@":"];

    NSData *secret = [self decryptFrom:[array[0] hexToData] andPassphrase:passphrase andSalt:[array[2] hexToData] andIV:[array[1] hexToData]];
    if (secret == nil)
        return nil;

    if (! (self = [self initWithSecret:secret compressed:YES])) return nil;
    return self;
}

- (NSString *)bitcoinjKeyWithPassphrase:(NSString *)passphrase andSalt:(NSData *)salt andIV:(NSData *) iv;{
    NSData *secret = [[self.privateKey base58checkToData] subdataWithRange:NSMakeRange(1, 32)];
    return [NSString stringWithFormat:@"%@:%@:%@"
            , [NSString hexWithData:[self encryptSecret:secret withPassphrase:passphrase andSalt:salt andIV:iv]]
            , [NSString hexWithData:iv], [NSString hexWithData:salt]];
}


// encrypts receiver with passphrase and returns Bitcoinj key
- (NSData *)encryptSecret:(NSData *)secret withPassphrase:(NSString *)passphrase andSalt:(NSData *)salt andIV:(NSData *) iv
{
    NSData *password = [passphrase dataUsingEncoding:NSUTF16BigEndianStringEncoding];
    NSData *derived = scrypt(password, salt, BITCOINJ_SCRYPT_N, BITCOINJ_SCRYPT_R, BITCOINJ_SCRYPT_P, 32);

    CCOperation operation = kCCEncrypt;
    NSData *result = [self doCipher:secret iv:iv key:derived operation:operation];

    return  result;
}

- (NSData *)decryptFrom:(NSData *)encrypted andPassphrase:(NSString *)passphrase andSalt:(NSData *)salt andIV:(NSData *) iv;{
    NSData *password = [passphrase dataUsingEncoding:NSUTF16BigEndianStringEncoding];
    NSData *derived = scrypt(password, salt, BITCOINJ_SCRYPT_N, BITCOINJ_SCRYPT_R, BITCOINJ_SCRYPT_P, 32);

    CCOperation operation = kCCDecrypt;
    NSData *result = [self doCipher:encrypted iv:iv key:derived operation:operation];
    return result;
}

- (NSData *)doCipher:(NSData *)data iv:(NSData *)iv key:(NSData *)key operation:(CCOperation)operation {
    if (operation == kCCDecrypt && ![self checkCipher:data iv:iv key:key operation:operation])
        return nil;

    NSMutableData *buffer;
    size_t len, actualLen = 0, remainLen;
    CCCryptorRef cryptor;
    if (CCCryptorCreateWithMode(operation, kCCModeCBC, kCCAlgorithmAES, kCCOptionPKCS7Padding, iv.bytes
            , key.bytes, kCCKeySizeAES256, NULL, 0, 0, kCCModeOptionCTR_BE, &cryptor) == kCCSuccess){
        remainLen = CCCryptorGetOutputLength(cryptor, data.length, true);
        buffer = [NSMutableData secureDataWithLength:(NSUInteger) remainLen];

        if (CCCryptorUpdate(cryptor, data.bytes, data.length, buffer.mutableBytes, buffer.length, &len) == kCCSuccess){
            remainLen -= len;
            actualLen += len;
        }

        if (CCCryptorFinal(cryptor, buffer.mutableBytes + len, remainLen, &len) == kCCSuccess){
            actualLen += len;
            CCCryptorRelease(cryptor);
            cryptor = NULL;
        }
    }
    NSData *result = [buffer subdataWithRange:NSMakeRange(0, actualLen)];
    return result;
}

- (BOOL)checkCipher:(NSData *)data iv:(NSData *)iv key:(NSData *)key operation:(CCOperation)operation {
    NSMutableData *buffer;
    size_t len, actualLen = 0, remainLen;
    CCCryptorRef cryptor;
    if (CCCryptorCreateWithMode(operation, kCCModeCBC, kCCAlgorithmAES, kCCOptionECBMode, iv.bytes
            , key.bytes, kCCKeySizeAES256, NULL, 0, 0, kCCModeOptionCTR_BE, &cryptor) == kCCSuccess){
        remainLen = CCCryptorGetOutputLength(cryptor, data.length, true);
        buffer = [NSMutableData secureDataWithLength:(NSUInteger) remainLen];

        if (CCCryptorUpdate(cryptor, data.bytes, data.length, buffer.mutableBytes, buffer.length, &len) == kCCSuccess){
            remainLen -= len;
            actualLen += len;
        }

        if (CCCryptorFinal(cryptor, buffer.mutableBytes + len, remainLen, &len) == kCCSuccess){
            actualLen += len;
            CCCryptorRelease(cryptor);
            cryptor = NULL;
        }
    }
    if (buffer.length == 48) {
        for (NSUInteger i = 32; i < 48; i++){
            if ([buffer UInt8AtOffset:i] != 0x10)
                return NO;
        }
        return YES;
    } else {
        return NO;
    }
}

+ (NSData *)saltWithBitcoinj:(NSString *)key;{
    NSArray *array = [key componentsSeparatedByString:@":"];
    if ([array count] == 3)
        return [array[2] hexToData];
    else
        return nil;
}

+ (NSData *)ivWithBitcoinj:(NSString *)key;{
    NSArray *array = [key componentsSeparatedByString:@":"];
    if ([array count] == 3)
        return [array[1] hexToData];
    else
        return nil;
}

@end