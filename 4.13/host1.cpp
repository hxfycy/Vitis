#include "xcl2.hpp"
#include <vector>
#include <algorithm>
#include <cstdlib>




int main(int argc, char **argv) {
  if (argc != 2) {
    std::cout << "Usage: " << argv[0] << " <XCLBIN File>" << std::endl;
    return EXIT_FAILURE;
  }
  std::string bin_file = argv[1];

  cl_int err;

  auto constexpr num_cu = 1;

  cl::CommandQueue q;
  cl::Context context;
  std::vector<cl::Kernel> krnl_rand_acc(num_cu);

  auto devices = xcl::get_xil_devices();
  auto file_buf = xcl::read_binary_file(bin_file);
  cl::Program::Binaries bins{{file_buf.data(), file_buf.size()}};

  int valid_device = 0;
  for (unsigned int i = 0; i < devices.size(); i++) {
    auto device = devices[i];
    // Creating Context and Command Queue for selected Device
    OCL_CHECK(err, context = cl::Context(device, NULL, NULL, NULL, &err));
    OCL_CHECK(err,
              q = cl::CommandQueue(context, device,
                                   CL_QUEUE_PROFILING_ENABLE |
                                       CL_QUEUE_OUT_OF_ORDER_EXEC_MODE_ENABLE,
                                   &err));

    std::cout << "Trying to program device[" << i
              << "]: " << device.getInfo<CL_DEVICE_NAME>() << std::endl;
    cl::Program program(context, {device}, bins, NULL, &err);

    //if (err != CL_SUCCESS) {
		if ((err != CL_SUCCESS)&&(device.getInfo<CL_DEVICE_NAME>()!="xilinx_u250_xdma_201830_2")){
      std::cout << "Failed to program device[" << i << "] with xclbin file!\n";
    } else {
      std::cout << "Device[" << i << "]: program successful!\n";
      for (int i = 0; i < num_cu; i++) {
        OCL_CHECK(err,
                  krnl_rand_acc[i] = cl::Kernel(program, "rand_acc", &err));
      }
      valid_device++;
      break; // we break because we found a valid device
    }
  }
  if (valid_device == 0) {
    std::cout << "Failed to program any device found, exit!\n";
    exit(EXIT_FAILURE);
  }

  unsigned length = 1024 * 1024 * 16; /* 1 GB / 512bit */
  unsigned length_int=1024*1024*128;  /* 1GB / 32bit*2 */
  /* Reduce the data length for emulation mode */
  if (xcl::is_emulation()) {
    length = 64; /* 4 KB */
  }
  unsigned data_size = length * 32;//each channel fixed 256 bit=32 byte
	
  //unsigned *out_sim = (unsigned *)aligned_alloc(4096, data_size);
  //unsigned *out_host = (unsigned *)aligned_alloc(4096, data_size);
  //fixed *out=(fixed *)aligned_alloc(16384,sizeof(unsigned)*num_cu);
  //fixed *idx_host = (fixed *)aligned_alloc(16384, data_size);
  //fixed *in_host1 = (fixed *)aligned_alloc(16384, data_size);
  
  std::vector <unsigned int ,aligned_allocator<unsigned int>> in_1(
  length_int);
  std::vector <unsigned int ,aligned_allocator<unsigned int>> in_2(
  length_int); 
  std::vector <unsigned int ,aligned_allocator<unsigned int>> out_vec(
  length_int);
  
  
  for (auto i = 0; i < length_int; i++) {
    in_1[i] = (unsigned)(i % 256);
	in_2[i] = (unsigned)(i % 256);
	out_vec[i]=0;
  }
	/*
  srand(0);
  for (auto i = 0; i < length; i++) {
    idx_host[i] = (rand() * (rand() + 1)) % length;
    //out_sim[i] = in_host[idx_host[i]];
  }
	*/
  //unsigned chunk_size = data_size / num_cu;
  //unsigned chunk_length = length / num_cu;
  //unsigned out_chunk=64/num_cu ;
  
  //cl::Buffer in_dev;
  //std::vector<cl::Buffer> idx_dev(num_cu);
  //std::vector<cl::Buffer> out_dev(num_cu);

  OCL_CHECK(err,
            cl::Buffer buffer_in1(context, CL_MEM_USE_HOST_PTR | CL_MEM_READ_ONLY,
                                data_size, in_1.data(), &err));
  OCL_CHECK(err,
            cl::Buffer buffer_in2(context, CL_MEM_USE_HOST_PTR | CL_MEM_READ_ONLY,
                                data_size, in_2.data(), &err));
  OCL_CHECK(err,
            cl::Buffer buffer_out(context, CL_MEM_USE_HOST_PTR | CL_MEM_WRITE_ONLY,
                                data_size, out_vec.data(), &err));
	/*
	OCL_CHECK(err, out_dev[i] = cl::Buffer(
                       context, CL_MEM_USE_HOST_PTR | CL_MEM_WRITE_ONLY,
                       sizeof(unsigned), out + i * out_chunk, &err));
	*/

  std::vector<cl::Event> task_event(num_cu);
  for (auto i = 0; i < num_cu; i++) {
    // must set before the first enqueue operation to obtain bank assignments
    int narg = 0;
    OCL_CHECK(err, err = krnl_rand_acc[i].setArg(narg++, buffer_in1));
    OCL_CHECK(err, err = krnl_rand_acc[i].setArg(narg++, buffer_in2));
    OCL_CHECK(err, err = krnl_rand_acc[i].setArg(narg++, buffer_out));
    OCL_CHECK(err, err = krnl_rand_acc[i].setArg(narg++, length));
  }

  OCL_CHECK(err, err = q.enqueueMigrateMemObjects({buffer_in1,buffer_in2}, 0));
  /*
  for (auto i = 0; i < num_cu; i++) {
    OCL_CHECK(err, err = q.enqueueMigrateMemObjects({idx_dev[i]}, 0));
  }
  */
  OCL_CHECK(err, err = q.finish());

  for (auto i = 0; i < num_cu; i++) {
    OCL_CHECK(err, err = q.enqueueTask(krnl_rand_acc[i], NULL, &task_event[i]));
  }
  OCL_CHECK(err, err = q.finish());

  for (auto i = 0; i < num_cu; i++) {
	  
    OCL_CHECK(err, err = q.enqueueMigrateMemObjects(
                       {buffer_out}, CL_MIGRATE_MEM_OBJECT_HOST));
					   
  }
  OCL_CHECK(err, err = q.finish());

/*
  bool match = true;
  for (auto i = 0; i < length; i++) {
	  
    if (out_host[i] != out_sim[i]) {
      std::cout << "ERROR : kernel failed; out_host[" << i
                << "] = " << out_host[i] << " ; but out_sim[" << i
                << "] = " << out_sim[i] << std::endl;
      match = false;
    }
  }
  */

  std::vector<cl_ulong> t_start(num_cu);
  std::vector<cl_ulong> t_end(num_cu);
  for (auto i = 0; i < num_cu; ++i) {
    OCL_CHECK(
        err,
        t_start[i] =
            task_event[i].getProfilingInfo<CL_PROFILING_COMMAND_START>(&err));
    OCL_CHECK(err, t_end[i] =
                       task_event[i].getProfilingInfo<CL_PROFILING_COMMAND_END>(
                           &err));
  }

  cl_ulong t_min_start = *std::min_element(t_start.begin(), t_start.end());
  cl_ulong t_max_end = *std::max_element(t_end.begin(), t_end.end());
  cl_ulong t_max_start = *std::max_element(t_start.begin(), t_start.end());
  cl_ulong t_min_end = *std::min_element(t_end.begin(), t_end.end());

  auto msec = [](ulong nsec) { return nsec / 1e6; };
  std::cout << "Union duration ... " << msec(t_max_end - t_min_start) << " ms"
            << std::endl;
  std::cout << "Intersect duration ... " << msec(t_min_end - t_max_start)
            << " ms" << std::endl;
  for (auto i = 0; i < num_cu; ++i) {
    std::cout << "Kernel[" << i << "] duration ... "
              << msec(t_end[i] - t_start[i]) << " ms" << std::endl;
  }
  
	//std::cout<<"OUT_TEST1="<<out[0]<<"2"<<out[1]<<std::endl;
 /*
  free(in_1);
  free(in_2);
  free(out_vec);
  */
  //free(out_host);
  //free(out_sim);

  //std::cout << "TEST " << (match ? "PASSED" : "FAILED") << std::endl;
  
  return EXIT_SUCCESS;
  //(match ? EXIT_SUCCESS : EXIT_FAILURE);
}
