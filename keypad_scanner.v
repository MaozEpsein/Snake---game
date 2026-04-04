// Keypad Matrix Scanner - 4x4
// Tang Nano 9K - Snake Game Controller
//
// Keypad layout:
//        COL[0] COL[1] COL[2] COL[3]
//  ROW[0]:  1      2      3      A
//  ROW[1]:  4      5      6      B
//  ROW[2]:  7      8      9      C
//  ROW[3]:  *      0      #      D
//
// Snake direction mapping:
//   UP    = key "2" -> ROW[0], COL[1]
//   LEFT  = key "4" -> ROW[1], COL[0]
//   PAUSE = key "5" -> ROW[1], COL[1]
//   RIGHT = key "6" -> ROW[1], COL[2]
//   DOWN  = key "8" -> ROW[2], COL[1]
//   RESTART = key "D" -> ROW[3], COL[3]
//
// row[3:0] -> pins 66,65,64,63 (FPGA output)
// col[3:0] -> pins 82,81,80,79 (FPGA input, PULL_DOWN in CST)

`timescale 1ns/1ps

module keypad_scanner (
    input  wire       clk,        // 33 MHz pixel clock
    input  wire       reset,

    output reg  [3:0] row,        // ROW outputs - one row HIGH at a time
    input  wire [3:0] col,        // COL inputs  - HIGH when key pressed

    output reg        key_up,
    output reg        key_down,
    output reg        key_left,
    output reg        key_right,
    output reg        key_pause,
    output reg        key_restart
);
    // 33 MHz / 2^15 = ~1007 Hz per row  ->  ~252 Hz full scan
    reg [14:0] scan_timer;
    reg [1:0]  row_sel;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            scan_timer <= 15'b0;
            row_sel    <= 2'b0;
        end else begin
            scan_timer <= scan_timer + 1'b1;
            if (scan_timer == 15'h7FFF)
                row_sel <= row_sel + 1'b1;
        end
    end

    always @(*) begin
        case (row_sel)
            2'd0: row = 4'b0001;
            2'd1: row = 4'b0010;
            2'd2: row = 4'b0100;
            2'd3: row = 4'b1000;
        endcase
    end

    // Sample columns at mid-scan (stable region)
    reg [3:0] col_r0, col_r1, col_r2, col_r3;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            col_r0 <= 4'b0;
            col_r1 <= 4'b0;
            col_r2 <= 4'b0;
            col_r3 <= 4'b0;
        end else if (scan_timer == 15'h4000) begin
            case (row_sel)
                2'd0: col_r0 <= col;
                2'd1: col_r1 <= col;
                2'd2: col_r2 <= col;
                2'd3: col_r3 <= col;
            endcase
        end
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            key_up    <= 1'b0;
            key_down  <= 1'b0;
            key_left  <= 1'b0;
            key_right <= 1'b0;
            key_pause <= 1'b0;
            key_restart <= 1'b0;
        end else begin
            key_up    <= col_r0[1];  // ROW0, COL1 = "2"
            key_down  <= col_r2[1];  // ROW2, COL1 = "8"
            key_left  <= col_r1[0];  // ROW1, COL0 = "4"
            key_right <= col_r1[2];  // ROW1, COL2 = "6"
            key_pause <= col_r1[1];  // ROW1, COL1 = "5"
            key_restart <= col_r3[3]; // ROW3, COL3 = "D"
        end
    end

endmodule
