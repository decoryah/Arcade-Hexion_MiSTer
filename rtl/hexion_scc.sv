//------------------------------------------------------------------------------
// Konami 051649 (SCC): five wavetable voices, 32 signed bytes each (voice 5 plays voice 4's table), written from MAME 0.289's
// k051649.cpp. One output sample per clock of the chip (3 MHz = 24 MHz / 8): for each voice whose frequency register is above 8,
// the 16-bit clock counter counts up and past the frequency steps the table position and restarts at 0; at clock 0 the voice
// latches table[position] * volume (0 when keyed off). The output is the sum of the five latched samples >> 4 (signed, -600..595;
// MAME scales it by 1/1024). A frequency write sets the clock counter to -1 (the sample reloads on the next clock); test register bit
// 5 also clears the position; bits 6 / 7 make the tables read-only and show them rotated by a position, as in MAME.
//
// Register map (the CPU at e800-e8ff, offset here): 00-7f tables (60-7f voices 4 and 5), 80-89 frequency (low byte, high 4 bits per
// voice), 8a-8e volume, 8f key on/off (bits 0-4), the same at 90-9f; e0-ff the test register (a read returns 0, MAME's unmapped
// value on this machine, and writes it to the register).
//
// A register write that comes while the engine is computing a sample waits for it to finish: in MAME the stream is brought up to
// the write's time first, so a write counts from the next sample on.
//------------------------------------------------------------------------------
`default_nettype none

module hexion_scc (
    input  logic        clk,
    input  logic        reset,
    input  logic        ce,             // 3 MHz: one output sample
    input  logic        wr,             // one clock per CPU write
    input  logic        rd,             // one clock per CPU read (the test register's read side effect)
    input  logic  [7:0] addr,
    input  logic  [7:0] din,
    output logic  [7:0] dout,           // the table byte at addr (valid two clocks after addr)
    output logic signed [10:0] sample
);
    logic [11:0] freq [5];
    logic  [3:0] vol  [5];
    logic  [4:0] key;
    logic  [7:0] test;
    logic [15:0] cnt  [5];
    logic  [4:0] pos  [5];
    logic signed [11:0] smp [5];        // table byte * volume

    // ------------------------------------------------------------------ the tables
    // 4 x 32 bytes; port A the CPU (writes and reads), port B the voice engine
    wire         sel_wave = (addr[7] == 1'b0);
    wire         wave_we  = wr && sel_wave && !test[6] && !(test[7] && addr[6:5] == 2'd3);
    logic  [4:0] rot;                   // MAME's k051649_waveform_r with test bits 6 / 7: the table rotated by a voice's position
    always_comb begin
        rot = 5'd0;
        if (addr[6:5] == 2'd3 && test[7:6] != 2'b00 && test[7:6] != 2'b11) rot = pos[test[6] ? 4 : 3];
        else if (test[6])                                                   rot = pos[addr[6:5]];
    end
    wire   [6:0] wa_addr = {addr[6:5], addr[4:0] + rot};
    logic  [6:0] wb_addr;
    logic  [7:0] wa_q, wb_q;
    hexion_dpram #(.AW(7), .DW(8)) u_wave (.clk(clk), .a_addr(wa_addr), .a_wdata(din), .a_we(wave_we), .a_q(wa_q),
                                           .b_addr(wb_addr), .b_q(wb_q));
    always_ff @(posedge clk) dout <= wa_q;

    // ------------------------------------------------------------------ the registers and the voice engine
    // per voice three clocks: step the counters and address the table; the RAM reads; latch the sample
    logic       busy;
    logic [2:0] v;
    logic [1:0] st;
    logic       reload;
    logic       pw;                     // a register write waiting for the engine
    logic [7:0] pw_addr, pw_data;
    logic       sum_go;

    wire  [2:0] tv = (v == 3'd4) ? 3'd3 : v;
    wire [15:0] c1 = cnt[v] + 16'd1;

    always_ff @(posedge clk) begin
        sum_go <= 1'b0;
        if (reset) begin
            for (int i = 0; i < 5; i++) begin
                freq[i] <= 12'd0; vol[i] <= 4'hf; cnt[i] <= 16'd0; pos[i] <= 5'd0; smp[i] <= 12'sd0;
            end
            key <= 5'd0; test <= 8'd0; busy <= 1'b0; pw <= 1'b0; sample <= 11'sd0;
        end else begin
            // the CPU side
            if (wr && addr[7]) begin pw <= 1'b1; pw_addr <= addr; pw_data <= din; end
            if (rd && addr[7:5] == 3'b111) test <= 8'h00;

            if (!busy) begin
                if (pw && !(wr && addr[7])) begin
                    pw <= 1'b0;
                    if (pw_addr[6:5] == 2'b00 && pw_addr[3:0] <= 4'h9) begin
                        if (pw_addr[0]) freq[pw_addr[3:1]][11:8] <= pw_data[3:0];
                        else            freq[pw_addr[3:1]][7:0]  <= pw_data;
                        if (test[5]) pos[pw_addr[3:1]] <= 5'd0;
                        cnt[pw_addr[3:1]] <= 16'hffff;
                    end
                    if (pw_addr[6:5] == 2'b00 && pw_addr[3:0] >= 4'ha && pw_addr[3:0] <= 4'he) vol[pw_addr[3:0] - 4'ha] <= pw_data[3:0];
                    if (pw_addr[6:5] == 2'b00 && pw_addr[3:0] == 4'hf) key <= pw_data[4:0];
                    if (pw_addr[6:5] == 2'b11) test <= pw_data;
                end
                if (ce) begin busy <= 1'b1; v <= 3'd0; st <= 2'd0; end
            end else begin
                case (st)
                    2'd0: begin
                        st <= 2'd1;
                        reload <= 1'b0;
                        if (freq[v] > 12'd8) begin
                            if (c1 > {4'd0, freq[v]}) begin
                                cnt[v] <= 16'd0;
                                pos[v] <= pos[v] + 5'd1;
                                wb_addr <= {tv[1:0], pos[v] + 5'd1};
                                reload <= 1'b1;
                            end else begin
                                cnt[v] <= c1;
                                wb_addr <= {tv[1:0], pos[v]};
                                reload <= (c1 == 16'd0);
                            end
                        end
                    end
                    2'd1: st <= 2'd2;           // the table RAM takes wb_addr at this edge
                    default: begin
                        st <= 2'd0;
                        if (reload) smp[v] <= key[v] ? $signed({{4{wb_q[7]}}, wb_q}) * $signed({8'd0, vol[v]}) : 12'sd0;
                        if (v == 3'd4) begin busy <= 1'b0; sum_go <= 1'b1; end
                        else v <= v + 3'd1;
                    end
                endcase
            end
            if (sum_go)
                sample <= 11'(($signed(smp[0]) >>> 4) + ($signed(smp[1]) >>> 4) + ($signed(smp[2]) >>> 4)
                            + ($signed(smp[3]) >>> 4) + ($signed(smp[4]) >>> 4));
        end
    end
endmodule
`default_nettype wire
