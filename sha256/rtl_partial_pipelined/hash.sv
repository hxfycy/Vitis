`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer:  xfhu
// 
// Create Date: 04/23/2020 05:49:13 PM
// Design Name: 
// Module Name: hash computation module for filecoin
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module w_comp(
	input wire clk,
	input wire  in_valid,						//input w[0]~w[15]
	output wire in_ready,
	input wire [31:0] Win[0:15],					
	//input wire [31:0] W14,W9,W1,W0, 			// w[i]=SSIG1(w[i-2])+w[i-7]+SSIG0(w[i-15])+w[i-16];
	//input wire  [31:0] W_fbatch [0:15],		// first w batch
	output reg [31:0] Wout[0:15], 					//output W for hash256
	input wire  out_ready,
	output wire out_valid
);
	reg Wout_valid=0;
	wire [31:0] Wtemp;
	wire in_hs;            //input handshake
	wire out_hs;           //output handshake
	assign in_hs=in_ready&&in_valid;
    assign out_hs=out_ready&&out_valid;
    
	//function definition
	function automatic [31:0] RightRot;
		input [31:0] In;
		input [4:0] movbit;
			RightRot=(In>>movbit)|(In<<(32-movbit));
	endfunction
	
	function automatic [31:0]SSIG0;
		input [31:0] In;
			SSIG0=RightRot(In,7)^RightRot(In,18)^(In>>3);
	endfunction
	
	function automatic [31:0]SSIG1;
		input [31:0] In;
			SSIG1=RightRot(In,17)^RightRot(In,19)^(In>>10);
	endfunction
	
	assign Wtemp=SSIG1(Win[14])+Win[9]+SSIG0(Win[1])+Win[0];
	always@(posedge clk)
	begin
		if(in_hs)
		begin
			Wout[0:15]<={Win[1:15],Wtemp};
			//Wout<=SSIG1(W14)+W9+SSIG0(W1)+W0;
			Wout_valid<=1'b1;
		end
		else if(!in_hs&&out_hs)
		Wout_valid<=1'b0;
	end
	
	//handshake drive
	assign in_ready=out_ready;
	assign out_valid=Wout_valid;
	
endmodule 


module hash256
	(
	input wire clk,
	//input bundle
	input wire in_valid,
	output wire in_ready,
	input wire [31:0] K,W,
	input wire [31:0] a,b,c,d,e,f,g,h,
	//output bundle
	output reg [31:0] a_out,b_out,c_out,d_out,e_out,f_out,g_out,h_out,
	input wire out_ready,
	output reg out_valid
	);
	
	//function definition
	function automatic [31:0] RightRot;
		input [31:0] In;
		input [4:0] movbit;
			RightRot=(In>>movbit)|(In<<(32-movbit));
	endfunction
	
	function automatic [31:0]CH;
		input [31:0]x,y,z;
		CH=(x&y)^(~x&z);
	endfunction
	
	function automatic [31:0]MAJ;
		input [31:0]x,y,z;
		MAJ=(x&y)^(x&z)^(y&z);
	endfunction
	
	function automatic [31:0] EP0;
		input [31:0]x;
		EP0=RightRot(x,2)^RightRot(x,13)^RightRot(x,22);
	endfunction
	
	function automatic [31:0]EP1;
		input [31:0]x;
		EP1=RightRot(x,6)^RightRot(x,11)^RightRot(x,25);
	endfunction
	
	wire [31:0]temp1,temp2;
	assign temp1=h+EP1(e)+CH(e,f,g)+K+W;
	assign temp2=EP0(a)+MAJ(a,b,c);
	assign in_ready=out_ready;
	wire in_hs,out_hs;
	assign in_hs=in_valid&&in_ready;
	assign out_hs=out_valid&&out_ready;
	
	always@(posedge clk)begin
		if(in_hs)begin
		a_out<=temp1+temp2;
		b_out<=a;
		c_out<=b;
		d_out<=c;
		e_out<=d+temp1;
		f_out<=e;
		g_out<=f;
		h_out<=g;
		out_valid<=1'b1;
		end
		else if(out_hs&&!in_hs)
		out_valid<=1'b0;
//		else 
//		out_valid<=1'b0;
	end
endmodule 


module counterM #(parameter cnt_mod=10)
	(
	input wire clk,
	input wire rst_n,
	input wire cnt_en,
	output reg [$clog2(cnt_mod)-1:0]cntout,
	output wire cout_en
	);
	assign cout_en=cnt_en&&(cntout==cnt_mod-1'b1);
	always@(posedge clk)
	begin
		if(!rst_n)
		cntout<=0;
		else if(cnt_en)begin
                if(cntout==cnt_mod-1'b1) begin
                 cntout<=0;
                end
                else cntout<=cntout+1'b1;
		end
	end
endmodule

module padding 
  (
  input clk,
  
  //input bundle
  input wire [10:0] data_width, //width in byte,32*39=1248 bytes at max
  input wire in_valid,
  output wire in_ready,
  input wire [9983:0] message_in,
  
  //output bundle
  //output wire [31:0] W [0:7] [0:15],
  output wire [10239:0] out,
  input wire out_ready,
  output reg out_valid
  );
  wire [63:0] DATA_WIDTH=data_width<<3;
  wire [5:0] node_cnt=data_width>>5;
  reg [10239:0] out_temp=0;
  assign out=out_temp;
  assign in_ready=out_ready;
	

  always@(posedge clk) begin
  if(in_valid&&in_ready)begin
    out_temp<={message_in,1'b1,191'b0,DATA_WIDTH};
    out_valid<=1'b1;
    end
  else if(out_valid&&out_ready)
    out_valid<=1'b0;
  end
//	case (node_cnt)
//		4'd2:begin //ID computation
//		  if(in_ready&&in_valid) begin
//		  out_temp[9727:0]<={message_in,1'b1,191'b0,DATA_WIDTH};
//		  end
//		end
//		4'd6:begin //first layer computation
//		  if(in_ready&&in_valid) begin
//		  out_temp[2047:0]<=2048'b0;
//		  out_temp[4095:2048]<={message_in[1535:0],1'b1,447'b0,DATA_WIDTH};
//		  end
//		end
//		4'd14:begin //other layer
//		  if(in_ready&&in_valid) begin
//		  out_temp<={message_in,1'b1,447'b0,DATA_WIDTH};
//		  end
//		end
//		default:out_temp<=0;
//	endcase
 endmodule 