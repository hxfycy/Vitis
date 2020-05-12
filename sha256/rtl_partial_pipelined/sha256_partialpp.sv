`default_nettype none
`timescale 1ps /1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: xfhu
// 
// Create Date: 2020/04/29 13:32:52
// Design Name: 
// Module Name: sha256_partial_pipelined for filecoin
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


module sha256#(
  parameter integer S_AXIS_TDATA_WIDTH=512, //input
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
  output wire							 m_axis_tlast,
  output wire							 done_onebatch //denotes 1024 point comp done
  );
  
    // constant define
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
	
	//input data fifo instantiation
	logic fifo_outvalid,fifo_outready;
	logic [255:0] fifo_outdata;
	logic [9:0] fifo_rdcnt,fifo_wrcnt;
	logic fifo_afull;

	//input flag data fifo instantiation
	logic flag_outvalid;
	logic flag_outready;
	logic [7:0] flag_out;
	logic [7:0] flag_wrcnt,flag_rdcnt;
	logic flag_afull;

	//fifo read signal control
	logic read_state; // read_state=0 -> read flag; read_state1-> read node;

   //input handshake and batch counter
	logic cnt_en6,cnt_en14,cnt_en1G;
	logic co_6,co_14,co_1G;
	logic [29:0] cnt1G;
	logic in_hd;												// valid input data handshake
	logic batch_init;										    // flag notifies another batch begins
	logic [3583:0] in_batch;									// input buffer of one batch
	logic message_valid;
	
	//input dumming    
    logic [255:0]node_id;
	logic [255:0]Rep_ID=Replica_ID;
	logic [9983:0]message_in;
	
    //padding instantiation 
    logic pad_outvalid;
    logic pad_inready,pad_outready;
    logic padding_sh;
	logic [10239:0] pad_out;
	logic pad_enable_d; 		//pad_enable signal delay 1 cycle for padding out ready
    logic pad_outvalid_d;       //delay padding out one cycle
	
	// flag and node delay buffer
	logic    [1:0]   flag_d1='0;  //flag data output delay 1 cycle
	logic    [255:0] node_d1='0;  //node data output delay 1 cycle
	logic    in_valid_d1,in_ready_d1;

	//padding output buffer
    logic [31:0] pad0_outbuf[0:19][0:63][0:1];
    logic [31:0] pad1_outbuf[0:19][0:63][0:1];
    logic [31:0] pad2_outbuf[0:19][0:63][0:1];
    logic [31:0] pad3_outbuf[0:19][0:63][0:1];
    logic [31:0] pad4_outbuf[0:19][0:63][0:1];
    logic [31:0] pad5_outbuf[0:19][0:63][0:1];
    logic [31:0] pad6_outbuf[0:19][0:63][0:1];
    logic [31:0] pad7_outbuf[0:19][0:63][0:1];
    logic [31:0] pad8_outbuf[0:19][0:63][0:1];
    logic [31:0] pad9_outbuf[0:19][0:63][0:1];
    logic [31:0] pada_outbuf[0:19][0:63][0:1];
    logic [31:0] padb_outbuf[0:19][0:63][0:1];
    logic [31:0] padc_outbuf[0:19][0:63][0:1];
    logic [31:0] padd_outbuf[0:19][0:63][0:1];
    logic [31:0] pade_outbuf[0:19][0:63][0:1];
    logic [31:0] padf_outbuf[0:19][0:63][0:1];
    logic [1:0] buffer_full=0;		//denote 64 depth input buffer is full
    logic [5:0] pad_ptr;        		  //padding output pointer
    logic [5:0] pad_ptr_d1=0;             //padding pointer delay 1 cycle;
    logic [5:0] w_ptr;                    //w_comp module data batch pointer
    logic [5:0] hash_ptr[0:15];	          //hash module data batch pointer		
	logic write_done;					  //one 64-batch buffer write done
	logic write_ptr=0;					  //pointer to current write buffer batch
	logic write_ptr_d1=0;                 //pointer delay 1 cycle
	logic comp_ptr[0:15];                 //pointer of current working buffer batch 
	logic pad_enable;					  //buffer not full, padding ready to get output
	
	//hash counter denotes current working batch
	logic [10:0] hash_cnt[0:63];       //one batch 64 input, 1280 computation
	logic [63:0] hash_en;	           //one batch computation finished
	logic comp_done;                   //computation done in current FIFO
	
	//w_comp module instantiation
	logic [63:16] w_invalid,w_inready,w_outready,w_outvalid;
	logic [31:0] Win [16:64][0:15];       // input of w_comp
	logic [31:0] Wout[16:64][0:15];       //output of w_comp
	
	//new hash digest buffer between two pipeline
    logic [5:0] ptr_hbuf ;           //pointer to hash buffer
    logic last_out;                  //denote last output
	logic [31:0] hash [0:7][64];     //hash buffer
	logic [4:0] hash_layer[64];//denotes current hash layer
	logic [10:0]hash_cnt_d1; //delay 1 cycle hash_counter;
	logic [4:0] hbuf_batch;	  //denote current hash output batch
	logic [4:0] hin_batch;     //denote current hash input batch
	
	// hash module driver begins here
	logic  [63:0] hash_invalid,hash_inready,hash_outvalid,hash_outready;
	logic  [31:0] a [0:63];
	logic  [31:0] b [0:63];
	logic  [31:0] c [0:63];
	logic  [31:0] d [0:63];
	logic  [31:0] e [0:63];
	logic  [31:0] f [0:63];
	logic  [31:0] g [0:63];
	logic  [31:0] h [0:63];
	logic  [31:0] a_out [0:63];
	logic  [31:0] b_out [0:63];
	logic  [31:0] c_out [0:63];
	logic  [31:0] d_out [0:63];
	logic  [31:0] e_out [0:63];
	logic  [31:0] f_out [0:63];
	logic  [31:0] g_out [0:63];
	logic  [31:0] h_out [0:63];
	logic  [31:0] W_inhash [0:63]; //w input from w_comp module
	
	//output driver
    logic outvalid=0;
    logic outvalid_d1=0;
    logic [5:0] ptr_hbuf_d1=0;
	logic last_out_d1=0;
    logic [9:0] out_validcnt; 
