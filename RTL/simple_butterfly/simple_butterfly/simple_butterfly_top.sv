`include "register_interface/typedef.svh"
`include "register_interface/assign.svh"

module simple_butterfly_top #(
    parameter int unsigned AXI_ADDR_WIDTH = 32,
    localparam int unsigned AXI_DATA_WIDTH = 32,
    parameter int unsigned AXI_ID_WIDTH = -1,
    parameter int unsigned AXI_USER_WIDTH = -1
)(
    input  logic                clk_i,
    input  logic                rst_ni,
    input  logic                test_mode_i,
    AXI_BUS.Slave               axi_slave
);
    import simple_butterfly_reg_pkg::simple_butterfly_reg2hw_t;
    import simple_butterfly_reg_pkg::simple_butterfly_hw2reg_t;

    REG_BUS #(.ADDR_WIDTH(32), .DATA_WIDTH(32)) axi_to_regfile();

    simple_butterfly_reg2hw_t reg_file_to_ip;
    simple_butterfly_hw2reg_t ip_to_reg_file;

    axi_to_reg_intf #(
        .ADDR_WIDTH(AXI_ADDR_WIDTH), .DATA_WIDTH(AXI_DATA_WIDTH),
        .ID_WIDTH(AXI_ID_WIDTH), .USER_WIDTH(AXI_USER_WIDTH), .DECOUPLE_W(0)
    ) i_axi2reg (
        .clk_i(clk_i), .rst_ni(rst_ni), .testmode_i(test_mode_i),
        .in(axi_slave), .reg_o(axi_to_regfile)
    );

    typedef logic [AXI_ADDR_WIDTH-1:0]   addr_t;
    typedef logic [AXI_DATA_WIDTH-1:0]   data_t;
    typedef logic [AXI_DATA_WIDTH/8-1:0] strb_t;

    `REG_BUS_TYPEDEF_REQ(reg_req_t, addr_t, data_t, strb_t)
    `REG_BUS_TYPEDEF_RSP(reg_rsp_t, data_t)

    reg_req_t to_reg_file_req;
    reg_rsp_t from_reg_file_rsp;

    `REG_BUS_ASSIGN_TO_REQ(to_reg_file_req, axi_to_regfile)
    `REG_BUS_ASSIGN_FROM_RSP(axi_to_regfile, from_reg_file_rsp)

    // Updated instance name to match your file: simple_butterfly_reg_top
    simple_butterfly_reg_top #(
        .reg_req_t(reg_req_t), .reg_rsp_t(reg_rsp_t)
    ) i_regfile (
        .clk_i, .rst_ni, .devmode_i(1'b1),
        .reg_req_i(to_reg_file_req), .reg_rsp_o(from_reg_file_rsp),
        .reg2hw(reg_file_to_ip), .hw2reg(ip_to_reg_file)
    );

    // --- Instantiate the Butterfly Accelerator ---
    wire signed [23:0] w_o_left;
    wire signed [23:0] w_o_right;
    wire               w_o_aux;

    simple_butterfly #(
        .IWIDTH(12), .CWIDTH(16), .OWIDTH(12), .SHIFT(0) 
    ) i_butterfly (
        .i_clk          (clk_i),
        .i_reset        (~rst_ni),
        .i_clk_enable   (1'b1),
        
        // Flattened names: removed .idx and .val
        .i_twiddle_idx  (reg_file_to_ip.twiddle.q),
        .i_left         (reg_file_to_ip.op_left.q),
        .i_right        (reg_file_to_ip.op_right.q),
        
        // Trigger pulse on writing OP_RIGHT
        .i_aux          (reg_file_to_ip.op_right.qe),
        
        .o_left         (w_o_left),
        .o_right        (w_o_right),
        .o_aux          (w_o_aux)
    );

    // --- Output Mapping ---
    
    // Status Register: Clears on trigger (qe), Sets on finish (w_o_aux)
    assign ip_to_reg_file.status.d  = w_o_aux ? 1'b1 : 1'b0;
    assign ip_to_reg_file.status.de = w_o_aux | reg_file_to_ip.op_right.qe;

    // Result Left: Latched when w_o_aux pulses
    assign ip_to_reg_file.result_left.d  = w_o_left; 
    assign ip_to_reg_file.result_left.de = w_o_aux; 

    // Result Right: Latched when w_o_aux pulses
    assign ip_to_reg_file.result_right.d  = w_o_right; 
    assign ip_to_reg_file.result_right.de = w_o_aux; 
    
    // =========================================================================
    // Hardware Diagnostic Prints
    // =========================================================================
    always @(posedge clk_i) begin
        if (reg_file_to_ip.op_right.qe) begin
            $display("[HW DEBUG] CYCLE %0t: Auto-Trigger received on OP_RIGHT! i_aux is HIGH", $time);
            $fflush(); // Force Questasim to print immediately
        end
            
        if (w_o_aux) begin
            $display("[HW DEBUG] CYCLE %0t: Pipeline Finished! w_o_aux is HIGH", $time);
            $fflush(); // Force Questasim to print immediately
        end
    end

endmodule
