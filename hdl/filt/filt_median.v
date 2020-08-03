`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Dmitry Matyunin (https://github.com/mcjtag)
// 
// Create Date: 03.08.2020 23:14:18
// Design Name: 
// Module Name: filt_median
// Project Name: 
// Target Devices:
// Tool Versions:
// Description: Median Filter
// Dependencies: 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// License: MIT
//  Copyright (c) 2020 Dmitry Matyunin
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
// 
//////////////////////////////////////////////////////////////////////////////////

module filt_median #(
	parameter DATA_WIDTH = 8,	// Data Width
	parameter ORDER = 7,		// Filter Order
	parameter FORMAT = 0		// Number Format: 0 - unsigned, 1 - signed
)
(
	input wire aclk,
	input wire aresetn,
	input wire [DATA_WIDTH-1:0]s_axis_tdata,
	input wire s_axis_tvalid,
	output wire s_axis_tready,
	output wire [DATA_WIDTH-1:0]m_axis_tdata,
	output wire m_axis_tvalid,
	input wire m_axis_tready
);

reg [DATA_WIDTH*(ORDER-1)-1:0]shift;
wire [DATA_WIDTH*ORDER-1:0]data_out;

assign m_axis_tdata = data_out[DATA_WIDTH*ORDER/2-1-:DATA_WIDTH];

always @(posedge aclk) begin
	if (aresetn == 1'b0) begin
		shift <= 0;
	end else begin
		if (s_axis_tvalid & s_axis_tready) begin
			shift <= {shift[DATA_WIDTH*(ORDER-2)-1:0],s_axis_tdata};
		end
	end
end

sort_net #(
	.DATA_WIDTH(DATA_WIDTH),
	.CHAN_NUM(ORDER),
	.DIR(0),
	.SIGNED(FORMAT)
) sort_net_inst (
	.aclk(aclk),
	.aresetn(aresetn),
	.s_axis_tdata({shift,s_axis_tdata}),
	.s_axis_tvalid(s_axis_tvalid),
	.s_axis_tready(s_axis_tready),
	.m_axis_tdata(data_out),
	.m_axis_tvalid(m_axis_tvalid),
	.m_axis_tready(m_axis_tready)
);
	
endmodule

module sort_net #(
	parameter DATA_WIDTH = 16,
	parameter CHAN_NUM = 32,
	parameter DIR = 0,
	parameter SIGNED = 0
)
(
	input wire aclk,
	input wire aresetn,
	input wire [DATA_WIDTH*CHAN_NUM-1:0]s_axis_tdata,
	input wire s_axis_tvalid,
	output wire s_axis_tready,
	output wire [DATA_WIDTH*CHAN_NUM-1:0]m_axis_tdata,
	output wire m_axis_tvalid,
	input wire m_axis_tready
);

localparam CHAN_ACT = 2**$clog2(CHAN_NUM);
localparam CHAN_ADD = CHAN_ACT - CHAN_NUM;

localparam STAGES = $clog2(CHAN_ACT);
localparam STAGE_DATA_WIDTH = DATA_WIDTH*CHAN_ACT;

wire [STAGE_DATA_WIDTH-1:0]axis_stage_tdata[STAGES:0];
wire [STAGE_DATA_WIDTH-1:0]m_axis_tdata_tmp;
wire [STAGES:0]axis_stage_tvalid;
wire [STAGES:0]axis_stage_tready;

assign axis_stage_tdata[0] = {s_axis_tdata, {CHAN_ADD{SIGNED?{1'b1,{(DATA_WIDTH-1){1'b0}}}:{DATA_WIDTH{1'b0}}}}};
assign axis_stage_tvalid[0] = s_axis_tvalid;
assign s_axis_tready = axis_stage_tready[0];
assign m_axis_tdata_tmp = axis_stage_tdata[STAGES];
assign m_axis_tdata = DIR ? m_axis_tdata_tmp[DATA_WIDTH*CHAN_NUM-1:0] : m_axis_tdata_tmp[DATA_WIDTH*CHAN_ACT-1-:DATA_WIDTH*CHAN_NUM];
assign m_axis_tvalid = axis_stage_tvalid[STAGES];
assign axis_stage_tready[STAGES] = m_axis_tready;

genvar stage;
genvar block;

generate for (stage = 0; stage < STAGES; stage = stage + 1) begin: SORT_STAGE
	localparam BLOCKS = CHAN_ACT / 2**(stage+1);
	localparam BLOCK_ORDER = stage;
		
	wire [STAGE_DATA_WIDTH-1:0]s_axis_stage_tdata;
	wire s_axis_stage_tvalid;
	wire s_axis_stage_tready;
	wire [STAGE_DATA_WIDTH-1:0]m_axis_stage_tdata;
	wire m_axis_stage_tvalid;
	wire m_axis_stage_tready;
		
	assign s_axis_stage_tdata = axis_stage_tdata[stage];
	assign s_axis_stage_tvalid = axis_stage_tvalid[stage];
	assign axis_stage_tready[stage] = s_axis_stage_tready;
	assign axis_stage_tdata[stage + 1] = m_axis_stage_tdata;
	assign m_axis_stage_tready = axis_stage_tready[stage + 1];
	assign axis_stage_tvalid[stage + 1] = m_axis_stage_tvalid;

	for (block = 0; block < BLOCKS; block = block + 1) begin: BLOCK
		localparam BLOCK_DATA_WIDTH = DATA_WIDTH*2**(BLOCK_ORDER+1);
		localparam BLOCK_POLARITY = DIR ? (~block & 1) : (block & 1);
			
		wire [BLOCK_DATA_WIDTH-1:0]s_axis_block_tdata;
		wire [BLOCK_DATA_WIDTH-1:0]m_axis_block_tdata;
			
		assign s_axis_block_tdata = s_axis_stage_tdata[BLOCK_DATA_WIDTH*(block+1)-1-:BLOCK_DATA_WIDTH];
		assign m_axis_stage_tdata[BLOCK_DATA_WIDTH*(block+1)-1-:BLOCK_DATA_WIDTH] = m_axis_block_tdata;
		
		if (block == 0) begin
			sort_net_block #(
				.DATA_WIDTH(DATA_WIDTH),
				.ORDER(BLOCK_ORDER),
				.POLARITY(BLOCK_POLARITY),
				.SIGNED(SIGNED)
			) snb_inst (
				.aclk(aclk),
				.aresetn(aresetn),
				.s_axis_tdata(s_axis_block_tdata),
				.s_axis_tvalid(s_axis_stage_tvalid),
				.s_axis_tready(s_axis_stage_tready),
				.m_axis_tdata(m_axis_block_tdata),
				.m_axis_tvalid(m_axis_stage_tvalid),
				.m_axis_tready(m_axis_stage_tready)
			);
		end else begin
			sort_net_block #(
				.DATA_WIDTH(DATA_WIDTH),
				.ORDER(BLOCK_ORDER),
				.POLARITY(BLOCK_POLARITY),
				.SIGNED(SIGNED)
			) snb_inst (
				.aclk(aclk),
				.aresetn(aresetn),
				.s_axis_tdata(s_axis_block_tdata),
				.s_axis_tvalid(s_axis_stage_tvalid),
				.s_axis_tready(),
				.m_axis_tdata(m_axis_block_tdata),
				.m_axis_tvalid(),
				.m_axis_tready(m_axis_stage_tready)
			);
		end
	end
end endgenerate

endmodule

module sort_net_block #(
	parameter DATA_WIDTH = 16,
	parameter ORDER = 0,
	parameter POLARITY = 0,
	parameter SIGNED = 0
)
(
	input wire aclk,
	input wire aresetn,
	input wire [DATA_WIDTH*2**(ORDER+1)-1:0]s_axis_tdata,
	input wire s_axis_tvalid,
	output wire s_axis_tready,
	output wire [DATA_WIDTH*2**(ORDER+1)-1:0]m_axis_tdata,
	output wire m_axis_tvalid,
	input wire m_axis_tready
);

localparam STAGES = ORDER + 1;
localparam STAGE_DATA_WIDTH = DATA_WIDTH*2**(ORDER+1);

wire [DATA_WIDTH*2**(ORDER+1)-1:0]axis_stage_tdata[STAGES:0];
wire [STAGES:0]axis_stage_tvalid;
wire [STAGES:0]axis_stage_tready;

assign axis_stage_tdata[0] = s_axis_tdata;
assign axis_stage_tvalid[0] = s_axis_tvalid;
assign s_axis_tready = axis_stage_tready[0];
assign m_axis_tdata = axis_stage_tdata[STAGES];
assign m_axis_tvalid = axis_stage_tvalid[STAGES];
assign axis_stage_tready[STAGES] = m_axis_tready;

genvar stage;
genvar node;

generate for (stage = 0; stage < STAGES; stage = stage + 1) begin: BLOCK_STAGE
	localparam NODES = 2**stage;
	localparam NODE_ORDER = STAGES - stage - 1;
		
	wire [STAGE_DATA_WIDTH-1:0]s_axis_stage_tdata;
	wire s_axis_stage_tvalid;
	wire s_axis_stage_tready;
	wire [STAGE_DATA_WIDTH-1:0]m_axis_stage_tdata;
	wire m_axis_stage_tvalid;
	wire m_axis_stage_tready;
		
	assign s_axis_stage_tdata = axis_stage_tdata[stage];
	assign s_axis_stage_tvalid = axis_stage_tvalid[stage];
	assign axis_stage_tready[stage] = s_axis_stage_tready;
	assign axis_stage_tdata[stage + 1] = m_axis_stage_tdata;
	assign m_axis_stage_tready = axis_stage_tready[stage + 1];
	assign axis_stage_tvalid[stage + 1] = m_axis_stage_tvalid;
		
	for (node = 0; node < NODES; node = node + 1) begin: NODE
		localparam NODE_DATA_WIDTH = DATA_WIDTH*2**(NODE_ORDER+1);
		
		wire [NODE_DATA_WIDTH-1:0]s_axis_node_tdata;
		wire [NODE_DATA_WIDTH-1:0]m_axis_node_tdata;
			
		assign s_axis_node_tdata = s_axis_stage_tdata[NODE_DATA_WIDTH*(node + 1)-1-:NODE_DATA_WIDTH];
		assign m_axis_stage_tdata[NODE_DATA_WIDTH*(node + 1)-1-:NODE_DATA_WIDTH] = m_axis_node_tdata;
		
		if (node == 0) begin
			sort_net_node #(
				.DATA_WIDTH(DATA_WIDTH),
				.ORDER(NODE_ORDER),
				.POLARITY(POLARITY),
				.SIGNED(SIGNED)
			) snn_inst (
				.aclk(aclk),
				.aresetn(aresetn),
				.s_axis_tdata(s_axis_node_tdata),
				.s_axis_tvalid(s_axis_stage_tvalid),
				.s_axis_tready(s_axis_stage_tready),
				.m_axis_tdata(m_axis_node_tdata),
				.m_axis_tvalid(m_axis_stage_tvalid),
				.m_axis_tready(m_axis_stage_tready)
			);
		end else begin
			sort_net_node #(
				.DATA_WIDTH(DATA_WIDTH),
				.ORDER(NODE_ORDER),
				.POLARITY(POLARITY),
				.SIGNED(SIGNED)
			) snn_inst (
				.aclk(aclk),
				.aresetn(aresetn),
				.s_axis_tdata(s_axis_node_tdata),
				.s_axis_tvalid(s_axis_stage_tvalid),
				.s_axis_tready(),
				.m_axis_tdata(m_axis_node_tdata),
				.m_axis_tvalid(),
				.m_axis_tready(m_axis_stage_tready)
			);
		end
	end
end endgenerate

endmodule

module sort_net_node #(
	parameter DATA_WIDTH = 16,
	parameter ORDER = 0,
	parameter POLARITY = 0,
	parameter SIGNED = 0
)
(
	input wire aclk,
	input wire aresetn,
	input wire [DATA_WIDTH*2**(ORDER+1)-1:0]s_axis_tdata,
	input wire s_axis_tvalid,
	output wire s_axis_tready,
	output wire [DATA_WIDTH*2**(ORDER+1)-1:0]m_axis_tdata,
	output wire m_axis_tvalid,
	input wire m_axis_tready
);

localparam COMP_NUM = 2**ORDER;

genvar i;

generate for (i = 0; i < COMP_NUM; i = i + 1) begin: COMP
	wire [DATA_WIDTH-1:0]a;
	wire [DATA_WIDTH-1:0]b;
	wire [DATA_WIDTH-1:0]h;
	wire [DATA_WIDTH-1:0]l;
	
	assign a = s_axis_tdata[DATA_WIDTH*(i + 1 + COMP_NUM * 0)-1-:DATA_WIDTH];
	assign b = s_axis_tdata[DATA_WIDTH*(i + 1 + COMP_NUM * 1)-1-:DATA_WIDTH];
	assign m_axis_tdata[DATA_WIDTH*(i + 1 + COMP_NUM * 0)-1-:DATA_WIDTH] = h;
	assign m_axis_tdata[DATA_WIDTH*(i + 1 + COMP_NUM * 1)-1-:DATA_WIDTH] = l;

	if (i == 0) begin
		sort_net_comp #(
			.DATA_WIDTH(DATA_WIDTH),
			.POLARITY(POLARITY),
			.SIGNED(SIGNED)
		) snc_inst (
			.aclk(aclk),
			.aresetn(aresetn),
			.s_axis_tdata({b,a}),
			.s_axis_tvalid(s_axis_tvalid),
			.s_axis_tready(s_axis_tready),
			.m_axis_tdata({h,l}),
			.m_axis_tvalid(m_axis_tvalid),
			.m_axis_tready(m_axis_tready)
		);
	end else begin
		sort_net_comp #(
			.DATA_WIDTH(DATA_WIDTH),
			.POLARITY(POLARITY),
			.SIGNED(SIGNED)
		) snc_inst (
			.aclk(aclk),
			.aresetn(aresetn),
			.s_axis_tdata({b,a}),
			.s_axis_tvalid(s_axis_tvalid),
			.s_axis_tready(),
			.m_axis_tdata({h,l}),
			.m_axis_tvalid(),
			.m_axis_tready(m_axis_tready)
		);
	end
end endgenerate

endmodule

module sort_net_comp #(
	parameter DATA_WIDTH = 16,
	parameter POLARITY = 0,
	parameter SIGNED = 0
)
(
	input wire aclk,
	input wire aresetn,
	input wire [DATA_WIDTH*2-1:0]s_axis_tdata,
	input wire s_axis_tvalid,
	output wire s_axis_tready,
	output wire [DATA_WIDTH*2-1:0]m_axis_tdata,
	output wire m_axis_tvalid,
	input wire m_axis_tready
);

wire [DATA_WIDTH-1:0]a;
wire [DATA_WIDTH-1:0]b;
reg [DATA_WIDTH-1:0]h;
reg [DATA_WIDTH-1:0]l;
reg cmp_done;
wire valid_i;
wire valid_o;
wire less;

assign valid_i = s_axis_tvalid & s_axis_tready;
assign valid_o = m_axis_tvalid & m_axis_tready;
assign s_axis_tready = (cmp_done ? m_axis_tready : 1'b1) & aresetn;
assign m_axis_tvalid = cmp_done & aresetn;
assign m_axis_tdata = {h,l};

assign a = s_axis_tdata[DATA_WIDTH*1-1-:DATA_WIDTH];
assign b = s_axis_tdata[DATA_WIDTH*2-1-:DATA_WIDTH];
assign less = (SIGNED == 0) ? ($unsigned(a) < $unsigned(b)) : $signed(a) < $signed(b);

always @(posedge aclk) begin
	if (aresetn == 1'b0) begin
		h <= 0;
		l <= 0;
	end else begin
		if (valid_i == 1'b1) begin
			if (POLARITY == 0) begin
				h <= (less) ? a : b;
				l <= (less) ? b : a;
			end else begin
				h <= (less) ? b : a;
				l <= (less) ? a : b;
			end
		end
	end
end

always @(posedge aclk) begin
	if (aresetn == 1'b0) begin
		cmp_done <= 1'b0;
	end else begin
		case ({valid_i,valid_o})
		2'b01: cmp_done <= 1'b0;
		2'b10: cmp_done <= 1'b1;
		default: cmp_done <= cmp_done;
		endcase
	end
end	

endmodule