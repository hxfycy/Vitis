`timescale 1ps/1ps
module testforsha;
logic clk,rst_n;
logic in_valid,in_ready,out_ready,out_valid,flag_ready;
logic [511:0]out_data;
logic [255:0]in_flag;

initial begin
    clk=1'b0;
    forever begin
    #5 clk=~clk;
    end
end

initial begin
        rst_n=1'b1;
        in_valid<='0;
    #10 rst_n=1'b0;
    #10 rst_n=1'b1;
        in_valid<=1'b1;
end

logic seed;
logic [255:0]cnt=0;

assign out_ready=1'b1;//out always ready
assign in_flag=256'b1;

always@(posedge clk)begin
	if(in_valid&&in_ready)
	begin
		cnt<=cnt+1'b1;
	end
end

sha256_rtl #(
  .S_AXIS_TDATA_WIDTH(256), //input
  .M_AXIS_TDATA_WIDTH(512),	//output
  .Replica_ID(256'b1)
  ) sha	
  (
   .s0_axis_aclk(clk),
  .s0_axis_aresetn(rst_n),
  .s0_axis_tvalid(in_valid),
  .s0_axis_tdata(cnt),
  .s0_axis_tready(in_ready),
  .s0_axis_tlast(),
  .s0_axis_tkeep(),
  
  //streaming slave port 1 for flag
  .s1_axis_aclk(clk),
  .s1_axis_aresetn(rst_n),
  .s1_axis_tvalid(in_valid),
  .s1_axis_tdata(in_flag),
  .s1_axis_tready(flag_ready),
  .s1_axis_tlast(),
  .s1_axis_tkeep(),
  
  //streaming master port
  .m_axis_aclk(clk),
  .m_axis_tready(out_ready),
  .m_axis_tvalid(out_valid),
  .m_axis_tdata(out_data),
  .m_axis_tkeep(),
  .m_axis_tlast()
  );

endmodule 