// Testbench - Snake Top (Tang Nano 9K + Sipeed 7-inch LCD 800x480)
// בודק: HSYNC/VSYNC תזמון + פיקסל נחש לבן במיקום הנכון
//
// הרצה:
//   iverilog -g2005 -o snake_sim.vvp clock_divider.v vga_controller.v keypad_scanner.v snake_top.v snake_top_tb.v
//   vvp snake_sim.vvp
`timescale 1ns/1ps

module snake_top_tb;

    // --- Inputs ---
    reg clk       = 0;
    reg reset_btn = 0;

    // --- Keypad (כל המקשים לא לחוצים) ---
    reg [3:0] KEY_COL = 4'b0000;

    // --- Outputs ---
    wire        LCD_CLK;
    wire        LCD_HYNC;
    wire        LCD_SYNC;
    wire        LCD_DEN;
    wire [4:0]  LCD_R;
    wire [5:0]  LCD_G;
    wire [4:0]  LCD_B;
    wire [3:0]  KEY_ROW;

    // --- DUT ---
    snake_top dut (
        .clk       (clk),
        .reset_btn (reset_btn),
        .LCD_CLK   (LCD_CLK),
        .LCD_HYNC  (LCD_HYNC),
        .LCD_SYNC  (LCD_SYNC),
        .LCD_DEN   (LCD_DEN),
        .LCD_R     (LCD_R),
        .LCD_G     (LCD_G),
        .LCD_B     (LCD_B),
        .KEY_ROW   (KEY_ROW),
        .KEY_COL   (KEY_COL)
    );

    // --- 27 MHz clock (period = ~37ns) ---
    always #18.5 clk = ~clk;

    // --- מונים ---
    integer hsync_count = 0;
    integer vsync_count = 0;
    integer white_pixels = 0;

    always @(negedge LCD_HYNC) hsync_count = hsync_count + 1;
    always @(negedge LCD_SYNC) vsync_count = vsync_count + 1;

    always @(posedge LCD_CLK) begin
        if (LCD_DEN && LCD_R == 5'b11111 && LCD_G == 6'b111111 && LCD_B == 5'b11111)
            white_pixels = white_pixels + 1;
    end

    // --- VCD ---
    initial begin
        $dumpfile("snake_top_tb.vcd");
        $dumpvars(0, snake_top_tb);
        #1_000_000;
        $dumpoff;
    end

    // --- Test sequence ---
    // פריים אחד = 1056 * 525 = 554,400 clocks * 30ns = 16.6ms
    // 2 פריימים ≈ 34ms (הנחש לא זז - SPEED=15 פריימים)
    initial begin
        $display("Starting simulation...");

        reset_btn = 1'b0;   // reset פעיל (active-low)
        #200;
        reset_btn = 1'b1;   // שחרור reset

        #34_000_000;        // המתן 2 פריימים

        $display("=== RESULTS ===");
        $display("VSYNC pulses : %0d  (expected ~2)", vsync_count);
        $display("HSYNC pulses : %0d  (expected ~1050)", hsync_count);
        $display("White pixels : %0d  (expected 1800 = 30x30 x2 frames)", white_pixels);

        if (vsync_count >= 1 && vsync_count <= 3)
            $display("PASS: VSYNC OK");
        else
            $display("FAIL: VSYNC wrong! got %0d", vsync_count);

        if (hsync_count >= 1000 && hsync_count <= 1100)
            $display("PASS: HSYNC OK");
        else
            $display("FAIL: HSYNC wrong! got %0d", hsync_count);

        // תא 32x32 עם border=1 → גרעין 30x30 = 900 פיקסלים/פריים
        // 2 פריימים = 1800 (הנחש לא זז ב-2 פריימים ראשונים - SPEED=15)
        if (white_pixels >= 1700 && white_pixels <= 1900)
            $display("PASS: Snake pixel count OK");
        else
            $display("FAIL: Snake pixels wrong! got %0d", white_pixels);

        $display("Simulation done.");
        $finish;
    end

endmodule
