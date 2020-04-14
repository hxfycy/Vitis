#include <ap_int.h>
#include <cstdlib>
#include <iostream>
#define DATAWIDTH 256  //32byte
#define BUFF_LEN  32
#define DATA_SIZE 16384

typedef ap_uint<DATAWIDTH> fixed;

// TRIPCOUNT identifier
const unsigned c_len = DATA_SIZE / BUFF_LEN;
const unsigned c_size = BUFF_LEN;

extern "C" {
void rand_acc(const fixed *in1, const fixed *in2,  fixed *out,
              unsigned length) {
#pragma HLS INTERFACE m_axi port = in1 offset = slave bundle = inmem1
#pragma HLS INTERFACE m_axi port = in2 offset = slave bundle = inmem2
#pragma HLS INTERFACE m_axi port = out offset = slave bundle = out_mem
#pragma HLS INTERFACE s_axilite port = in1 bundle = control
#pragma HLS INTERFACE s_axilite port = in2 bundle = control
#pragma HLS INTERFACE s_axilite port = out bundle = control
#pragma HLS INTERFACE s_axilite port = length bundle = control
#pragma HLS INTERFACE s_axilite port = return bundle = control
  //srand(0);
  unsigned idx_buff[BUFF_LEN];
  //std::hash <unsigned> ha;
  //idx_buff[0]=rand();
  idx_buff[0]=1;
  for(int i=1; i<BUFF_LEN;i++){
	 idx_buff[i]=((idx_buff[i-1]<<4)^idx_buff[i-1]+1)%length;
  }
	  
  fixed val_buff1[BUFF_LEN];
  fixed val_buff2[BUFF_LEN];
  //unsigned out;
  for (int i = 0; i < length; i += BUFF_LEN) {
#pragma HLS LOOP_TRIPCOUNT min = c_len max = c_len
    int chunk_size = BUFF_LEN;
    // boundary checks
    if ((i + BUFF_LEN) > length)
      chunk_size = length - i;

  read_in:
    for (int j = 0; j < chunk_size; j++) {
#pragma HLS LOOP_TRIPCOUNT min = c_size max = c_size
#pragma HLS PIPELINE II = 1
      val_buff1[j] = in1[idx_buff[j]];
	  val_buff2[j] = in2[idx_buff[j]];
    }
	
/* test-random read only
*/
  write:
    for (int j = 0; j < chunk_size; j++) {
#pragma HLS LOOP_TRIPCOUNT min = c_size max = c_size
#pragma HLS PIPELINE II = 1
	  out[i + j] = val_buff1[j]+val_buff2[j];
      //out+=(((j%2)==1)?val_buff1[j]:val_buff2[j]);
    }
  }
}
}
