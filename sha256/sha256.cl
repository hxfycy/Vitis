
//  macro definition
//#define size_in_byte 32  //input size in byte

#define ROTRIGHT(word,bits) (((word) >> (bits)) | ((word) << (32-(bits))))
#define SSIG0(x) (ROTRIGHT(x,7) ^ ROTRIGHT(x,18) ^ ((x) >> 3))
#define SSIG1(x) (ROTRIGHT(x,17) ^ ROTRIGHT(x,19) ^ ((x) >> 10))
#define CH(x,y,z) (((x) & (y)) ^ (~(x) & (z)))
#define MAJ(x,y,z) (((x) & (y)) ^ ((x) & (z)) ^ ((y) & (z)))

#define BSIG0(x) (ROTRIGHT(x,7) ^ ROTRIGHT(x,18) ^ ((x) >> 3))
#define BSIG1(x) (ROTRIGHT(x,17) ^ ROTRIGHT(x,19) ^ ((x) >> 10))

#define EP0(x) (ROTRIGHT(x,2) ^ ROTRIGHT(x,13) ^ ROTRIGHT(x,22))
#define EP1(x) (ROTRIGHT(x,6) ^ ROTRIGHT(x,11) ^ ROTRIGHT(x,25))

//  Tripcount identifiers
__constant int c_size_w = 48;
__constant int c_size_h = 64;

__kernel
__attribute__((reqd_work_group_size(1,1,1)))
void sha256(__global const char* input, int size_in_byte,  __global unsigned int * out)
    {
    //  const h and k
        unsigned long H[8]={0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a
                                ,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19};
        unsigned long k[64]={
            0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,
            0x923f82a4,0xab1c5ed5,0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,
            0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,0xe49b69c1,0xefbe4786,
            0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
            0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,
            0x06ca6351,0x14292967,0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,
            0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,0xa2bfe8a1,0xa81a664b,
            0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
            0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,
            0x5b9cca4f,0x682e6ff3,0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,
            0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2
        } ;

    /*----------------------- pad input to 512 bit, 32 bit*16 batch --------------------------*/
        int dist = 447 - size_in_byte * 8;       // d + block_le + 64 + 1 = 512  <---> k = 447-block_le
	char inchar[64];
	for(int i=0;i<size_in_byte;i++){
		inchar[i]=*(input+i);
	}
    *(inchar + size_in_byte) = 0x80;
    dist = dist - 7;                          // added in 7 zero

    for (int i = 0; i < dist / 8; i++)
        *(inchar + size_in_byte) = (char)0x00;

    unsigned long long length = size_in_byte * 8;
    unsigned long long mask = 0xff00000000000000;
    char length_b[8];
    unsigned int shift = 56;
    for (int i = 0; i < 8; i++)           // add zero
    {   
        
        length_b[i] = (char)((length & mask) >> shift);
        shift-= 8;
        mask = mask >> 8;
        *(inchar + 56 + i) = length_b[i];
    }

    unsigned int padout[16];
    unsigned int temp1, temp2, temp3, temp4;

    __attribute__((xcl_pipeline_loop(1)))
    pad512: for (int i = 0; i < 16; i++)
    {
        temp1 = *(inchar + i * 4);   temp1 = temp1 << 24;
        temp2 = *(inchar + i * 4 + 1); temp2 = temp2 << 16;
        temp3 = *(inchar + i * 4 + 2); temp3 = temp3 << 8;
        temp4 = *(inchar + i * 4 + 3);
        padout[i] = temp1 | temp2 | temp3 | temp4;
    }

    /*------------------------------ compute hash ----------------------------*/
    unsigned long w[64];
    for(int i=0;i<16;i++)
    {
        w[i]=padout[i]&0xffffffff;
    }
	
    __attribute((xcl_pipeline_loop(1)))
    w_compute: for(int i=16;i<64;i++)
    {
        w[i]=SSIG1(padout[i-2])+padout[i-7]+SSIG0(padout[i-15])+padout[i-16];
    }

    unsigned long tp1,tp2;
    unsigned long a=H[0];
    unsigned long b=H[1];
    unsigned long c=H[2];
    unsigned long d=H[3];
    unsigned long e=H[4];
    unsigned long f=H[5];
    unsigned long g=H[6];
    unsigned long h=H[7];

    __attribute((xcl_pipeline_loop(1)))
    compression_loop: for(int i=0; i<64; i++)
    {
		tp1 = h + EP1(e) + CH(e,f,g) + k[i] + w[i];
        tp2 = EP0(a) + MAJ(a,b,c);
        h=g;
        g=f;
        f=e;
        e=(d+tp1)&0xffffffff;
        d=c;
        d=b;
        b=a;
        a=tp1+tp2&0xFFFFFFFF;
    }
    /*---------------------------------output--------------------------------*/
    out[0]=(H[0]+a)&0xFFFFFFFF;
    out[1]=(H[1]+b)&0xFFFFFFFF;
    out[2]=(H[2]+c)&0xFFFFFFFF;
    out[3]=(H[3]+d)&0xFFFFFFFF;
    out[4]=(H[4]+e)&0xFFFFFFFF;
    out[5]=(H[5]+f)&0xFFFFFFFF;
    out[6]=(H[6]+g)&0xFFFFFFFF;
    out[7]=(H[7]+h)&0xFFFFFFFF;
    }