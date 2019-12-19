#include <string.h>
#include <cstdio>

#define SHA2_SHFR(x, n)    (x >> n)
#define SHA2_ROTR(x, n)   ((x >> n) | (x << ((sizeof(x) << 3) - n)))
#define SHA2_ROTL(x, n)   ((x << n) | (x >> ((sizeof(x) << 3) - n)))
#define SHA2_CH(x, y, z)  ((x & y) ^ (~x & z))
#define SHA2_MAJ(x, y, z) ((x & y) ^ (x & z) ^ (y & z))
#define SHA256_F1(x) (SHA2_ROTR(x,  2) ^ SHA2_ROTR(x, 13) ^ SHA2_ROTR(x, 22))
#define SHA256_F2(x) (SHA2_ROTR(x,  6) ^ SHA2_ROTR(x, 11) ^ SHA2_ROTR(x, 25))
#define SHA256_F3(x) (SHA2_ROTR(x,  7) ^ SHA2_ROTR(x, 18) ^ SHA2_SHFR(x,  3))
#define SHA256_F4(x) (SHA2_ROTR(x, 17) ^ SHA2_ROTR(x, 19) ^ SHA2_SHFR(x, 10))
#define SHA2_UNPACK32(x, str)                 \
{                                             \
    *((str) + 3) = (uint8) ((x)      );       \
    *((str) + 2) = (uint8) ((x) >>  8);       \
    *((str) + 1) = (uint8) ((x) >> 16);       \
    *((str) + 0) = (uint8) ((x) >> 24);       \
}
#define SHA2_PACK32(str, x)                   \
{                                             \
    *(x) =   ((uint32) *((str) + 3)      )    \
           | ((uint32) *((str) + 2) <<  8)    \
           | ((uint32) *((str) + 1) << 16)    \
           | ((uint32) *((str) + 0) << 24);   \
}
#define  SHA224_256_BLOCK_SIZE  64
#define  DIGEST_SIZE 32
 
struct Input {
    char a[32];
};

struct Output {
    unsigned char digest[DIGEST_SIZE];
};


class SHA256
{
protected:
    typedef unsigned char uint8;
    typedef unsigned int uint32;
    typedef unsigned long long uint64;
   
    uint32 sha256_k[64];
			 
public:
    __attribute__((always_inline)) SHA256()
    {
        sha256_k[0] = 0x428a2f98; sha256_k[1] = 0x71374491; sha256_k[2] = 0xb5c0fbcf; sha256_k[3] = 0xe9b5dba5;
        sha256_k[4] = 0x3956c25b; sha256_k[5] = 0x59f111f1; sha256_k[6] = 0x923f82a4; sha256_k[7] = 0xab1c5ed5;
        sha256_k[8] = 0xd807aa98; sha256_k[9] = 0x12835b01; sha256_k[10] = 0x243185be; sha256_k[11] = 0x550c7dc3;
        sha256_k[12] = 0x72be5d74; sha256_k[13] = 0x80deb1fe; sha256_k[14] = 0x9bdc06a7; sha256_k[15] = 0xc19bf174;
        sha256_k[16] = 0xe49b69c1; sha256_k[17] = 0xefbe4786; sha256_k[18] = 0xfc19dc6; sha256_k[19] = 0x240ca1cc;
        sha256_k[20] = 0x2de92c6f; sha256_k[21] = 0x4a7484aa; sha256_k[22] = 0x5cb0a9dc; sha256_k[23] = 0x76f988da;
        sha256_k[24] = 0x983e5152; sha256_k[25] = 0xa831c66d; sha256_k[26] = 0xb00327c8; sha256_k[27] = 0xbf597fc7;
        sha256_k[28] = 0xc6e00bf3; sha256_k[29] = 0xd5a79147; sha256_k[30] = 0x6ca6351; sha256_k[31] = 0x14292967;
        sha256_k[32] = 0x27b70a85; sha256_k[33] = 0x2e1b2138; sha256_k[34] = 0x4d2c6dfc; sha256_k[35] = 0x53380d13;
        sha256_k[36] = 0x650a7354; sha256_k[37] = 0x766a0abb; sha256_k[38] = 0x81c2c92e; sha256_k[39] = 0x92722c85;
        sha256_k[40] = 0xa2bfe8a1; sha256_k[41] = 0xa81a664b; sha256_k[42] = 0xc24b8b70; sha256_k[43] = 0xc76c51a3;
        sha256_k[44] = 0xd192e819; sha256_k[45] = 0xd6990624; sha256_k[46] = 0xf40e3585; sha256_k[47] = 0x106aa070;
        sha256_k[48] = 0x19a4c116; sha256_k[49] = 0x1e376c08; sha256_k[50] = 0x2748774c; sha256_k[51] = 0x34b0bcb5;
        sha256_k[52] = 0x391c0cb3; sha256_k[53] = 0x4ed8aa4a; sha256_k[54] = 0x5b9cca4f; sha256_k[55] = 0x682e6ff3;
        sha256_k[56] = 0x748f82ee; sha256_k[57] = 0x78a5636f; sha256_k[58] = 0x84c87814; sha256_k[59] = 0x8cc70208;
        sha256_k[60] = 0x90befffa; sha256_k[61] = 0xa4506ceb; sha256_k[62] = 0xbef9a3f7; sha256_k[63] = 0xc67178f2;

        m_h[0] = 0x6a09e667;
        m_h[1] = 0xbb67ae85;
        m_h[2] = 0x3c6ef372;
        m_h[3] = 0xa54ff53a;
        m_h[4] = 0x510e527f;
        m_h[5] = 0x9b05688c;
        m_h[6] = 0x1f83d9ab;
        m_h[7] = 0x5be0cd19;

        m_len = 0;
        m_tot_len = 0;
    }

