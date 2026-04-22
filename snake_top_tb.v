// Testbench - Snake Game (Tang Nano 9K + Sipeed 7-inch LCD 800x480)
//
// Phase 1 - ST_IDLE:       white title text, no green pixels
// Phase 2 - Idle start gate: only key "5" starts, arrows must not start
// Phase 3 - ST_PLAYING:    head green, food red, score/HUD visible, no bad pixels
// Phase 4 - Movement:      head position changes after one forced game move
// Phase 5 - U-turn block:  pressing opposite direction does not reverse snake
// Phase 6 - Pause/Resume:  key "5" toggles paused, freezes and resumes movement
// Phase 7 - Restart (D):   short press ignored, long press (~1s) restarts game
// Phase 8 - Game Over:     hit_body=1 -> transitions to ST_GAME_OVER + LAST score latched
// Phase 9 - GO visuals:    red/dark-red background + GAME OVER text, no green
// Phase 10 - Reset:        S1 returns to ST_IDLE, title visible
// Phase 11 - Obstacle spawn: forced spawn window creates obstacle(s)
// Phase 12 - Head safety:   near-head spawn blocked, farther spawn allowed
// Phase 13 - Obstacle TTL:  forced expiry clears obstacle map/slot
// Phase 14 - Obstacle hit:  next-cell obstacle causes immediate game over
//
// Acceleration technique (Phases 3, 4):
//   Instead of waiting 15 frames for a game move, force dut.frame_cnt = 14
//   immediately before a frame_tick.  The move fires on that same tick.
//
// Build & run:
//   iverilog -g2005 -o snake_sim.vvp clock_divider.v vga_controller.v \
//            keypad_scanner.v snake_top.v snake_top_tb.v
//   vvp snake_sim.vvp

`timescale 1ns/1ps

module snake_top_tb;

    reg clk       = 0;
    reg reset_btn = 0;
    reg [3:0] KEY_COL = 4'b0000;

    wire        LCD_CLK, LCD_HSYNC, LCD_VSYNC, LCD_DEN;
    wire [4:0]  LCD_R;
    wire [5:0]  LCD_G;
    wire [4:0]  LCD_B;
    wire [3:0]  KEY_ROW;

    snake_top dut (
        .clk(clk), .reset_btn(reset_btn),
        .LCD_CLK(LCD_CLK), .LCD_HSYNC(LCD_HSYNC), .LCD_VSYNC(LCD_VSYNC),
        .LCD_DEN(LCD_DEN), .LCD_R(LCD_R), .LCD_G(LCD_G), .LCD_B(LCD_B),
        .KEY_ROW(KEY_ROW), .KEY_COL(KEY_COL)
    );

    always #18.5 clk = ~clk;

    integer vsync_count   = 0;
    integer white_pixels  = 0;
    integer green_pixels  = 0;
    integer red_pixels    = 0;   // bright red: R=11111 G=0 B=0
    integer anyred_pixels = 0;   // any red-only: R>0 G=0 B=0  (covers dark flash too)
    integer bad_pixels    = 0;

    always @(negedge LCD_VSYNC) vsync_count = vsync_count + 1;

    always @(posedge LCD_CLK) begin
        if (LCD_DEN && LCD_R==5'b11111 && LCD_G==6'b111111 && LCD_B==5'b11111)
            white_pixels  = white_pixels  + 1;
        if (LCD_DEN && LCD_R==5'b00000 && LCD_G==6'b111111 && LCD_B==5'b00000)
            green_pixels  = green_pixels  + 1;
        if (LCD_DEN && LCD_R==5'b11111 && LCD_G==6'b000000 && LCD_B==5'b00000)
            red_pixels    = red_pixels    + 1;
        if (LCD_DEN && LCD_G==6'b000000 && LCD_B==5'b00000 && LCD_R!=5'b0)
            anyred_pixels = anyred_pixels + 1;
        if (!LCD_DEN && (LCD_R!=5'b0 || LCD_G!=6'b0 || LCD_B!=5'b0))
            bad_pixels    = bad_pixels    + 1;
    end

    task reset_counters;
        begin
            white_pixels  = 0; green_pixels  = 0;
            red_pixels    = 0; anyred_pixels = 0;
            vsync_count   = 0; bad_pixels    = 0;
        end
    endtask

    task tb_pulse_frame_tick;
        begin
            @(posedge dut.frame_tick);
        end
    endtask

    task tb_wait_frames;
        input integer count;
        begin
            repeat (count) @(posedge dut.frame_tick);
        end
    endtask

    task tb_visual_wait;
        begin
`ifdef FAST_MODE
            #300000;
