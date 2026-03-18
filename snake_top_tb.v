// Testbench - Snake Top (Tang Nano 9K + Sipeed 7-inch LCD 800x480)
// בודק: HSYNC/VSYNC תזמון + פיקסל נחש לבן במיקום הנכון
//
// הרצה:
//   iverilog -g2005 -o snake_sim.vvp clock_divider.v vga_controller.v snake_top.v snake_top_tb.v
//   vvp snake_sim.vvp

module snake_top_tb;

    // --- Inputs ---
    reg clk       = 0;
    reg reset_btn = 0;

    // --- Outputs (תואמים בדיוק לפורטים של snake_top) ---
    wire        LCD_CLK;
    wire        LCD_HYNC;
    wire        LCD_SYNC;
    wire        LCD_DEN;
    wire [4:0]  LCD_R;
    wire [5:0]  LCD_G;
    wire [4:0]  LCD_B;

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
        .LCD_B     (LCD_B)
    );

    // --- 27 MHz clock (period = ~37ns) ---
    always #18.5 clk = ~clk;

    // --- מונים ---
    integer hsync_count = 0;
    integer vsync_count = 0;
    integer white_pixels = 0;  // פיקסלים לבנים (נחש)

    always @(negedge LCD_HYNC) hsync_count = hsync_count + 1;
    always @(negedge LCD_SYNC) vsync_count = vsync_count + 1;

    // ספירת פיקסלים לבנים (LCD_DEN=1 + כל הצבעים מקסימליים)
    always @(posedge LCD_CLK) begin
        if (LCD_DEN && LCD_R == 5'b11111 && LCD_G == 6'b111111 && LCD_B == 5'b11111)
            white_pixels = white_pixels + 1;
    end

    // --- VCD: רק 1ms ראשון (לא לפוצץ את הדיסק) ---
    initial begin
        $dumpfile("snake_top_tb.vcd");
        $dumpvars(0, snake_top_tb);
        #1_000_000;
        $dumpoff;
    end

    // --- Test sequence ---
    // פריים אחד = 1056 * 525 = 554,400 clocks * 30ns = 16.6ms
    // 2 פריימים ≈ 33.3ms + מרווח ביטחון = 34ms
    initial begin
        $display("Starting simulation...");

        reset_btn = 1'b0;   // reset פעיל (active-low)
        #200;
        reset_btn = 1'b1;   // שחרור reset

        #34_000_000;        // המתן 2 פריימים

        // --- בדיקות ---
        $display("=== RESULTS ===");
        $display("VSYNC pulses : %0d  (expected ~2)", vsync_count);
        $display("HSYNC pulses : %0d  (expected ~1050)", hsync_count);
        $display("White pixels : %0d  (expected 900 = 30x30 snake core)", white_pixels);

        // VSYNC: צפוי 2 פעמים (2 פריימים)
        if (vsync_count >= 1 && vsync_count <= 3)
            $display("PASS: VSYNC OK");
        else
            $display("FAIL: VSYNC wrong! got %0d", vsync_count);

        // HSYNC: 525 שורות * 2 פריימים = 1050
        if (hsync_count >= 1000 && hsync_count <= 1100)
            $display("PASS: HSYNC OK");
        else
            $display("FAIL: HSYNC wrong! got %0d", hsync_count);

        // פיקסלים לבנים: תא 32x32 עם border=1 -> גרעין 30x30 = 900 פיקסלים לפריים
        // 2 פריימים = 1800 פיקסלים לבנים
        if (white_pixels >= 1700 && white_pixels <= 1900)
            $display("PASS: Snake pixel count OK");
        else
            $display("FAIL: Snake pixels wrong! got %0d", white_pixels);

        $display("Simulation done.");
        $finish;
    end

endmodule