	void update(const unsigned char *message, unsigned int len);
    void final(unsigned char *digest);
   
protected:
	void transform(const unsigned char *message, unsigned int block_nb);
    unsigned int m_tot_len;
    unsigned int m_len;
    unsigned char m_block[2*SHA224_256_BLOCK_SIZE];
    uint32 m_h[8];
};
 
 extern "C" {
    void outsource(Input *, Output *);
   extern void _unroll_hint(unsigned);
};

inline __attribute__((always_inline)) void SHA256::transform(const unsigned char *message, unsigned int block_nb)
{
    uint32 w[64];
    uint32 wv[8];
    uint32 t1, t2;
    const unsigned char *sub_block;
    int i;
    int j;
    for (i = 0; i < (int) block_nb; i++) {
        sub_block = message + (i << 6);
        for (j = 0; j < 16; j++) {
            SHA2_PACK32(&sub_block[j << 2], &w[j]);
        }
        for (j = 16; j < 64; j++) {
            w[j] =  SHA256_F4(w[j -  2]) + w[j -  7] + SHA256_F3(w[j - 15]) + w[j - 16];
        }
        for (j = 0; j < 8; j++) {
            wv[j] = m_h[j];
        }
        for (j = 0; j < 64; j++) {
            t1 = wv[7] + SHA256_F2(wv[4]) + SHA2_CH(wv[4], wv[5], wv[6])
                + sha256_k[j] + w[j];
            t2 = SHA256_F1(wv[0]) + SHA2_MAJ(wv[0], wv[1], wv[2]);
            wv[7] = wv[6];
            wv[6] = wv[5];
            wv[5] = wv[4];
            wv[4] = wv[3] + t1;
            wv[3] = wv[2];
            wv[2] = wv[1];
            wv[1] = wv[0];
            wv[0] = t1 + t2;
        }
        for (j = 0; j < 8; j++) {
            m_h[j] += wv[j];
        }
    }
}

inline __attribute__((always_inline)) void * memcopy( unsigned char * destination, const  unsigned char * source, size_t num )
{
	for (int i = 0 ; i < num ; ++i)
	{
		*(destination+i) = *(source+i);
	}
	return destination;
}


inline __attribute__((always_inline)) void SHA256::update(const unsigned char *message, unsigned int len)
{
    unsigned int block_nb;
    unsigned int new_len, rem_len, tmp_len;
    const unsigned char *shifted_message;
    tmp_len = SHA224_256_BLOCK_SIZE - m_len;
    rem_len = len < tmp_len ? len : tmp_len;
    memcopy(&m_block[m_len], message, rem_len);
    if (m_len + len < SHA224_256_BLOCK_SIZE) {
        m_len += len;
        return;
    }
    new_len = len - rem_len;
    block_nb = new_len / SHA224_256_BLOCK_SIZE;
    shifted_message = message + rem_len;
    transform(m_block, 1);
    transform(shifted_message, block_nb);
    rem_len = new_len % SHA224_256_BLOCK_SIZE;
    memcopy(m_block, &shifted_message[block_nb << 6], rem_len);
    m_len = rem_len;
    m_tot_len += (block_nb + 1) << 6;
}
 
 inline __attribute__((always_inline)) void SHA256::final(unsigned char *digest)
{
    unsigned int block_nb;
    unsigned int pm_len;
    unsigned int len_b;
    int i;
    block_nb = (1 + ((SHA224_256_BLOCK_SIZE - 9)
                     < (m_len % SHA224_256_BLOCK_SIZE)));
    len_b = (m_tot_len + m_len) << 3;
    pm_len = block_nb << 6;
    //memset(m_block + m_len, 0, pm_len - m_len);
	for (int i=0; i< pm_len - m_len; ++i)
		(m_block + m_len)[i] = 0;
	
    m_block[m_len] = 0x80;
    SHA2_UNPACK32(len_b, m_block + pm_len - 4);
    transform(m_block, block_nb);
    for (i = 0 ; i < 8; i++) {
        SHA2_UNPACK32(m_h[i], &digest[i << 2]);
    }
}
 
 

void outsource(struct Input *input, struct Output *output)
{	
	
	unsigned char digest[DIGEST_SIZE];
    //memset(digest,0,SHA256::DIGEST_SIZE);
	for (int i = 0; i < DIGEST_SIZE; i++)
		digest[i] = 0;
	
    SHA256 ctx;
	int input_size=sizeof(input->a) / sizeof(input->a[0]);
    ctx.update( (unsigned char*)input->a, input_size);
    ctx.final(digest);
 
    char buf[2*DIGEST_SIZE+1];
    buf[2*DIGEST_SIZE] = 0;
    for (int i = 0; i < DIGEST_SIZE; i++)
	{
		buf[i] = 0;
		buf[i+1] =0;
  //      sprintf(buf+i*2, "%02x", digest[i]);
		output->digest[i] = digest[i];
	}
	
    //return std::string(buf);
}
