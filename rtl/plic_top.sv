

`define VER_RTL  32'h0000_1_000
`define NEXT_VER_RTL  32`h0000_1_001
`define EXT_INTRPT_TIMER 15


module plic_top #(
  parameter int N_SOURCE    = 30,
  parameter int N_TARGET    = 2,
  parameter int MAX_PRIO    = 7,
  parameter int SRCW        = $clog2(N_SOURCE+1)
) (
  input  logic clk_i,    // Clock
  input  logic rst_ni,  // Asynchronous reset active low
  // Bus Interface
  input  reg_intf::reg_intf_req_a32_d32 req_i,
  output reg_intf::reg_intf_resp_d32    resp_o,
  input logic [N_SOURCE-1:0] le_i, // 0:level 1:edge
  // Interrupt Sources
  input  logic [N_SOURCE-1:0] irq_sources_i,
  // Interrupt notification to targets
  output logic [N_TARGET-1:0] eip_targets_o
);
  localparam PRIOW = $clog2(MAX_PRIO+1);

  logic [N_SOURCE-1:0] ip;

  logic [N_TARGET-1:0][PRIOW-1:0]    threshold_q;

  logic [N_TARGET-1:0]               claim_re; //Target read indicator
  logic [N_TARGET-1:0][SRCW-1:0]     claim_id;
  logic [N_SOURCE-1:0]               claim; //Converted from claim_re/claim_id

  logic [N_TARGET-1:0]               complete_we; //Target write indicator
  logic [N_TARGET-1:0][SRCW-1:0]     complete_id;
  logic [N_SOURCE-1:0]               complete; //Converted from complete_re/complete_id

  logic [N_SOURCE-1:0][PRIOW-1:0]    prio_q;
  logic [N_TARGET-1:0][N_SOURCE-1:0] ie_q;



  logic	[31:0]	ext_intrpt_cnt;
  logic		ext_intrpt_edg;
  logic		ext_intrpt_lvl;
  logic		ext_intrpt_edg_lvl;

  logic		en, sel, edg, strt;

  logic		ext_intrpt_en;

   logic 	[31:0] tim_val_i;
   logic 	[31:0] tim_val_o;
   logic 	[31:0] tim_val_q;
   logic	tim_val_we_o;
   logic	tim_val_re_o;

   logic 	[31:0] ctrl_i;
   logic 	[31:0] ctrl_o;
   logic 	[31:0] ctrl_q;
   logic	ctrl_we_o;
   logic	ctrl_re_o;

   logic	ver_reg_re_o;

   logic 	[31:0] tim_stat_i;
   logic 	[31:0] tim_stat_o;
   logic 	[31:0] tim_stat_q;
   logic	tim_stat_we_o;
   logic	tim_stat_re_o;


    assign tim_val_i = tim_val_q;
    assign ctrl_i = ctrl_q;
    assign tim_stat_i = tim_stat_q;


  // registers
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (~rst_ni) begin
      tim_val_q <= '0;
      ctrl_q <= '0;
      tim_stat_q <= '0;
    end else begin
      // source zero is 0
        tim_val_q <= tim_val_we_o ? tim_val_o : tim_val_q;
        ctrl_q <= ctrl_we_o ? ctrl_o : ctrl_q;
        tim_stat_q <= tim_stat_we_o ? tim_stat_o : tim_stat_q;

    end
  end

always_comb begin
	 en 	= ctrl_q[0];
	 //sel 	= ctrl_o[1];
	 edg 	= ctrl_q[2];
	 strt 	= ctrl_q[3];
