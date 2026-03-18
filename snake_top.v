// Snake Game - Top Module
// Hardware: Tang Nano 9K (Gowin GW1NR-9C) + Sipeed 7-inch LCD 800x480
//
// System clock: 27 MHz (onboard crystal, פין 52)
// Pixel clock:  33 MHz (via Gowin rPLL)
// Color depth:  RGB565
//
// Grid: 25 cols × 15 rows (each cell = 32×32 px)
// Speed: SPEED frames per move (15 frames @ 60Hz = 4 moves/sec)
//
// Keypad (4x4 matrix):
//   UP=2, DOWN=8, LEFT=4, RIGHT=6

module snake_top (
    input  wire        clk,        // 27 MHz (פין 52)
    input  wire        reset_btn,  // כפתור S1 active-low (פין 4)

    // ממשק LCD
    output wire        LCD_CLK,
    output wire        LCD_HYNC,
    output wire        LCD_SYNC,
    output wire        LCD_DEN,
    output wire [4:0]  LCD_R,
    output wire [5:0]  LCD_G,
    output wire [4:0]  LCD_B,

    // ממשק Keypad 4x4
    output wire [3:0]  KEY_ROW,   // פינים 66,65,64,63
    input  wire [3:0]  KEY_COL    // פינים 82,81,80,79
);
    // --- Reset ---
    wire reset = ~reset_btn;

    // --- PLL: 27 MHz → 33 MHz ---
    wire clk_pixel;
    wire pll_locked;

    clock_divider u_pll (
        .clk_27MHz  (clk),
        .reset      (reset),
        .clk_pixel  (clk_pixel),
        .pll_locked (pll_locked)
    );

    wire sys_reset = reset | ~pll_locked;

    // --- LCD Controller ---
    wire        vsync_int;
    wire        de;
    wire [9:0]  pixel_x;
    wire [9:0]  pixel_y;

    vga_controller u_lcd (
        .clk_pixel (clk_pixel),
        .reset     (sys_reset),
        .hsync     (LCD_HYNC),
        .vsync     (vsync_int),
        .de        (de),
        .pixel_x   (pixel_x),
        .pixel_y   (pixel_y)
    );

    assign LCD_CLK  = clk_pixel;
    assign LCD_DEN  = de;
    assign LCD_SYNC = vsync_int;

    // --- Keypad Scanner ---
    wire key_up, key_down, key_left, key_right;

    keypad_scanner u_keypad (
        .clk       (clk_pixel),
        .reset     (sys_reset),
        .row       (KEY_ROW),
        .col       (KEY_COL),
        .key_up    (key_up),
        .key_down  (key_down),
        .key_left  (key_left),
        .key_right (key_right)
    );

    // -------------------------------------------------------
    //  Snake Logic
    // -------------------------------------------------------
    localparam CELL_SIZE = 32;
    localparam GRID_COLS = 25;   // 800 / 32
    localparam GRID_ROWS = 15;   // 480 / 32
    localparam BORDER    = 1;
    localparam SPEED     = 15;   // פריימים בין כל תזוזה (4 תזוזות/שנייה)

    localparam DIR_RIGHT = 2'd0;
    localparam DIR_LEFT  = 2'd1;
    localparam DIR_UP    = 2'd2;
    localparam DIR_DOWN  = 2'd3;

    // מיקום ראש הנחש (בתאים)
    reg [4:0]  head_col;   // 0..24
    reg [3:0]  head_row;   // 0..14
    reg [1:0]  direction;
    reg [3:0]  frame_cnt;

    // זיהוי עלייה של vsync (end of vsync pulse = frame boundary)
    reg vsync_d;
    wire frame_tick = ~vsync_d & vsync_int;

    always @(posedge clk_pixel or posedge sys_reset) begin
        if (sys_reset) begin
            vsync_d   <= 1'b1;
            head_col  <= 5'd12;   // מרכז: עמודה 12
            head_row  <= 4'd7;    // מרכז: שורה 7
            direction <= DIR_RIGHT;
            frame_cnt <= 4'd0;
        end else begin
            vsync_d <= vsync_int;

            if (frame_tick) begin
                // עדכון כיוון - מונע פנייה של 180°
                if      (key_up    && direction != DIR_DOWN)  direction <= DIR_UP;
                else if (key_down  && direction != DIR_UP)    direction <= DIR_DOWN;
                else if (key_left  && direction != DIR_RIGHT) direction <= DIR_LEFT;
                else if (key_right && direction != DIR_LEFT)  direction <= DIR_RIGHT;

                // תזוזה כל SPEED פריימים
                frame_cnt <= frame_cnt + 1;
                if (frame_cnt == SPEED - 1) begin
                    frame_cnt <= 4'd0;
                    case (direction)
                        DIR_RIGHT: head_col <= (head_col == 5'd24) ? 5'd0  : head_col + 1;
                        DIR_LEFT:  head_col <= (head_col == 5'd0)  ? 5'd24 : head_col - 1;
                        DIR_UP:    head_row <= (head_row == 4'd0)  ? 4'd14 : head_row - 1;
                        DIR_DOWN:  head_row <= (head_row == 4'd14) ? 4'd0  : head_row + 1;
                    endcase
                end
            end
        end
    end

    // -------------------------------------------------------
    //  Rendering
    // -------------------------------------------------------
    wire [9:0] head_px = {head_col, 5'b00000};   // head_col * 32
    wire [9:0] head_py = {1'b0, head_row, 5'b00000};  // head_row * 32

    wire in_snake = de &&
        (pixel_x >= head_px + BORDER) && (pixel_x < head_px + CELL_SIZE - BORDER) &&
        (pixel_y >= head_py + BORDER) && (pixel_y < head_py + CELL_SIZE - BORDER);

    // לבן = נחש, שחור = רקע
    assign LCD_R = in_snake ? 5'b11111 : 5'b00000;
    assign LCD_G = in_snake ? 6'b111111 : 6'b000000;
    assign LCD_B = in_snake ? 5'b11111 : 5'b00000;

endmodule
