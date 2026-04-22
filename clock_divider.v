// Clock Divider - 27 MHz -> 33 MHz using Gowin rPLL
// Tang Nano 9K (Gowin GW1NR-9C)
//
// PLL parameters: IDIV=1, FBDIV=22, ODIV=18
// Output: 27 * (22+1) / ((1+1) * 18/2) = 27 * 23 / 18 = 34.5 MHz (approx 33 MHz)
//
// For simulation (iverilog): behavioral model generates ~33 MHz directly.
// For synthesis (Gowin IDE): uses Gowin_rPLL IP.

`timescale 1ns/1ps

`ifdef VERILATOR

// --- Verilator: pass-through (clock driven from C++) ---
module clock_divider (
    input  wire clk_27MHz,
    input  wire reset,
    output wire clk_pixel,
    output wire pll_locked
);
    assign clk_pixel  = clk_27MHz;
    assign pll_locked = ~reset;
endmodule

`elsif SIMULATION

// --- Simulation: behavioral 33 MHz generator ---
module clock_divider (
    input  wire clk_27MHz,
    input  wire reset,
    output reg  clk_pixel,
    output reg  pll_locked
);
    // 33 MHz period = ~30.3 ns -> half period ~15.15 ns
    // Approximate with 15 ns half-period
    initial begin
        clk_pixel  = 0;
        pll_locked = 0;
    end

    always #15 clk_pixel = ~clk_pixel;

    // Simulate PLL lock after a short delay
    initial begin
        #200;
        @(posedge clk_27MHz);
        pll_locked = 1;
    end

endmodule

`else

// --- Synthesis (default): Gowin rPLL ---
// Requires the Gowin_rPLL IP to be generated via Gowin EDA:
//   Tools -> IP Core Generator -> Clock -> rPLL
//   Input: 27 MHz, Output: 33 MHz, instance name: Gowin_rPLL
module clock_divider (
    input  wire clk_27MHz,
    input  wire reset,
    output wire clk_pixel,
    output wire pll_locked
);
    Gowin_rPLL u_pll (
        .clkout  (clk_pixel),
        .lock    (pll_locked),
        .clkin   (clk_27MHz),
        .reset   (reset)
    );
endmodule

`endif
