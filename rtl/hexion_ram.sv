//------------------------------------------------------------------------------
// Block RAMs of the Hexion core, written in the forms Quartus infers as M10K (registered address, registered output).
//   hexion_spram: one port, read and write
//   hexion_dpram: port A read and write, port B read only (the video's read of the VRAM and the line buffers)
//------------------------------------------------------------------------------
`default_nettype none

module hexion_spram #(
    parameter int AW = 13,
    parameter int DW = 8
) (
    input  logic          clk,
    input  logic [AW-1:0] addr,
    input  logic [DW-1:0] wdata,
    input  logic          we,
    output logic [DW-1:0] q
);
    logic [DW-1:0] mem [1 << AW];
    always_ff @(posedge clk) begin
        if (we) mem[addr] <= wdata;
        q <= mem[addr];
    end
endmodule

module hexion_dpram #(
    parameter int AW = 11,
    parameter int DW = 8
) (
    input  logic          clk,
    input  logic [AW-1:0] a_addr,
    input  logic [DW-1:0] a_wdata,
    input  logic          a_we,
    output logic [DW-1:0] a_q,
    input  logic [AW-1:0] b_addr,
    output logic [DW-1:0] b_q
);
    logic [DW-1:0] mem [1 << AW];
    always_ff @(posedge clk) begin
        if (a_we) mem[a_addr] <= a_wdata;
        a_q <= mem[a_addr];
    end
    always_ff @(posedge clk) b_q <= mem[b_addr];
endmodule
`default_nettype wire
