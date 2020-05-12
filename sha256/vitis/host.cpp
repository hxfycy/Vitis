#include "xcl2.hpp"
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
  std::vector<cl::Kernel> sha256_master(num_cu);
  //std::vector<cl::Kernel> ke_test(num_cu);

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

    if (err != CL_SUCCESS) {
      std::cout << "Failed to program device[" << i << "] with xclbin file!\n";
    } else {
      std::cout << "Device[" << i << "]: program successful!\n";
      for (int i = 0; i < num_cu; i++) {
        OCL_CHECK(err,
                  sha256_master[i] = cl::Kernel(program, "sha256_master", &err));
				  /*
        OCL_CHECK(err,
                  ke_test[i]  = cl::Kernel(program, "ke_test", &err));
				  */
      }
      valid_device++;
      break; // we break because we found a valid device
    }
  }
  if (valid_device == 0) {
    std::cout << "Failed to program any device found, exit!\n";
    exit(EXIT_FAILURE);
  }

  unsigned length = 32 * 1024 / 4; /* in Dword */
  /* Reduce the data length for emulation mode */
  if (xcl::is_emulation()) {
    length = 1024; /* 4 KB */
  }
  unsigned data_size = length * sizeof(unsigned);
  
  unsigned *out_sim = (unsigned *)aligned_alloc(4096, data_size);
  unsigned *out_host1 = (unsigned *)aligned_alloc(4096, data_size);
  unsigned *out_host2 = (unsigned *)aligned_alloc(4096, data_size);
  unsigned *out_host3 = (unsigned *)aligned_alloc(4096, data_size);
  unsigned *out_host4 = (unsigned *)aligned_alloc(4096, data_size);
  unsigned *in_host1 = (unsigned *)aligned_alloc(4096, data_size);
  unsigned *in_host2 = (unsigned *)aligned_alloc(4096, data_size);

  for (auto i = 0; i < length; i++) {
    in_host1[i] = (unsigned)(i);
    in_host2[i] = (unsigned)(i);
  }

  srand(0);
  for (auto i = 0; i < length; i++) {
    out_sim[i] = in_host1[i];
  }

  unsigned chunk_size = data_size / num_cu;
  unsigned chunk_length = length / num_cu;
  cl::Buffer in_dev1;
  cl::Buffer in_dev2;
  cl::Buffer out_dev1;
  cl::Buffer out_dev2;
  cl::Buffer out_dev3;
  cl::Buffer out_dev4;

  OCL_CHECK(err,
            in_dev1 = cl::Buffer(context, CL_MEM_USE_HOST_PTR | CL_MEM_READ_ONLY,
                                data_size, in_host1, &err));
  OCL_CHECK(err,
            in_dev2 = cl::Buffer(context, CL_MEM_USE_HOST_PTR | CL_MEM_READ_ONLY,
                                data_size, in_host2, &err));
  OCL_CHECK(err, 
            out_dev1 = cl::Buffer(context, CL_MEM_USE_HOST_PTR | CL_MEM_WRITE_ONLY,
                                data_size, out_host1, &err));
  OCL_CHECK(err, 
            out_dev2 = cl::Buffer(context, CL_MEM_USE_HOST_PTR | CL_MEM_WRITE_ONLY,
                                data_size, out_host2, &err));
  OCL_CHECK(err, 
            out_dev3 = cl::Buffer(context, CL_MEM_USE_HOST_PTR | CL_MEM_WRITE_ONLY,
                                data_size, out_host3, &err));
  OCL_CHECK(err, 
            out_dev4 = cl::Buffer(context, CL_MEM_USE_HOST_PTR | CL_MEM_WRITE_ONLY,
                                data_size, out_host4, &err));
								

  std::vector<cl::Event> task_event(num_cu);
  std::vector<cl::Event> task_event2(num_cu);
  for (auto i = 0; i < num_cu; i++) {
    // must set before the first enqueue operation to obtain bank assignments
    int narg = 0;
    OCL_CHECK(err, err = ke_writenode[i].setArg(0, 768*1024*1024)); //start_idx
    OCL_CHECK(err, err = ke_writenode[i].setArg(1, 1024)); //step
    OCL_CHECK(err, err = ke_writenode[i].setArg(2, 0)); //rsv don't care
    OCL_CHECK(err, err = ke_writenode[i].setArg(3, out_dev1)); //
    OCL_CHECK(err, err = ke_writenode[i].setArg(4, out_dev2));
    OCL_CHECK(err, err = ke_writenode[i].setArg(5, out_dev3));
    OCL_CHECK(err, err = ke_writenode[i].setArg(6, out_dev4));
    OCL_CHECK(err, err = ke_test[i].setArg(0, 0)); //rsv don't care
    OCL_CHECK(err, err = ke_test[i].setArg(1, 0)); //rsv don't care
  }

  OCL_CHECK(err, err = q.finish());

  for (auto i = 0; i < num_cu; i++) {
    OCL_CHECK(err, err = q.enqueueTask(ke_writenode[i], NULL, &task_event2[i]));
    OCL_CHECK(err, err = q.enqueueTask(ke_test[i], NULL, &task_event[i]));
  }
  OCL_CHECK(err, err = q.finish());

  OCL_CHECK(err, err = q.enqueueMigrateMemObjects({out_dev1}, CL_MIGRATE_MEM_OBJECT_HOST));
  OCL_CHECK(err, err = q.enqueueMigrateMemObjects({out_dev2}, CL_MIGRATE_MEM_OBJECT_HOST));
  OCL_CHECK(err, err = q.enqueueMigrateMemObjects({out_dev3}, CL_MIGRATE_MEM_OBJECT_HOST));
  OCL_CHECK(err, err = q.enqueueMigrateMemObjects({out_dev4}, CL_MIGRATE_MEM_OBJECT_HOST));

  OCL_CHECK(err, err = q.finish());

  bool match = true;
  for (auto i = 0; i < length; i++) { //length
  //  if (out_host2[i] != out_sim[i]) {
      std::cout << "ERROR : kernel failed; out_host1[" << i
                << "] = " << out_host1[i] << " ; out_host2[" << i
                << "] = " << out_host2[i] << " ; out_host3[" << i
                << "] = " << out_host3[i] << " ; out_host4[" << i
                << "] = " << out_host4[i] << " ; but out_sim[" << i
                << "] = " << out_sim[i] << std::endl;
      match = false;
  //  }
  }

  std::vector<cl_ulong> t_start(num_cu);
  std::vector<cl_ulong> t_end(num_cu);
  for (auto i = 0; i < num_cu; ++i) {
    OCL_CHECK(err, t_start[i] =
                       task_event[i].getProfilingInfo<CL_PROFILING_COMMAND_START>(&err));
    OCL_CHECK(err, t_end[i] =
                       task_event2[i].getProfilingInfo<CL_PROFILING_COMMAND_END>(&err));
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

  free(in_host1);
  free(in_host2);
  free(out_host1);
  free(out_host2);
  free(out_host3);
  free(out_host4);
  free(out_sim);

  std::cout << "TEST " << (match ? "PASSED" : "FAILED") << std::endl;
  return (match ? EXIT_SUCCESS : EXIT_FAILURE);
}