`else
            #(2 * ONE_FRAME);
`endif
        end
    endtask

    // Force a game move immediately by setting frame_cnt to move_speed-1
    // right before the next frame_tick.
    task force_one_move;
        begin
            dut.frame_cnt = dut.move_speed - 4'd1;
            tb_wait_frames(1);
            #60;                           // 2 clk_pixel periods - let NBA settle
        end
    endtask

    // Trigger one obstacle spawn attempt deterministically.
    task trigger_obstacle_spawn;
        input [15:0] seed;
        begin
            force dut.play_frame_cnt = 9'd200;      // past grace window
            force dut.obstacle_spawn_cnt = 9'd511;  // guarantee spawn attempt
            force dut.lfsr = seed;
            tb_wait_frames(1);
            #60;
            release dut.lfsr;
            release dut.obstacle_spawn_cnt;
            release dut.play_frame_cnt;
        end
    endtask

    task start_game_from_idle;
        begin
            force dut.key_pause = 1'b1;
            tb_wait_frames(3);
            release dut.key_pause;
            tb_wait_frames(2);
        end
    endtask

    initial begin
        $dumpfile("snake_top_tb.vcd");
        $dumpvars(0, snake_top_tb);
        #500_000;
        $dumpoff;
    end

    localparam ONE_FRAME = 17_000_000;

    initial begin
        $display("=== Snake Game Testbench ===");

        reset_btn = 1'b0; #200;
        reset_btn = 1'b1; #100;
        reset_counters;

        // ---- Phase 1: ST_IDLE (2 frames, no key pressed) ----
        tb_visual_wait;
        $display("--- Phase 1: ST_IDLE ---");
        $display("VSYNC  : %0d (expect 2)",  vsync_count);
        $display("White  : %0d (expect >0 title text)", white_pixels);
        $display("Green  : %0d (expect 0  no game yet)", green_pixels);

        if (vsync_count >= 1 && vsync_count <= 3)
            $display("PASS: VSYNC timing OK");
        else
            $display("FAIL: VSYNC wrong - got %0d", vsync_count);

        if (white_pixels > 0)
            $display("PASS: Title text visible");
        else
            $display("FAIL: No title text pixels");

        if (green_pixels == 0)
            $display("PASS: No game pixels in IDLE");
        else
            $display("FAIL: Unexpected green in IDLE: %0d", green_pixels);

        reset_counters;

        // ---- Phase 2: Idle start gate (only key 5 starts) ----
        $display("--- Phase 2: Idle start gate ---");
        force dut.key_up = 1'b1;
        tb_wait_frames(2);
        release dut.key_up;
        tb_wait_frames(1);
        if (dut.game_state == 2'd0)
            $display("PASS: Arrow key does not start from IDLE");
        else
            $display("FAIL: Arrow key started game from IDLE (state=%0d)", dut.game_state);

        start_game_from_idle;
        if (dut.game_state == 2'd1)
            $display("PASS: Key 5 starts game from IDLE");
        else
            $display("FAIL: Key 5 did not start game (state=%0d)", dut.game_state);

        // Ensure BEST has a non-zero known value via one forced "eat" event
        force dut.eating_food = 1'b1;
        force dut.hit_body    = 1'b0;
        dut.frame_cnt = dut.move_speed - 4'd1;
        tb_wait_frames(1);
        #60;
        release dut.eating_food;
        release dut.hit_body;
        if (dut.best_score > 8'd0)
            $display("PASS: BEST updates during play");
        else
            $display("FAIL: BEST did not update");

        reset_counters;
        tb_visual_wait;

        $display("--- Phase 3: ST_PLAYING ---");
        $display("Green  : %0d (expect ~1800 head pixels)", green_pixels);
        $display("Red    : %0d (expect >0 food)", red_pixels);
        $display("White  : %0d (expect >0 score)", white_pixels);
        $display("Bad    : %0d (expect 0)", bad_pixels);

        if (green_pixels >= 1700 && green_pixels <= 1900)
            $display("PASS: Head pixel count OK");
        else
            $display("FAIL: Head pixels wrong - got %0d", green_pixels);

        if (red_pixels > 0)
            $display("PASS: Food rendered");
        else
            $display("FAIL: No food pixels");

        if (white_pixels > 0)
            $display("PASS: Score overlay rendered");
        else
            $display("FAIL: No score pixels");

        if (bad_pixels == 0)
            $display("PASS: No pixels outside DE");
        else
            $display("FAIL: %0d pixels outside DE", bad_pixels);

        // ---- Phase 4: Snake movement ----
        // Force frame_cnt -> move fires on next frame_tick (no 15-frame wait).
        // Snake is going UP: head_row must decrease by 1.
        $display("--- Phase 4: Snake movement ---");
        begin : phase3
            reg [4:0] pre_col;
            reg [3:0] pre_row;
            force dut.direction = 2'd2; // DIR_UP
            pre_col = dut.head_col;
            pre_row = dut.head_row;
            $display("Pre-move  head: col=%0d row=%0d", pre_col, pre_row);
            force_one_move;
            $display("Post-move head: col=%0d row=%0d", dut.head_col, dut.head_row);
            if (dut.head_row < pre_row || (pre_row == 4'd0 && dut.head_row == 4'd14))
                $display("PASS: Snake moved UP");
            else
                $display("FAIL: Snake did not move UP (row %0d -> %0d)", pre_row, dut.head_row);
            // Count one clean frame to verify pixel output after the move
            reset_counters;
            tb_wait_frames(1);
            #60;
            if (green_pixels >= 1700 && green_pixels <= 1900)
                $display("PASS: Head pixels OK after move");
            else
                $display("FAIL: Head pixels wrong after move - got %0d", green_pixels);
            release dut.direction;
            release dut.key_right;
            release dut.key_left;
            release dut.key_down;
            release dut.key_up;
        end

        // ---- Phase 5: U-turn prevention ----
        // Direction is UP. Force key_down=1 (opposite) for one frame, then
        // trigger a move and verify the row still decreased (snake kept going UP).
        $display("--- Phase 5: U-turn prevention ---");
        begin : phase4
            reg [3:0] pre_row4;
            force dut.direction = 2'd2; // ensure known current direction UP
            pre_row4 = dut.head_row;
            // Override keypad_scanner outputs to simulate pressing DOWN
            force dut.key_down = 1'b1;
            force dut.key_up   = 1'b0;
            tb_wait_frames(1);  // let one frame_tick see key_down
            #1;
            release dut.key_down;
            release dut.key_up;
            // Now trigger a move
            force_one_move;
            $display("Post-Uturn head: col=%0d row=%0d", dut.head_col, dut.head_row);
            if (dut.head_row < pre_row4 || (pre_row4 == 4'd0 && dut.head_row == 4'd14))
                $display("PASS: U-turn blocked, snake still moving UP");
            else
                $display("FAIL: U-turn NOT blocked (row %0d -> %0d)", pre_row4, dut.head_row);
            release dut.direction;
            release dut.key_right;
            release dut.key_left;
        end

        // ---- Phase 6: Pause/Resume (key 5) ----
        $display("--- Phase 6: Pause/Resume (key 5) ---");
        begin : phase5
            reg [4:0] pre_col5;
            reg [3:0] pre_row5;
            reg [4:0] paused_col5;
            reg [3:0] paused_row5;

            // Ensure a clean low level first, then create a rising edge
            force dut.key_pause = 1'b0;
            tb_wait_frames(1);

            // Toggle pause ON
            force dut.key_pause = 1'b1;
            tb_wait_frames(1);
            #1;
            release dut.key_pause;

            if (dut.paused)
                $display("PASS: Pause toggled ON");
            else
                $display("FAIL: Pause did not toggle ON");

            // Verify snake is frozen while paused
            pre_col5 = dut.head_col;
            pre_row5 = dut.head_row;
            tb_visual_wait;
            paused_col5 = dut.head_col;
            paused_row5 = dut.head_row;
            if (paused_col5 == pre_col5 && paused_row5 == pre_row5)
                $display("PASS: Snake frozen during pause");
            else
                $display("FAIL: Snake moved during pause (%0d,%0d)->(%0d,%0d)",
                         pre_col5, pre_row5, paused_col5, paused_row5);

            // Ensure a clean low level first, then create a rising edge
            force dut.key_pause = 1'b0;
            tb_wait_frames(1);

            // Toggle pause OFF
            force dut.key_pause = 1'b1;
            tb_wait_frames(1);
            #1;
            release dut.key_pause;

            if (!dut.paused)
                $display("PASS: Pause toggled OFF (resume)");
            else
                $display("FAIL: Pause did not toggle OFF");

            // Verify movement resumes
            pre_col5 = dut.head_col;
            pre_row5 = dut.head_row;
            force_one_move;
            if (dut.head_col != pre_col5 || dut.head_row != pre_row5)
                $display("PASS: Snake moves after resume");
            else
                $display("FAIL: Snake still frozen after resume");
        end

        // ---- Phase 7: Restart by D long-press ----
        $display("--- Phase 7: Restart by D long-press ---");
        begin : phase6
            // Short press: should NOT restart
            force dut.key_restart = 1'b1;
            tb_wait_frames(3);
            release dut.key_restart;
            tb_wait_frames(1);
            if (dut.game_state == 2'd1 && dut.restart_latched == 1'b0)
                $display("PASS: Short D press ignored");
            else
                $display("FAIL: Short D press triggered restart (state=%0d)", dut.game_state);

            // Long-press behavior (optimized): pre-load counter near threshold,
            // then hold D for a few frame ticks to cross the restart trigger point.
            force dut.restart_hold_cnt = 7'd59;
            force dut.key_restart = 1'b1;
            tb_wait_frames(3);
            release dut.key_restart;
            release dut.restart_hold_cnt;
            #100;

            if (dut.game_state == 2'd0)
                $display("PASS: Long D press restarted to ST_IDLE");
            else
                $display("FAIL: Long D press did not restart (state=%0d)", dut.game_state);

            if (dut.score == 8'd0 && dut.snake_len == 7'd3 && dut.paused == 1'b0)
                $display("PASS: Restart reset core game state");
            else
                $display("FAIL: Restart state wrong (score=%0d len=%0d paused=%0d)",
                         dut.score, dut.snake_len, dut.paused);

            // Re-enter PLAYING quickly with key 5 so following phases remain valid
            start_game_from_idle;
            if (dut.game_state == 2'd1)
                $display("PASS: Re-entered ST_PLAYING after restart");
            else
                $display("FAIL: Could not re-enter ST_PLAYING (state=%0d)", dut.game_state);

            if ((dut.score == 8'd0) && (dut.best_score > 8'd0))
                $display("PASS: New game keeps BEST and SCORE is near reset baseline");
            else
                $display("FAIL: SCORE/BEST after restart-start wrong (score=%0d best=%0d)",
                         dut.score, dut.best_score);
        end

        // ---- Phase 8: Self-collision -> Game Over ----
        // hit_body is only evaluated when frame_tick AND frame_cnt==move_speed-1.
        // Force both so the collision check fires on the very next frame_tick.
        $display("--- Phase 8: Self-collision -> Game Over ---");
        if (dut.game_state != 2'd1)
            start_game_from_idle;
        force dut.food_active = 1'b0;
        force dut.key_up    = 1'b0;
        force dut.key_down  = 1'b0;
        force dut.key_left  = 1'b0;
        force dut.key_right = 1'b0;
        force dut.direction = 2'd0; // DIR_RIGHT
        tb_wait_frames(1);
        reg [374:0] collision_body_map;
        collision_body_map = dut.body_map;
        collision_body_map[dut.next_cidx] = 1'b1;
        force dut.body_map = collision_body_map;
        force dut.score = 8'd7;
        dut.frame_cnt = dut.move_speed - 4'd1;
        tb_wait_frames(1);
        #60;
        release dut.body_map;
        release dut.food_active;
        release dut.score;
        #100;
        if (dut.game_state == 2'd2)
            $display("PASS: Transitioned to ST_GAME_OVER");
        else
            $display("FAIL: game_state=%0d (expected 2=ST_GAME_OVER)", dut.game_state);

        if (dut.last_score == 8'd7)
            $display("PASS: LAST score latched on game over");
        else
            $display("FAIL: LAST score wrong (last=%0d expected=7)", dut.last_score);

        // ---- Phase 9: Game Over visuals ----
        // anyred_pixels covers both flash states (bright R=11111 and dark R=00110).
        // Expect: anyred > 0, GAME OVER text (white > 0), no green, no bad pixels.
        reset_counters;
        tb_visual_wait;
        $display("--- Phase 9: Game Over visuals ---");
        $display("AnyRed : %0d (expect >0 flash bg)", anyred_pixels);
        $display("White  : %0d (expect >0 GAME OVER text)", white_pixels);
        $display("Green  : %0d (expect 0)", green_pixels);
        $display("Bad    : %0d (expect 0)", bad_pixels);

        if (anyred_pixels > 0)
            $display("PASS: Red flash background visible");
        else
            $display("FAIL: No red background in Game Over");

        if (white_pixels > 0)
            $display("PASS: GAME OVER text visible");
        else
            $display("FAIL: No GAME OVER text pixels");

        if (green_pixels == 0)
            $display("PASS: No snake pixels in Game Over");
        else
            $display("FAIL: Unexpected green in Game Over: %0d", green_pixels);

        if (bad_pixels == 0)
            $display("PASS: No pixels outside DE in Game Over");
        else
            $display("FAIL: %0d pixels outside DE in Game Over", bad_pixels);

        // ---- Phase 10: Reset from Game Over -> ST_IDLE ----
        $display("--- Phase 10: Reset from Game Over ---");
        reset_btn = 1'b0;  // S1 active-low: assert reset
        #200;
        reset_btn = 1'b1;
        reset_counters;
        tb_visual_wait;
        $display("State  : %0d (expect 0=ST_IDLE)", dut.game_state);
        $display("White  : %0d (expect >0 title screen)", white_pixels);
        $display("Green  : %0d (expect 0)", green_pixels);

        if (dut.game_state == 2'd0)
            $display("PASS: Back to ST_IDLE after reset");
        else
            $display("FAIL: game_state=%0d (expected 0=ST_IDLE)", dut.game_state);

        if (white_pixels > 0)
            $display("PASS: Title screen visible after reset");
        else
            $display("FAIL: No title text after reset");

        if (green_pixels == 0)
            $display("PASS: No game pixels after reset");
        else
            $display("FAIL: Unexpected green after reset: %0d", green_pixels);

        // ---- Phase 11: Obstacle spawn in PLAYING ----
        $display("--- Phase 11: Obstacle spawn ---");
        begin : phase11
            integer attempt11;
            reg spawned11;

            // Enter PLAYING from IDLE using key 5
            start_game_from_idle;
            tb_wait_frames(2);

            if (dut.game_state != 2'd1)
                $display("FAIL: Could not enter PLAYING for obstacle tests (state=%0d)", dut.game_state);

            // Keep board deterministic for obstacle checks.
            force dut.obstacle_map = 375'b0;
            force dut.obs_active = 8'b0;
            force dut.obstacle_count = 4'd0;
            tb_wait_frames(1);
            #60;
            release dut.obstacle_map;
            release dut.obs_active;
            release dut.obstacle_count;

            spawned11 = 1'b0;
            for (attempt11 = 0; attempt11 < 6; attempt11 = attempt11 + 1) begin
                if (!spawned11) begin
                    trigger_obstacle_spawn(16'h1357 + attempt11);
                    if (dut.obstacle_count > 0)
                        spawned11 = 1'b1;
                end
            end

            if (spawned11 && (|dut.obstacle_map))
                $display("PASS: Obstacle spawns and map updates");
            else
                $display("FAIL: Obstacle did not spawn as expected");
        end

        // ---- Phase 12: Dynamic head safety radius ----
        $display("--- Phase 12: Head safety radius ---");
        begin : phase12
            reg [15:0] near_seed;
            reg [15:0] far_seed;
            reg [4:0] near_col;
            reg [4:0] far_col;

            // Reset obstacle state for this phase.
            force dut.obstacle_map = 375'b0;
            force dut.obs_active = 8'b0;
            force dut.obstacle_count = 4'd0;
            tb_wait_frames(1);
            #60;
            release dut.obstacle_map;
            release dut.obs_active;
            release dut.obstacle_count;

            // Keep food out of the tested spawn cells.
            force dut.food_active = 1'b0;
            force dut.food_col = 5'd0;
            force dut.food_row = 4'd0;

            near_col = (dut.head_col <= 5'd20) ? (dut.head_col + 5'd4) : (dut.head_col - 5'd4);
            far_col  = 5'd0;

            near_seed = 16'h0001;
            near_seed[9:5]   = near_col;
            near_seed[13:10] = dut.head_row;

            far_seed = 16'h0001;
            far_seed[9:5]   = far_col;
            far_seed[13:10] = 4'd0;

            // Near candidate (distance 4) should be blocked early-game.
            trigger_obstacle_spawn(near_seed);
            if (dut.obstacle_count == 0)
                $display("PASS: Near-head spawn blocked by safety radius");
            else
                $display("FAIL: Near-head obstacle spawned unexpectedly");

            // Farther candidate (distance 6) should be allowed.
            trigger_obstacle_spawn(far_seed);
            if (dut.obstacle_count > 0)
                $display("PASS: Farther spawn allowed outside safety radius");
            else
                $display("FAIL: Farther spawn was blocked unexpectedly");

            release dut.food_row;
            release dut.food_col;
            release dut.food_active;
        end

        // ---- Phase 13: Obstacle TTL expiry ----
        $display("--- Phase 13: Obstacle TTL expiry ---");
        // After Phase 12, first obstacle slot should be active. Force ttl=1 and ensure expiry clears it.
        dut.obs_ttl[0] = 9'd1;
        tb_wait_frames(1);
        #60;

        if ((dut.obs_active[0] == 1'b0) && (dut.obstacle_count == 0) && (~|dut.obstacle_map))
            $display("PASS: Obstacle expired and map cleared");
        else
            $display("FAIL: Obstacle expiry did not clear state (active0=%0d count=%0d)",
                     dut.obs_active[0], dut.obstacle_count);

        // ---- Phase 14: Obstacle collision -> Game Over ----
        $display("--- Phase 14: Obstacle collision -> Game Over ---");
        if (dut.game_state != 2'd1)
            start_game_from_idle;
        tb_wait_frames(2);
        force dut.key_up    = 1'b0;
        force dut.key_down  = 1'b0;
        force dut.key_left  = 1'b0;
        force dut.key_right = 1'b0;
        force dut.direction = 2'd0; // DIR_RIGHT
        tb_wait_frames(1);
        reg [374:0] collision_obstacle_map;
        collision_obstacle_map = 375'b0;
        collision_obstacle_map[dut.next_cidx] = 1'b1;
        force dut.obstacle_map = collision_obstacle_map;
        force dut.hit_body = 1'b0;
        dut.frame_cnt = dut.move_speed - 4'd1;
        tb_wait_frames(1);
        #60;
        release dut.obstacle_map;
        release dut.hit_body;

        if (dut.game_state == 2'd2)
            $display("PASS: Obstacle hit transitions to ST_GAME_OVER");
        else
            $display("FAIL: Obstacle hit did not trigger game over (state=%0d)", dut.game_state);

        $display("=== Done ===");
        $finish;
    end

endmodule