//**---------------------------------------------RTL begins here------------------------------------------**//	
	
	
  //input node data fifo
  axis_data_fifo_0 infifo(
  .s_axis_aresetn(s0_axis_aresetn),
  .s_axis_aclk(s0_axis_aclk),
  .s_axis_tvalid(s0_axis_tvalid),
  .s_axis_tready(s0_axis_tready),
  .s_axis_tdata(s0_axis_tdata[255:0]),
  .m_axis_aclk(m_axis_aclk),
  .m_axis_tvalid(fifo_outvalid),
  .m_axis_tready(fifo_outready),
  .m_axis_tdata(fifo_outdata),
  .axis_wr_data_count(fifo_wrcnt),
  .axis_rd_data_count(fifo_rdcnt),
  .almost_full(fifo_afull)
); 


  //input flag data synchronize 
    axis_data_fifo_1 flagfifo(
  .s_axis_aresetn(s1_axis_aresetn),
  .s_axis_aclk(s1_axis_aclk),
  .s_axis_tvalid(s1_axis_tvalid),
  .s_axis_tready(s1_axis_tready),
  .s_axis_tdata(s1_axis_tdata[7:0]),
  .m_axis_aclk(m_axis_aclk),
  .m_axis_tvalid(flag_outvalid),
  .m_axis_tready(flag_outready),
  .m_axis_tdata(flag_out),
  .axis_wr_data_count(flag_wrcnt),
  .axis_rd_data_count(flag_rdcnt),
  .almost_full(flag_afull)
); 

   /*------------------------------------------ output clock domain begins here -----------------------------------------*/
   
  //fifo read signal control
  assign fifo_outready=pad_enable&&(!write_done)&&read_state;
  assign flag_outready=pad_enable&&(!read_state);
  
  //read state drive
  always_ff@(posedge m_axis_aclk)begin
        if(!s0_axis_aresetn)begin
            read_state<=0;  
        end
        else begin
            case(read_state)
            1'b0: 
            begin 
                if(flag_outvalid&&flag_outready)
                read_state<=1'b1;
            end
            1'b1:
            begin
                if(co_14|co_6)
                read_state<=1'b0;
            end
            endcase
        end
  end
  
	//input data and flag buffer to padding 
    always_ff@(posedge m_axis_aclk)begin
            flag_d1<=flag_out[1:0];
            node_d1<=fifo_outdata[255:0];
            in_valid_d1<=fifo_outvalid;
            in_ready_d1<=fifo_outready;
    end
	
	//data counter enable driver
    assign in_hd=fifo_outvalid&&fifo_outready;			
	assign cnt_en6=!flag_out[1]&in_hd;						//flag=0,1,  6 input
	assign cnt_en14=flag_out[1]&in_hd;						//flag=2,3, 14 input
	assign cnt_en1G=(co_14|co_6);				            //flag=1,3, 1G length at total	
	assign batch_init=(flag_d1==flag_out[1:0]);				//changing flag denotes the beginning of another batch
    
    //message valid signal delays 1 cycle
	always_ff@(posedge m_axis_aclk)
	begin
	   message_valid<=co_14|co_6;
	   node_id<=cnt1G;
	end
	
	//data counter instantiation
    counterM #(6) cnt_6( .clk(m_axis_aclk),.rst_n(s0_axis_aresetn&&batch_init),.cnt_en(cnt_en6),.cntout(),.cout_en(co_6));
	counterM #(14) cnt_14( .clk(m_axis_aclk),.rst_n(s0_axis_aresetn&&batch_init),.cnt_en(cnt_en14),.cntout(),.cout_en(co_14));
	counterM #(1<<30) cnt_1G( .clk(m_axis_aclk),.rst_n(s0_axis_aresetn),.cnt_en(cnt_en1G),.cntout(cnt1G),.cout_en(co_1G));
	
	//input dumming drive
	always_ff@(posedge m_axis_aclk )
	begin 
		if(!s0_axis_aresetn)begin
		in_batch<=0;
		end
		else if(in_hd)begin
			in_batch<={in_batch[3327:0],fifo_outdata[255:0]};
		end
	end
    
  	//padding input= Replica_ID + node_ID + input_after_dumming;
	assign message_in=flag_d1[1]?{Rep_ID,node_id,in_batch,in_batch,in_batch[3583:1280]}   //2*14+9
	                            :{Rep_ID,node_id,in_batch[1535:0],in_batch[1535:0],in_batch[1535:0],
								in_batch[1535:0],in_batch[1535:0],in_batch[1535:0],in_batch[1535:1280]};  //6*6+1
    
	

    always_ff@(posedge m_axis_aclk)begin
        pad_enable_d<=pad_enable;
    end
    
    //padding output ready drive
    assign padding_sh=(message_valid&&pad_inready);
    assign pad_outready=pad_enable_d;

    
    //padding module instantiation
     padding  pad512(
			 .clk(m_axis_aclk),
			 .data_width(11'd1248), 		//width in byte
			 .in_valid(message_valid),	
			 .in_ready(pad_inready),
			 .message_in(message_in),
			 .out(pad_out),
			 .out_ready(pad_outready),
			 .out_valid(pad_outvalid)
		   );
		   
    //padding output buffer

	assign pad_enable=buffer_full!=2'b11; 
	
    //padding output buffer drive
    generate 
        for(genvar i=0;i<20;i=i+1'b1)begin
            //for(genvar j=0;j<16;j=j+1'b1)begin
                always_ff@(posedge m_axis_aclk)begin
                    if(pad_outvalid&&pad_outready)begin
                       // pad_outbuf[i][j][pad_ptr_d1][write_ptr_d1]<=pad_out[10239-i*512-j*32:10208-i*512-j*32];
                        pad0_outbuf[i][pad_ptr_d1][write_ptr_d1]<=pad_out[10239-i*512:10208-i*512];
                        pad1_outbuf[i][pad_ptr_d1][write_ptr_d1]<=pad_out[10207-i*512:10176-i*512];
                        pad2_outbuf[i][pad_ptr_d1][write_ptr_d1]<=pad_out[10175-i*512:10144-i*512];
                        pad3_outbuf[i][pad_ptr_d1][write_ptr_d1]<=pad_out[10143-i*512:10112-i*512];
                        pad4_outbuf[i][pad_ptr_d1][write_ptr_d1]<=pad_out[10111-i*512:10080-i*512];
                        pad5_outbuf[i][pad_ptr_d1][write_ptr_d1]<=pad_out[10079-i*512:10048-i*512];
                        pad6_outbuf[i][pad_ptr_d1][write_ptr_d1]<=pad_out[10047-i*512:10016-i*512];
                        pad7_outbuf[i][pad_ptr_d1][write_ptr_d1]<=pad_out[10015-i*512:9984-i*512];
                        pad8_outbuf[i][pad_ptr_d1][write_ptr_d1]<=pad_out[9983-i*512:9952-i*512];
                        pad9_outbuf[i][pad_ptr_d1][write_ptr_d1]<=pad_out[9951-i*512:9920-i*512];
                        pada_outbuf[i][pad_ptr_d1][write_ptr_d1]<=pad_out[9919-i*512:9888-i*512];
                        padb_outbuf[i][pad_ptr_d1][write_ptr_d1]<=pad_out[9887-i*512:9856-i*512];
                        padc_outbuf[i][pad_ptr_d1][write_ptr_d1]<=pad_out[9855-i*512:9824-i*512];
                        padd_outbuf[i][pad_ptr_d1][write_ptr_d1]<=pad_out[9823-i*512:9792-i*512];
                        pade_outbuf[i][pad_ptr_d1][write_ptr_d1]<=pad_out[9791-i*512:9760-i*512];
                        padf_outbuf[i][pad_ptr_d1][write_ptr_d1]<=pad_out[9759-i*512:9728-i*512];
                    end
                end
            //end
        end
    endgenerate
    
    //comp_ptr drive
    generate 
        for(genvar i=0;i<16;i=i+1'b1)begin
            always_ff@(posedge m_axis_aclk)begin
                if(!s0_axis_aresetn)begin
                    comp_ptr[i]<='0;
                end
                else begin
                    if(hash_en[i])
                        comp_ptr[i]<=~comp_ptr[i];
                end
            end
        end
    endgenerate
    
	//other pointer drive
	always_ff@(posedge m_axis_aclk) begin
    if(!s0_axis_aresetn)begin
        write_ptr<=2'b0;
        buffer_full<=2'b0;
        pad_ptr_d1<=6'b0;
    end
    else begin
        write_ptr_d1<=write_ptr;
        pad_ptr_d1<=pad_ptr;
            if(write_done) begin
                write_ptr<=~write_ptr;
                buffer_full[write_ptr]<=1'b1;
            end
            if(hash_en[15])begin
                  buffer_full[comp_ptr[15]]<=1'b0;
            end
    end
	end
	
    //buffer pointer drive
    counterM #(.cnt_mod(64)) cnt_pad( .clk(m_axis_aclk),.rst_n(s0_axis_aresetn),.cnt_en(padding_sh),.cntout(pad_ptr),.cout_en(write_done));
    counterM #(.cnt_mod(64)) cnt_w( .clk(m_axis_aclk),.rst_n(s0_axis_aresetn),.cnt_en(w_invalid[16]&&w_inready[16]),.cntout(w_ptr),.cout_en( ));
    
    for(genvar j=0;j<16;j=j+1'b1)begin
        counterM #(.cnt_mod(64)) cnt_hash( .clk(m_axis_aclk),.rst_n(s0_axis_aresetn),.cnt_en(hash_invalid[j]&&hash_inready[j]),.cntout(hash_ptr[j]),.cout_en());
    end
    
    //hash counter denotes current working batch

	assign comp_done=hash_en[0];       
	generate 
	   for(genvar i=0;i<64;i=i+1'b1)
           counterM#(1280) batch_cnt( .clk(m_axis_aclk),.rst_n(s0_axis_aresetn),.cnt_en(hash_invalid[i]&&hash_inready[i]),.cntout(hash_cnt[i]),.cout_en(hash_en[i]));
	endgenerate
	

    //w_comp module assignment
    assign w_invalid[16]=hash_invalid[15];
    assign w_invalid[63:17]=w_outvalid[62:16];
    assign w_outready=hash_inready[63:16];

    //w_comp input assignment
    assign Win[17:64]=Wout[16:63];
    always_comb begin
        Win[16][0]=pad0_outbuf[hash_cnt[15][10:6]][w_ptr][comp_ptr[15]];
        Win[16][1]=pad1_outbuf[hash_cnt[15][10:6]][w_ptr][comp_ptr[15]];
        Win[16][2]=pad2_outbuf[hash_cnt[15][10:6]][w_ptr][comp_ptr[15]];
        Win[16][3]=pad3_outbuf[hash_cnt[15][10:6]][w_ptr][comp_ptr[15]];
        Win[16][4]=pad4_outbuf[hash_cnt[15][10:6]][w_ptr][comp_ptr[15]];
        Win[16][5]=pad5_outbuf[hash_cnt[15][10:6]][w_ptr][comp_ptr[15]];
        Win[16][6]=pad6_outbuf[hash_cnt[15][10:6]][w_ptr][comp_ptr[15]];
        Win[16][7]=pad7_outbuf[hash_cnt[15][10:6]][w_ptr][comp_ptr[15]];
        Win[16][8]=pad8_outbuf[hash_cnt[15][10:6]][w_ptr][comp_ptr[15]];
        Win[16][9]=pad9_outbuf[hash_cnt[15][10:6]][w_ptr][comp_ptr[15]];
        Win[16][10]=pada_outbuf[hash_cnt[15][10:6]][w_ptr][comp_ptr[15]];
        Win[16][11]=padb_outbuf[hash_cnt[15][10:6]][w_ptr][comp_ptr[15]];
        Win[16][12]=padc_outbuf[hash_cnt[15][10:6]][w_ptr][comp_ptr[15]];
        Win[16][13]=padd_outbuf[hash_cnt[15][10:6]][w_ptr][comp_ptr[15]];
        Win[16][14]=pade_outbuf[hash_cnt[15][10:6]][w_ptr][comp_ptr[15]];
        Win[16][15]=padf_outbuf[hash_cnt[15][10:6]][w_ptr][comp_ptr[15]];
    end
    
    //w_comp instantiation
    generate
            for(genvar j=16;j<64;j=j+1'b1)	//w[i]=SSIG1(w[i-2])+w[i-7]+SSIG0(w[i-15])+w[i-16];
            w_comp _wcomp(.clk(m_axis_aclk),.in_valid(w_invalid[j]),.in_ready(w_inready[j]), .Win(Win[j]),
                        .Wout(Wout[j]),.out_ready(w_outready[j]),.out_valid(w_outvalid[j])// first w batch
                         );
    endgenerate



    always@(posedge m_axis_aclk)begin
       pad_outvalid_d<=pad_outvalid;
    end

    // hash buffer pointer driver
    counterM #(.cnt_mod(64)) cnt_hbuf( .clk(m_axis_aclk),.rst_n(s0_axis_aresetn),.cnt_en(hash_outvalid[63]&&hash_outready[63]),.cntout(ptr_hbuf),.cout_en());
    

	
	assign hin_batch= hash_cnt[0][10:6];
	assign hbuf_batch=hash_cnt_d1[10:6];
	
	always_ff@(posedge m_axis_aclk)begin
		hash_cnt_d1<=hash_cnt[63];
	end
	
    //hash buffer driver
	       always_ff@(posedge m_axis_aclk)begin
	           if(hash_outvalid[63]&&hash_outready[63])begin
	           hash[0][ptr_hbuf]<=(hbuf_batch==0)?a_out[63]+H_ini[0]:a_out[63]+hash[0][ptr_hbuf];
	           hash[1][ptr_hbuf]<=(hbuf_batch==0)?b_out[63]+H_ini[1]:b_out[63]+hash[1][ptr_hbuf];
	           hash[2][ptr_hbuf]<=(hbuf_batch==0)?c_out[63]+H_ini[2]:c_out[63]+hash[2][ptr_hbuf];
	           hash[3][ptr_hbuf]<=(hbuf_batch==0)?d_out[63]+H_ini[3]:d_out[63]+hash[3][ptr_hbuf];
	           hash[4][ptr_hbuf]<=(hbuf_batch==0)?e_out[63]+H_ini[4]:e_out[63]+hash[4][ptr_hbuf];
	           hash[5][ptr_hbuf]<=(hbuf_batch==0)?f_out[63]+H_ini[5]:f_out[63]+hash[5][ptr_hbuf];
	           hash[6][ptr_hbuf]<=(hbuf_batch==0)?g_out[63]+H_ini[6]:g_out[63]+hash[6][ptr_hbuf];
	           hash[7][ptr_hbuf]<=(hbuf_batch==0)?h_out[63]+H_ini[7]:h_out[63]+hash[7][ptr_hbuf];
	           end
	       end
	
    //hash module streaming data assignment
	always_comb begin
			 a[1:63]=a_out[0:62];
			 b[1:63]=b_out[0:62];
			 c[1:63]=c_out[0:62];
			 d[1:63]=d_out[0:62];
			 e[1:63]=e_out[0:62];
			 f[1:63]=f_out[0:62];
			 g[1:63]=g_out[0:62];
			 h[1:63]=h_out[0:62];
			
			if(hin_batch==0) begin
			 a[0]=H_ini[0];
			 b[0]=H_ini[1];
			 c[0]=H_ini[2];
			 d[0]=H_ini[3];
			 e[0]=H_ini[4];
			 f[0]=H_ini[5];
			 g[0]=H_ini[6];
			 h[0]=H_ini[7];
			end
			else if(hin_batch==1) begin
			 a[0]=H_ini[0]+a_out[63];
			 b[0]=H_ini[1]+b_out[63];
			 c[0]=H_ini[2]+c_out[63];
			 d[0]=H_ini[3]+d_out[63];
			 e[0]=H_ini[4]+e_out[63];
			 f[0]=H_ini[5]+f_out[63];
			 g[0]=H_ini[6]+g_out[63];
			 h[0]=H_ini[7]+h_out[63];
			end
			else begin
			 a[0]=a_out[63]+hash[0][ptr_hbuf];
			 b[0]=b_out[63]+hash[1][ptr_hbuf];
			 c[0]=c_out[63]+hash[2][ptr_hbuf];
			 d[0]=d_out[63]+hash[3][ptr_hbuf];
			 e[0]=e_out[63]+hash[4][ptr_hbuf];
			 f[0]=f_out[63]+hash[5][ptr_hbuf];
			 g[0]=g_out[63]+hash[6][ptr_hbuf];
			 h[0]=h_out[63]+hash[7][ptr_hbuf];  
			end
	end
	
	//logic [31:0] pad_outbuf[0:19][0:15][0:63][0:1];
	//assign hash_layer[i]=hash_cnt[i][10:6];
	//logic [31:0] pad_outbuf[0:19][0:15][0:63][0:1];

	always_comb begin   //first 16 module input from padding
        W_inhash[0]=pad0_outbuf[hash_layer[0]][hash_ptr[0]][comp_ptr[0]]; 
        W_inhash[1]=pad1_outbuf[hash_layer[1]][hash_ptr[1]][comp_ptr[1]]; 
        W_inhash[2]=pad2_outbuf[hash_layer[2]][hash_ptr[2]][comp_ptr[2]]; 
        W_inhash[3]=pad3_outbuf[hash_layer[3]][hash_ptr[3]][comp_ptr[3]]; 
        W_inhash[4]=pad4_outbuf[hash_layer[4]][hash_ptr[4]][comp_ptr[4]]; 
        W_inhash[5]=pad5_outbuf[hash_layer[5]][hash_ptr[5]][comp_ptr[5]]; 
        W_inhash[6]=pad6_outbuf[hash_layer[6]][hash_ptr[6]][comp_ptr[6]]; 
        W_inhash[7]=pad7_outbuf[hash_layer[7]][hash_ptr[7]][comp_ptr[7]]; 
        W_inhash[8]=pad8_outbuf[hash_layer[8]][hash_ptr[8]][comp_ptr[8]]; 
        W_inhash[9]=pad9_outbuf[hash_layer[9]][hash_ptr[9]][comp_ptr[9]]; 
        W_inhash[10]=pada_outbuf[hash_layer[10]][hash_ptr[10]][comp_ptr[10]]; 
        W_inhash[11]=padb_outbuf[hash_layer[11]][hash_ptr[11]][comp_ptr[11]]; 
        W_inhash[12]=padc_outbuf[hash_layer[12]][hash_ptr[12]][comp_ptr[12]]; 
        W_inhash[13]=padd_outbuf[hash_layer[13]][hash_ptr[13]][comp_ptr[13]]; 
        W_inhash[14]=pade_outbuf[hash_layer[14]][hash_ptr[14]][comp_ptr[14]]; 
        W_inhash[15]=padf_outbuf[hash_layer[15]][hash_ptr[15]][comp_ptr[15]]; 
    end
	
	
	generate 
		for(genvar i=0;i<16;i=i+1'b1)begin
			//assign W_inhash[i]=pad_outbuf[hash_layer[i]][i][hash_ptr[i]][comp_ptr[i]]; //first 16 module input from padding
			assign hash_layer[i]=hash_cnt[i][10:6];
		end	
		for (genvar j=16;j<64;j=j+1'b1)begin
			assign W_inhash[j]=Wout[j][15];//ensuing 48 input from W_comp module 
			assign hash_layer[j]=hash_cnt[j][10:6];
		end
	endgenerate
	
    //hash handshake assignment 
	always_comb begin
		hash_outready[62:0]=hash_inready[63:1];
		hash_outready[63]=m_axis_tready;
		hash_invalid[63:16]=hash_outvalid[62:15]&w_outvalid[63:16];
		hash_invalid[15:1]=hash_outvalid[14:0];
		hash_invalid[0]=hash_cnt[0][10:6]==0?buffer_full[comp_ptr[0]]:hash_outvalid[63];
	end
    
    //hash module instantiation
    generate 
        for(genvar j=0;j<64;j=j+1'b1)
            hash256 hash(.clk(m_axis_aclk),.in_valid(hash_invalid[j]),.in_ready(hash_inready[j]),.K(K[j]),.W(W_inhash[j]),
            .a(a[j]),.b(b[j]),.c(c[j]),.d(d[j]),.e(e[j]),.f(f[j]),.g(g[j]),.h(h[j]),
            .a_out(a_out[j]),.b_out(b_out[j]),.c_out(c_out[j]),.d_out(d_out[j]),.e_out(e_out[j]),.f_out(f_out[j]),.g_out(g_out[j]),.h_out(h_out[j]),
            .out_ready(hash_outready[j]), .out_valid(hash_outvalid[j]));
    endgenerate
    
      
    always_ff@(posedge m_axis_aclk)begin
        outvalid<=hash_outvalid[63]&&(hash_cnt[63][10:6]==19);
        outvalid_d1<=outvalid;
        last_out<=hash_en[63];
		last_out_d1<=last_out;
        ptr_hbuf_d1<=ptr_hbuf;
    end

	assign m_axis_tlast=last_out_d1;
    assign m_axis_tvalid=outvalid_d1;
    assign m_axis_tdata={hash[0][ptr_hbuf_d1],hash[1][ptr_hbuf_d1],hash[2][ptr_hbuf_d1],hash[3][ptr_hbuf_d1],
                         hash[4][ptr_hbuf_d1],hash[5][ptr_hbuf_d1],hash[6][ptr_hbuf_d1],hash[7][ptr_hbuf_d1]};
						 
	//1024 batch done signal
	counterM #(1024) cnt_batch( .clk(m_axis_aclk),.rst_n(s0_axis_aresetn),.cnt_en(m_axis_tvalid&&m_axis_tready),.cntout(out_validcnt),.cout_en(done_onebatch));
						 
						 
    
endmodule 