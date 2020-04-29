`default_nettype none
`timescale 1ps /1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer:  xfhu
// 
// Create Date: 2020/04/25 10:55:12
// Design Name: 
// Module Name: sha256_rtl for rilecoin
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

module sha256_rtl #(
  parameter integer S_AXIS_TDATA_WIDTH=256, //input
  parameter integer M_AXIS_TDATA_WIDTH=512,	//output
  parameter Replica_ID=256'b1
  )	
  (
  //streaming slave port 0 for node
  input wire 							 s0_axis_aclk,
  input wire							 s0_axis_aresetn,
  input wire 							 s0_axis_tvalid,
  input wire [S_AXIS_TDATA_WIDTH-1:0]	 s0_axis_tdata,
  output wire							 s0_axis_tready,
  input wire							 s0_axis_tlast,
  input wire [S_AXIS_TDATA_WIDTH/8-1:0]	 s0_axis_tkeep,
  
  //streaming slave port 1 for flag
  input wire 							 s1_axis_aclk,
  input wire							 s1_axis_aresetn,
  input wire 							 s1_axis_tvalid,
  input wire [S_AXIS_TDATA_WIDTH-1:0]	 s1_axis_tdata,
  output wire							 s1_axis_tready,
  input wire							 s1_axis_tlast,
  input wire [S_AXIS_TDATA_WIDTH/8-1:0]	 s1_axis_tkeep,
  
  //streaming master port
  input wire							 m_axis_aclk,
  input wire							 m_axis_tready,
  output wire 							 m_axis_tvalid,
  output wire [M_AXIS_TDATA_WIDTH-1:0]	 m_axis_tdata,
  output wire [M_AXIS_TDATA_WIDTH/8-1:0] m_axis_tkeep,
  output wire							 m_axis_tlast
  );
  

	wire [31:0]  K[0:63]=
	{
	32'h428a2f98,32'h71374491,32'hb5c0fbcf,32'he9b5dba5,32'h3956c25b,32'h59f111f1,
	32'h923f82a4,32'hab1c5ed5,32'hd807aa98,32'h12835b01,32'h243185be,32'h550c7dc3,
	32'h72be5d74,32'h80deb1fe,32'h9bdc06a7,32'hc19bf174,32'he49b69c1,32'hefbe4786,
	32'h0fc19dc6,32'h240ca1cc,32'h2de92c6f,32'h4a7484aa,32'h5cb0a9dc,32'h76f988da,
	32'h983e5152,32'ha831c66d,32'hb00327c8,32'hbf597fc7,32'hc6e00bf3,32'hd5a79147,
	32'h06ca6351,32'h14292967,32'h27b70a85,32'h2e1b2138,32'h4d2c6dfc,32'h53380d13,
	32'h650a7354,32'h766a0abb,32'h81c2c92e,32'h92722c85,32'ha2bfe8a1,32'ha81a664b,
	32'hc24b8b70,32'hc76c51a3,32'hd192e819,32'hd6990624,32'hf40e3585,32'h106aa070,
	32'h19a4c116,32'h1e376c08,32'h2748774c,32'h34b0bcb5,32'h391c0cb3,32'h4ed8aa4a,
	32'h5b9cca4f,32'h682e6ff3,32'h748f82ee,32'h78a5636f,32'h84c87814,32'h8cc70208,
	32'h90befffa,32'ha4506ceb,32'hbef9a3f7,32'hc67178f2
	};
	
	wire [31:0] H_ini[0:7]={
	32'h6a09e667,32'hbb67ae85,32'h3c6ef372,32'ha54ff53a,32'h510e527f,32'h9b05688c,32'h1f83d9ab,32'h5be0cd19
	};
	
	// input buffer
	reg                              m_tvalid = 0;
	reg   [S_AXIS_TDATA_WIDTH-1:0]   m_tdata=0;
	reg                              m_tready=0;
	reg                              f_tvalid = 0;
	reg   [S_AXIS_TDATA_WIDTH-1:0]   f_tdata='0;
	
	//output delay signal
    reg outvalid;
    
    //input handshake and batch counter
	wire cnt_en6,cnt_en14,cnt_en1G;
	wire co_6,co_14,co_1G;
	wire [29:0] cnt1G;
	wire in_hd;												// valid input handshake
	wire batch_init;										// flag notifies another batch begins
	reg [3583:0] in_batch;									// input buffer of one batch
	wire message_valid;
	
	//input dumming
    wire [255:0]node_id=cnt1G;
	wire [255:0]Rep_ID=Replica_ID;
	wire [9983:0]message_in;
	
    //padding instantiation 
    wire pad_outvalid;
    wire pad_inready,pad_outready;
    wire padding_sh;
	wire [10239:0] pad_out;
	
    // fifo to buffer padding output
    reg [31:0] w0_padbuf[0:19][1232]; //64*19+16 level buffer
	reg [31:0] w1_padbuf[0:19][1232]; //64*19+16 level buffer
	reg [31:0] w2_padbuf[0:19][1232]; //64*19+16 level buffer
	reg [31:0] w3_padbuf[0:19][1232]; //64*19+16 level buffer
	reg [31:0] w4_padbuf[0:19][1232]; //64*19+16 level buffer
	reg [31:0] w5_padbuf[0:19][1232]; //64*19+16 level buffer
	reg [31:0] w6_padbuf[0:19][1232]; //64*19+16 level buffer
	reg [31:0] w7_padbuf[0:19][1232]; //64*19+16 level buffer
	reg [31:0] w8_padbuf[0:19][1232]; //64*19+16 level buffer
	reg [31:0] w9_padbuf[0:19][1232]; //64*19+16 level buffer
    reg [31:0] wa_padbuf[0:19][1232]; //64*19+16 level buffer
    reg [31:0] wb_padbuf[0:19][1232]; //64*19+16 level buffer
    reg [31:0] wc_padbuf[0:19][1232]; //64*19+16 level buffer
    reg [31:0] wd_padbuf[0:19][1232]; //64*19+16 level buffer
    reg [31:0] we_padbuf[0:19][1232]; //64*19+16 level buffer
    reg [31:0] wf_padbuf[0:19][1232]; //64*19+16 level buffer
    
    //pointer to current input
	wire [10:0] pad_ptr[0:19];        //padding output pointer
	wire [10:0] w_ptr[0:19];          //w_comp  input pointer
	wire [10:0] hash_ptr[0:19][0:15]; //hash input pointer
	
    //w_comp module instantiation
	wire [63:16] w_invalid[0:19];
	wire [63:16] w_inready[0:19];
	wire [63:16] w_outready[0:19];
	wire [63:16] w_outvalid[0:19];
	wire [31:0] Win [0:19][16:64][0:15];       // input of w_comp
	wire [31:0] Wout[0:19][16:64][0:15];       //output of w_comp
	
    // hash module driver begins here
	wire  [63:0] hash_invalid[0:19];
	wire  [63:0] hash_inready[0:19];
	wire  [63:0] hash_outvalid[0:19];
	wire  [63:0] hash_outready[0:19];
	wire  [31:0] a [0:19][0:63];
	wire  [31:0] b [0:19][0:63];
	wire  [31:0] c [0:19][0:63];
	wire  [31:0] d [0:19][0:63];
	wire  [31:0] e [0:19][0:63];
	wire  [31:0] f [0:19][0:63];
	wire  [31:0] g [0:19][0:63];
	wire  [31:0] h [0:19][0:63];
	wire  [31:0] a_out [0:19][0:63];
	wire  [31:0] b_out [0:19][0:63];
	wire  [31:0] c_out [0:19][0:63];
	wire  [31:0] d_out [0:19][0:63];
	wire  [31:0] e_out [0:19][0:63];
	wire  [31:0] f_out [0:19][0:63];
	wire  [31:0] g_out [0:19][0:63];
	wire  [31:0] h_out [0:19][0:63];
	wire  [31:0] W_inhash[0:19][0:63]; //w input from w_comp module
	
    //new hash digest buffer between two pipeline
    wire [5:0] ptr_hbuf[0:19];           //pointer to hash buffer
	reg [31:0] hash[0:7][0:19][64];      //hash buffer
	
    //delay padding out one cycle
    reg pad_outvalid_d; 
    // buffer streaming input
    always@(posedge s0_axis_aclk) begin
		m_tvalid<=s0_axis_tvalid;
		m_tdata<=s0_axis_tdata;
		m_tready<=s0_axis_tready;
    end
	
	always@(posedge s1_axis_aclk)begin
		if(s1_axis_tvalid&&s1_axis_tready)
		f_tdata<=s1_axis_tdata;
	end
	

	assign in_hd=m_tvalid&&m_tready;			
	assign cnt_en6=!f_tdata[1]&in_hd;						//flag=0,1,  6 input
	assign cnt_en14=co_6|co_14;						        //flag=2,3, 14 input
	assign cnt_en1G=(co_14|co_6);				            //flag=1,3, 1G length at total	
	assign batch_init=f_tdata==s1_axis_tdata;				//changing flag denotes the beginning of one batch
	assign message_valid=co_14|co_6;                        //padding module input signal
	
	counterM #(6) cnt_6( .clk(s0_axis_aclk),.rst_n(batch_init&s0_axis_aresetn&padding_sh),.cnt_en(cnt_en6),.cntout(),.cout_en(co_6));
	counterM #(14) cnt_14( .clk(s0_axis_aclk),.rst_n(batch_init&s0_axis_aresetn&padding_sh),.cnt_en(cnt_en14),.cntout(),.cout_en(co_14));
	counterM #(1<<30) cnt_1G( .clk(s0_axis_aclk),.rst_n(s0_axis_aresetn),.cnt_en(cnt_en1G),.cntout(cnt1G),.cout_en(co_1G));

	//input handshake and buffer to padding
	always@(posedge s0_axis_aclk or negedge s0_axis_aresetn or negedge batch_init)
	begin 
		if(!s0_axis_aresetn|!batch_init)begin
		in_batch<=0;
		end
		else if(in_hd)begin
			in_batch<={in_batch[3327:0],m_tdata};
		end
	end
	
	//padding input= Replica_ID + node_ID + input_after_dumming;
	assign node_id=cnt1G;
	assign message_in=f_tdata[1]?{Rep_ID,node_id,in_batch,in_batch,in_batch[3583:1280]}   //2*14+9
	                            :{Rep_ID,node_id,in_batch[1535:0],in_batch[1535:0],in_batch[1535:0],
								in_batch[1535:0],in_batch[1535:0],in_batch[1535:0],in_batch[1535:1280]};  //6*6+1


    assign padding_sh=!(message_valid&&pad_inready);
    assign pad_outready=hash_inready[0][0];
    assign s0_axis_tready=pad_inready;
    assign s1_axis_tready=pad_inready;
    
    //padding module instantiation
  padding  pad512(
			 .clk(s0_axis_aclk),
			 .data_width(11'd1248), 		//width in byte
			 .in_valid(message_valid),	
			 .in_ready(pad_inready),
			 .message_in(message_in),
			 .out(pad_out),
			 .out_ready(pad_outready),
			 .out_valid(pad_outvalid)
		   );

	//fifo pointer driver
	generate 
		for(genvar i=0;i<20;i=i+1'b1)begin
			counterM #(.cnt_mod(1232)) cnt_pad( .clk(s0_axis_aclk),.rst_n(s0_axis_aresetn),.cnt_en(pad_outvalid&&pad_outready),.cntout(pad_ptr[i]),.cout_en( ));
			counterM #(.cnt_mod(1232)) cnt_w( .clk(s0_axis_aclk),.rst_n(s0_axis_aresetn),.cnt_en(w_invalid[i][16]&&w_inready[i][16]),.cntout(w_ptr[i]),.cout_en( ));
			for(genvar j=0;j<16;j=j+1'b1)begin
			counterM #(.cnt_mod(1232)) cnt_hash( .clk(s0_axis_aclk),.rst_n(s0_axis_aresetn),.cnt_en(hash_outvalid[i][j]&&hash_outready[i][j]),.cntout(hash_ptr[i][j]),.cout_en());
			end
		end
	endgenerate
	
	//padding output buffer in fifo
	generate
	   //for(genvar i=0;i<16;i=i+1'b1)begin
			   for(genvar j=0;j<20;j=j+1'b1)
				   begin
					   always@(posedge s0_axis_aclk or negedge s0_axis_aresetn)begin
						   if(!s0_axis_aresetn)begin
						       w0_padbuf[j][0]<=0;
							   w1_padbuf[j][0]<=0;
							   w2_padbuf[j][0]<=0;
							   w3_padbuf[j][0]<=0;
							   w4_padbuf[j][0]<=0;
							   w5_padbuf[j][0]<=0;
							   w6_padbuf[j][0]<=0;
							   w7_padbuf[j][0]<=0;
							   w8_padbuf[j][0]<=0;
							   w9_padbuf[j][0]<=0;
							   wa_padbuf[j][0]<=0;
							   wb_padbuf[j][0]<=0;
							   wc_padbuf[j][0]<=0;
							   wd_padbuf[j][0]<=0;
							   we_padbuf[j][0]<=0;
							   wf_padbuf[j][0]<=0;
						   end
						   else begin
								if(pad_outvalid&&pad_outready)begin
//									w_padbuf[i][j][pad_ptr[i]]<=pad_out[10239-j*512-i*32:10240-j*512-(i+1)*32];
                                    w0_padbuf[j][pad_ptr[j]]<=pad_out[10239-j*512:10208-j*512];
                                    w1_padbuf[j][pad_ptr[j]]<=pad_out[10207-j*512:10176-j*512];
                                    w2_padbuf[j][pad_ptr[j]]<=pad_out[10175-j*512:10144-j*512];
                                    w3_padbuf[j][pad_ptr[j]]<=pad_out[10143-j*512:10122-j*512];
                                    w4_padbuf[j][pad_ptr[j]]<=pad_out[10111-j*512:10080-j*512];
                                    w5_padbuf[j][pad_ptr[j]]<=pad_out[10079-j*512:10048-j*512];
                                    w6_padbuf[j][pad_ptr[j]]<=pad_out[10047-j*512:10016-j*512];
                                    w7_padbuf[j][pad_ptr[j]]<=pad_out[10015-j*512:9984-j*512];
                                    w8_padbuf[j][pad_ptr[j]]<=pad_out[9983-j*512:9952-j*512];
                                    w9_padbuf[j][pad_ptr[j]]<=pad_out[9951-j*512:9920-j*512];
                                    wa_padbuf[j][pad_ptr[j]]<=pad_out[9919-j*512:9888-j*512];
                                    wb_padbuf[j][pad_ptr[j]]<=pad_out[9887-j*512:9856-j*512];
                                    wc_padbuf[j][pad_ptr[j]]<=pad_out[9855-j*512:9824-j*512];
                                    wd_padbuf[j][pad_ptr[j]]<=pad_out[9823-j*512:9792-j*512];
                                    we_padbuf[j][pad_ptr[j]]<=pad_out[9791-j*512:9760-j*512];
                                    wf_padbuf[j][pad_ptr[j]]<=pad_out[9759-j*512:9728-j*512];
								end
						   end
					   end
				   end
	endgenerate
	

	//w input assignment
	generate 
		for(genvar i=0;i<20;i=i+1'b1)begin
			assign Win[i][17:64]=Wout[i][16:63];
			assign Win[i][16][0]=w0_padbuf[i][w_ptr[i]];
			assign Win[i][16][1]=w1_padbuf[i][w_ptr[i]];
			assign Win[i][16][2]=w2_padbuf[i][w_ptr[i]];
			assign Win[i][16][3]=w3_padbuf[i][w_ptr[i]];
			assign Win[i][16][4]=w4_padbuf[i][w_ptr[i]];
			assign Win[i][16][5]=w5_padbuf[i][w_ptr[i]];
			assign Win[i][16][6]=w6_padbuf[i][w_ptr[i]];
			assign Win[i][16][7]=w7_padbuf[i][w_ptr[i]];
			assign Win[i][16][8]=w8_padbuf[i][w_ptr[i]];
			assign Win[i][16][9]=w9_padbuf[i][w_ptr[i]];
			assign Win[i][16][10]=wa_padbuf[i][w_ptr[i]];
			assign Win[i][16][11]=wb_padbuf[i][w_ptr[i]];
			assign Win[i][16][12]=wc_padbuf[i][w_ptr[i]];
			assign Win[i][16][13]=wd_padbuf[i][w_ptr[i]];
			assign Win[i][16][14]=we_padbuf[i][w_ptr[i]];
			assign Win[i][16][15]=wf_padbuf[i][w_ptr[i]];
			end
	endgenerate
	
	//w_input handshake assignment
	generate
		for(genvar i=0;i<20;i=i+1'b1)begin
			assign w_invalid[i][16]=hash_invalid[i][15];
			assign w_invalid[i][63:17]=w_outvalid[i][62:16];
			assign w_outready[i]=hash_inready[i][63:16];
		end
	endgenerate
	
    //w_comp instantiation
    generate
    for(genvar i=0;i<20;i=i+1'b1)
        for(genvar j=16;j<64;j=j+1'b1)	//w[i]=SSIG1(w[i-2])+w[i-7]+SSIG0(w[i-15])+w[i-16];
        w_comp _wcomp(.clk(s0_axis_aclk),.in_valid(w_invalid[i][j]),.in_ready(w_inready[i][j]), .Win(Win[i][j]),
                    //.W14(W_in[i][j-2]),.W9(W_in[i][j-7]),.W1(W_in[i][j-15]),.W0(W_in[i][j-16]),
                    .Wout(Wout[i][j]),.out_ready(w_outready[i][j]),.out_valid(w_outvalid[i][j])// first w batch
                     );
    endgenerate
	

                           
        always@(posedge s0_axis_aclk)begin
           pad_outvalid_d<=pad_outvalid;
        end
        
	// hash buffer pointer driver
	generate 
	   for(genvar i=0;i<20;i=i+1'b1)begin
	       counterM #(.cnt_mod(64)) cnt_hbuf( .clk(s0_axis_aclk),.rst_n(s0_axis_aresetn),.cnt_en(hash_outvalid[i][63]&&hash_outready[i][63]),.cntout(ptr_hbuf[i]),.cout_en( ));
	   end
	endgenerate
	
	//hash module streaming data assignment
	generate 
		for(genvar i=0;i<20;i=i+1'b1)begin
			assign a[i][1:63]=a_out[i][0:62];
			assign b[i][1:63]=b_out[i][0:62];
			assign c[i][1:63]=c_out[i][0:62];
			assign d[i][1:63]=d_out[i][0:62];
			assign e[i][1:63]=e_out[i][0:62];
			assign f[i][1:63]=f_out[i][0:62];
			assign g[i][1:63]=g_out[i][0:62];
			assign h[i][1:63]=h_out[i][0:62];
			if(i==0)begin
                assign a[i][0]=H_ini[0];
                assign b[i][0]=H_ini[1];
                assign c[i][0]=H_ini[2];
                assign d[i][0]=H_ini[3];
                assign e[i][0]=H_ini[4];
                assign f[i][0]=H_ini[5];
                assign g[i][0]=H_ini[6];
                assign h[i][0]=H_ini[7];
			end
			else if(i==1) begin
                assign a[i][0]=H_ini[0]+a_out[i-1][63];
                assign b[i][0]=H_ini[1]+b_out[i-1][63];
                assign c[i][0]=H_ini[2]+c_out[i-1][63];
                assign d[i][0]=H_ini[3]+d_out[i-1][63];
                assign e[i][0]=H_ini[4]+e_out[i-1][63];
                assign f[i][0]=H_ini[5]+f_out[i-1][63];
                assign g[i][0]=H_ini[6]+g_out[i-1][63];
                assign h[i][0]=H_ini[7]+h_out[i-1][63];
			end
			else begin
                assign a[i][0]=a_out[i-1][63]+hash[0][i-2][ptr_hbuf[i-1]];
                assign b[i][0]=b_out[i-1][63]+hash[1][i-2][ptr_hbuf[i-1]];
                assign c[i][0]=c_out[i-1][63]+hash[2][i-2][ptr_hbuf[i-1]];
                assign d[i][0]=d_out[i-1][63]+hash[3][i-2][ptr_hbuf[i-1]];
                assign e[i][0]=e_out[i-1][63]+hash[4][i-2][ptr_hbuf[i-1]];
                assign f[i][0]=f_out[i-1][63]+hash[5][i-2][ptr_hbuf[i-1]];
                assign g[i][0]=g_out[i-1][63]+hash[6][i-2][ptr_hbuf[i-1]];
                assign h[i][0]=h_out[i-1][63]+hash[7][i-2][ptr_hbuf[i-1]];  
			end
			end
	endgenerate
	
	generate 
	for(genvar i=0;i<20;i=i+1'b1)begin
	
	    //first 16 module input from padding
		assign W_inhash[i][0]=w0_padbuf[i][hash_ptr[i][0]];
		assign W_inhash[i][1]=w1_padbuf[i][hash_ptr[i][1]];
		assign W_inhash[i][2]=w2_padbuf[i][hash_ptr[i][2]];
		assign W_inhash[i][3]=w3_padbuf[i][hash_ptr[i][3]];
		assign W_inhash[i][4]=w4_padbuf[i][hash_ptr[i][4]];
		assign W_inhash[i][5]=w5_padbuf[i][hash_ptr[i][5]];
		assign W_inhash[i][6]=w6_padbuf[i][hash_ptr[i][6]];
		assign W_inhash[i][7]=w7_padbuf[i][hash_ptr[i][7]];
		assign W_inhash[i][8]=w8_padbuf[i][hash_ptr[i][8]];
		assign W_inhash[i][9]=w9_padbuf[i][hash_ptr[i][9]];
		assign W_inhash[i][10]=wa_padbuf[i][hash_ptr[i][10]];
		assign W_inhash[i][11]=wb_padbuf[i][hash_ptr[i][11]];
		assign W_inhash[i][12]=wc_padbuf[i][hash_ptr[i][12]];
		assign W_inhash[i][13]=wd_padbuf[i][hash_ptr[i][13]];
		assign W_inhash[i][14]=we_padbuf[i][hash_ptr[i][14]];
		assign W_inhash[i][15]=wf_padbuf[i][hash_ptr[i][15]];
		
		//ensuing 48 input from W_comp module 
			for (genvar j=16;j<64;j=j+1'b1)
			     assign W_inhash[i][j]=Wout[i][j][15];   
			             
    end
	endgenerate
    
    //hash handshake assignment 
	generate 
		for (genvar i=0;i<20;i=i+1'b1)begin
		assign hash_outready[i][62:0]=hash_inready[i][63:1];
		assign hash_outready[i][63]=i==19?m_axis_tready:hash_inready[i+1][0];
		assign hash_invalid[i][63:16]=hash_outvalid[i][62:15]&w_outvalid[i][63:16];
		assign hash_invalid[i][15:1]=hash_outvalid[i][14:0];
		assign hash_invalid[i][0]=i==0?pad_outvalid_d:hash_outvalid[i-1][63];
		end
	endgenerate

	//hash buffer driver
	generate 
	   for(genvar i=0;i<20;i=i+1'b1)begin
	       always@(posedge s0_axis_aclk)begin
	           if(hash_outvalid[i][63]&&hash_outready[i][63])begin
	           hash[0][i][ptr_hbuf[i]]<=(i==0)?a_out[i][63]+H_ini[0]:a_out[i][63]+hash[0][i-1][ptr_hbuf[i]];
	           hash[1][i][ptr_hbuf[i]]<=(i==0)?b_out[i][63]+H_ini[1]:b_out[i][63]+hash[1][i-1][ptr_hbuf[i]];
	           hash[2][i][ptr_hbuf[i]]<=(i==0)?c_out[i][63]+H_ini[2]:c_out[i][63]+hash[2][i-1][ptr_hbuf[i]];
	           hash[3][i][ptr_hbuf[i]]<=(i==0)?d_out[i][63]+H_ini[3]:d_out[i][63]+hash[3][i-1][ptr_hbuf[i]];
	           hash[4][i][ptr_hbuf[i]]<=(i==0)?e_out[i][63]+H_ini[4]:e_out[i][63]+hash[4][i-1][ptr_hbuf[i]];
	           hash[5][i][ptr_hbuf[i]]<=(i==0)?f_out[i][63]+H_ini[5]:f_out[i][63]+hash[5][i-1][ptr_hbuf[i]];
	           hash[6][i][ptr_hbuf[i]]<=(i==0)?g_out[i][63]+H_ini[6]:g_out[i][63]+hash[6][i-1][ptr_hbuf[i]];
	           hash[7][i][ptr_hbuf[i]]<=(i==0)?h_out[i][63]+H_ini[7]:h_out[i][63]+hash[7][i-1][ptr_hbuf[i]];
	           end
	       end
	   end
	endgenerate
	
	//hash module instantiation
    generate 
    for(genvar i=0;i<20;i=i+1'b1)
        for(genvar j=0;j<64;j=j+1'b1)
            hash256 hash(.clk(s0_axis_aclk),.in_valid(hash_invalid[i][j]),.in_ready(hash_inready[i][j]),.K(K[j]),.W(W_inhash[i][j]),
            .a(a[i][j]),.b(b[i][j]),.c(c[i][j]),.d(d[i][j]),.e(e[i][j]),.f(f[i][j]),.g(g[i][j]),.h(h[i][j]),
            .a_out(a_out[i][j]),.b_out(b_out[i][j]),.c_out(c_out[i][j]),.d_out(d_out[i][j]),.e_out(e_out[i][j]),.f_out(f_out[i][j]),.g_out(g_out[i][j]),.h_out(h_out[i][j]),
            .out_ready(hash_outready[i][j]), .out_valid(hash_outvalid[i][j]));
    endgenerate
    
    //output assignment
    always@(posedge s0_axis_aclk)begin
        outvalid<=hash_outvalid[19][63];
    end
    assign m_axis_tvalid=outvalid;
    assign m_axis_tdata={hash[0][19][ptr_hbuf[19]-1],hash[1][19][ptr_hbuf[19]-1],hash[2][19][ptr_hbuf[19]-1],hash[3][19][ptr_hbuf[19]-1],
                         hash[4][19][ptr_hbuf[19]-1],hash[5][19][ptr_hbuf[19]-1],hash[6][19][ptr_hbuf[19]-1],hash[7][19][ptr_hbuf[19]-1]};
    
endmodule 


