//------------------------------------------------------------------------------
// The ROM image's way in: the HPS download arrives a byte at a time at its image offset; this module routes each byte to the
// program ROM (BRAM), the colour PROMs (BRAM), the board byte, or its place in the SDRAM.
//
// The image (mra/*.mra, tools/hexion_rom.py), the same layout for both sets:
//   0x000000  maincpu  128 KB  the Z80 program                      -> BRAM
//   0x020000  tiles    512 KB  122a07.1h, then 122a06.1g (MAME's "tiles")
//   0x0A0000  oki      256 KB  122a05.2f
//   0x0E0000  proms    768 B   122a04.10b (red), 122a03.11b (green), 122a02.13b (blue)   -> BRAM
//   0x0E0300  board    1 B     0 the Konami board (K051649), 1 the bootleg (a second OKI)
//   0x100000  oki2     256 KB  hexionb.u18 (the bootleg only)
//
// The SDRAM (byte addresses): tiles at 0x000000 with the region's half bit (offset bit 18) moved down next to bit 0, so a tile row's
// two byte pairs (its pixels 2,3,6,7 from the first half and 0,1,4,5 from the second) are one 2-word burst:
// SDRAM byte = {b[17:1], b[18], b[0]} for tiles offset b. OKI at 0x080000, OKI 2 at 0x0C0000. Byte pairs stay pairs.
//------------------------------------------------------------------------------
`default_nettype none

module hexion_loader (
    input  logic        clk,
    input  logic        dl_wr,                 // one clock per byte
    input  logic [20:0] dl_addr,               // image offset
    input  logic  [7:0] dl_data,
    output logic        o_wr,                  // to the SDRAM's download port
    output logic [24:0] o_addr,
    output logic  [7:0] o_data,
    output logic        prog_wr,
    output logic [16:0] prog_addr,
    output logic        prom_wr,
    output logic  [9:0] prom_addr,
    output logic  [7:0] b_data,                // the data of prog_wr / prom_wr
    output logic        board_wr
);
    localparam logic [20:0] TILES = 21'h020000, OKI = 21'h0A0000, PROMS = 21'h0E0000, BOARD = 21'h0E0300, OKI2 = 21'h100000,
                            END2 = 21'h140000;

    wire [20:0] b = dl_addr - TILES;
    always_ff @(posedge clk) begin
        o_wr <= 1'b0; prog_wr <= 1'b0; prom_wr <= 1'b0; board_wr <= 1'b0;
        o_data <= dl_data; b_data <= dl_data;
        prog_addr <= dl_addr[16:0];
        prom_addr <= dl_addr[9:0];
        if (dl_wr) begin
            if (dl_addr < TILES) prog_wr <= 1'b1;
            else if (dl_addr < OKI) begin
                o_wr <= 1'b1; o_addr <= {6'd0, b[17:1], b[18], b[0]};
            end else if (dl_addr < PROMS) begin
                o_wr <= 1'b1; o_addr <= {7'd0, 18'(dl_addr - OKI)} + 25'h080000;
            end else if (dl_addr < BOARD) prom_wr <= 1'b1;
            else if (dl_addr == BOARD) board_wr <= 1'b1;
            else if (dl_addr >= OKI2 && dl_addr < END2) begin
                o_wr <= 1'b1; o_addr <= {7'd0, 18'(dl_addr - OKI2)} + 25'h0C0000;
            end
        end
    end
endmodule
`default_nettype wire