end


  always_comb begin
    claim = '0;
    complete = '0;
    for (int i = 0 ; i < N_TARGET ; i++) begin
      if (claim_re[i] && claim_id[i] != 0) claim[claim_id[i]-1] = 1'b1;
      if (complete_we[i] && complete_id[i] != 0) complete[complete_id[i]-1] = 1'b1;
    end
  end

  // Gateways
  rv_plic_gateway #(
    .N_SOURCE (N_SOURCE)
  ) i_rv_plic_gateway (
    .clk_i,
    .rst_ni,
    .src({irq_sources_i[N_SOURCE-1:`EXT_INTRPT_TIMER+1],ext_intrpt_en,irq_sources_i[`EXT_INTRPT_TIMER-1:0]}),
    .le(le_i),
    .claim(claim),
    .complete(complete),
    .ip(ip)
  );

  // Target interrupt notification
  for (genvar i = 0 ; i < N_TARGET; i++) begin : gen_target
    rv_plic_target #(
      .N_SOURCE  ( N_SOURCE ),
      .MAX_PRIO  ( MAX_PRIO ),
      .ALGORITHM ( "SEQUENTIAL" )
    ) i_target (
      .clk_i,
      .rst_ni,
      .ip(ip),
      .ie(ie_q[i]),
      .prio(prio_q),
      .threshold(threshold_q[i]),
      .irq(eip_targets_o[i]),
      .irq_id(claim_id[i])
    );
  end

  logic [N_TARGET-1:0] threshold_we_o;
  logic [N_TARGET-1:0][PRIOW-1:0] threshold_o;

  logic [N_SOURCE:0][PRIOW-1:0] prio_i, prio_o;
  logic [N_SOURCE:0] prio_we_o;

  // TODO(zarubaf): This needs more graceful handling
  // it will break if the number of sources is larger than 32
  logic [N_TARGET-1:0][N_SOURCE:0] ie_i, ie_o;
  logic [N_TARGET-1:0] ie_we_o;

  plic_regs i_plic_regs (
    .prio_i(prio_i),
    .prio_o(prio_o),
    .prio_we_o(prio_we_o),
    .prio_re_o(), // don't care
    // source zero is always zero
    .ip_i({ip, 1'b0}),
    .ip_re_o(), // don't care
    .ie_i(ie_i),
    .ie_o(ie_o),
    .ie_we_o(ie_we_o),
    .ie_re_o(), // don't care
    .threshold_i(threshold_q),
    .threshold_o(threshold_o),
    .threshold_we_o(threshold_we_o),
    .threshold_re_o(), // don't care
    .cc_i(claim_id),
    .cc_o(complete_id),
    .cc_we_o(complete_we),
    .cc_re_o(claim_re),

    .ctrl_i(ctrl_i),
    .ctrl_o(ctrl_o),
    .ctrl_we_o(ctrl_we_o),
    .ctrl_re_o(ctrl_re_o), // don't care
    .ver_reg_re_o(ver_reg_re_o),
    .tim_val_i(tim_val_i),
    .tim_val_o(tim_val_o),
    .tim_val_we_o(tim_val_we_o),
    .tim_val_re_o(tim_val_re_o), // don't care
    .tim_stat_i(tim_stat_i),
    .tim_stat_o(tim_stat_o),
    .tim_stat_we_o(tim_stat_we_o),
    .tim_stat_re_o(tim_stat_re_o),


    .req_i,
    .resp_o
  );

  assign prio_i[0] = '0;

  for (genvar i = 0; i < N_TARGET; i++) begin
    assign ie_i[i] = {ie_q[i][N_SOURCE-1:0], 1'b0};
  end

  for (genvar i = 1; i < N_SOURCE + 1; i++) begin
    assign prio_i[i] = prio_q[i - 1];
  end

  // registers
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (~rst_ni) begin
      prio_q <= '0;
      ie_q <= '0;
      threshold_q <= '0;
    end else begin
      // source zero is 0
      for (int i = 0; i < N_SOURCE; i++) begin
        prio_q[i] <= prio_we_o[i + 1] ? prio_o[i + 1] : prio_q[i];
      end
      for (int i = 0; i < N_TARGET; i++) begin
        threshold_q[i] <= threshold_we_o[i] ? threshold_o[i] : threshold_q[i];
        ie_q[i] <= ie_we_o[i] ? ie_o[i][N_SOURCE:1] : ie_q[i];
      end

    end
  end


// muxes , select the edge or level after it is enabled or not and
// than select value from switch

always @(posedge clk_i or negedge rst_ni)
 begin
	if (!rst_ni)
	 begin
		ext_intrpt_en		<= 1'b0;
		ext_intrpt_edg_lvl	<= 1'b0;
	 end
	else
	 begin
		//ext_intrpt_sel		<= sel	? ext_intrpt_en 		: 1'b1;
		// Yuri asked to cancel this option of switch
		// I didn't see yet where the switch is located
		//ext_intrpt_sel		<= sel	? ext_intrpt_en 		: ext_intrpt_switch;
		ext_intrpt_en 		<= en 	? ext_intrpt_edg_lvl 	: '0;
		ext_intrpt_edg_lvl 	<= edg 	? ext_intrpt_edg 		: ext_intrpt_lvl;
	 end
 end




always @(posedge clk_i or negedge rst_ni)
 begin
	if (!rst_ni)
	 begin
		ext_intrpt_cnt 		<= '0;
		ext_intrpt_edg		<= 1'b0;
		ext_intrpt_lvl		<= 1'b0;
	 end
	else
	  begin
		if (strt)
		  begin
			if (ext_intrpt_cnt == tim_val_q)
			  begin
				ext_intrpt_cnt 		<= '0;
				ext_intrpt_edg		<= 1'b1;
				ext_intrpt_lvl		<= 1'b1;
			  end
			else
			  begin
				ext_intrpt_cnt 		<= ext_intrpt_cnt+1;
				ext_intrpt_edg		<= 1'b0;
				ext_intrpt_lvl		<= ext_intrpt_lvl;
			  end
		  end
		else
		 begin
				ext_intrpt_cnt 		<= tim_val_o;
				ext_intrpt_lvl		<= 1'b0;
				ext_intrpt_edg		<= 1'b0;
		 end
       end
  end

endmodule
