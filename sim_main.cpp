// Verilator + SDL2 testbench for Snake Game
// 800x480 VGA output — Arrow keys, Space=pause, R=restart, ESC=quit
//
// Performance strategy:
//   - Inner loop runs BATCH_CYCLES full clocks before touching SDL
//   - Keypad driven between falling/rising edges (correct setup time)
//   - Pixel buffer written only when LCD_DEN is high
//   - SDL_RenderPresent called ONCE per frame on vsync rising edge (0->1)
//   - No VCD tracing

#include <SDL2/SDL.h>
#include <verilated.h>
#include "Vsnake_top.h"
#include <cstdio>

static constexpr int H_ACTIVE    = 800;
static constexpr int V_ACTIVE    = 480;
static constexpr int BATCH_CYCLES = 512;   // full clk cycles per batch

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    auto* top = new Vsnake_top;

    // ---- SDL2 init ----
    if (SDL_Init(SDL_INIT_VIDEO) < 0) {
        fprintf(stderr, "SDL_Init failed: %s\n", SDL_GetError());
        return 1;
    }
    SDL_Window* window = SDL_CreateWindow(
        "Snake FPGA Sim", SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
        H_ACTIVE, V_ACTIVE, SDL_WINDOW_SHOWN);
    SDL_Renderer* renderer = SDL_CreateRenderer(
        window, -1, SDL_RENDERER_ACCELERATED);
    SDL_Texture* texture = SDL_CreateTexture(
        renderer, SDL_PIXELFORMAT_RGB888, SDL_TEXTUREACCESS_STREAMING,
        H_ACTIVE, V_ACTIVE);

    // Pixel buffer — written during active display, presented on vsync
    uint32_t framebuf[H_ACTIVE * V_ACTIVE];

    // ---- Key state ----
    bool key_up = false, key_down = false, key_left = false, key_right = false;
    bool key_pause = false, key_restart = false;

    // ---- Reset (100 full cycles) ----
    top->clk = 0;
    top->reset_btn = 0;   // active-low: 0 = asserted
    top->KEY_COL   = 0;
    for (int i = 0; i < 200; i++) {
        top->clk = !top->clk;
        top->eval();
    }
    top->reset_btn = 1;   // release

    bool running    = true;
    bool frame_ready = false;
    bool prev_vs    = true;     // vsync idles high
    int  px = 0, py = 0;       // pixel position tracker

    while (running) {
        // ---- Tight simulation batch ----
        for (int cyc = 0; cyc < BATCH_CYCLES; cyc++) {

            // -- Falling edge --
            top->clk = 0;
            top->eval();

            // Drive keypad between edges so KEY_COL has correct
            // setup time before the next rising edge samples it.
            uint8_t row = top->KEY_ROW;
            uint8_t col = 0;
            if ((row & 1) && key_up)      col |= 0x02;  // ROW0: 2=UP   -> COL1
            if ((row & 2) && key_left)    col |= 0x01;  // ROW1: 4=LEFT -> COL0
            if ((row & 2) && key_pause)   col |= 0x02;  //       5=PAUSE-> COL1
            if ((row & 2) && key_right)   col |= 0x04;  //       6=RIGHT-> COL2
            if ((row & 4) && key_down)    col |= 0x02;  // ROW2: 8=DOWN -> COL1
            if ((row & 8) && key_restart) col |= 0x08;  // ROW3: D=RST  -> COL3
            top->KEY_COL = col;

            // -- Rising edge --
            top->clk = 1;
            top->eval();

            // -- Capture pixel when display is active --
            if (top->LCD_DEN) {
                if (px < H_ACTIVE && py < V_ACTIVE) {
                    uint8_t r = (top->LCD_R << 3) | (top->LCD_R >> 2);
                    uint8_t g = (top->LCD_G << 2) | (top->LCD_G >> 4);
                    uint8_t b = (top->LCD_B << 3) | (top->LCD_B >> 2);
                    framebuf[py * H_ACTIVE + px] = (r << 16) | (g << 8) | b;
                }
                px++;
            } else if (px > 0) {
                // First inactive pixel after an active line -> next row
                py++;
                px = 0;
            }

            // -- Vsync rising edge (0 -> 1) = frame complete --
            bool vs = top->LCD_VSYNC;
            if (!prev_vs && vs) {
                frame_ready = true;
                px = 0;
                py = 0;
            }
            prev_vs = vs;
        }

        // ---- Present frame (only on vsync, ~60 times/sec simulated) ----
        if (frame_ready) {
            SDL_UpdateTexture(texture, nullptr, framebuf,
                              H_ACTIVE * sizeof(uint32_t));
            SDL_RenderCopy(renderer, texture, nullptr, nullptr);
            SDL_RenderPresent(renderer);
            frame_ready = false;
        }

        // ---- Poll SDL events (once per batch) ----
        SDL_Event ev;
        while (SDL_PollEvent(&ev)) {
            if (ev.type == SDL_QUIT) {
                running = false;
            } else if (ev.type == SDL_KEYDOWN || ev.type == SDL_KEYUP) {
                bool pressed = (ev.type == SDL_KEYDOWN);
                switch (ev.key.keysym.sym) {
                    case SDLK_UP:     key_up      = pressed; break;
                    case SDLK_DOWN:   key_down    = pressed; break;
                    case SDLK_LEFT:   key_left    = pressed; break;
                    case SDLK_RIGHT:  key_right   = pressed; break;
                    case SDLK_SPACE:  key_pause   = pressed; break;
                    case SDLK_r:      key_restart = pressed; break;
                    case SDLK_ESCAPE: running     = false;   break;
                }
            }
        }
    }

    // ---- Cleanup ----
    delete top;
    SDL_DestroyTexture(texture);
    SDL_DestroyRenderer(renderer);
    SDL_DestroyWindow(window);
    SDL_Quit();
    return 0;
}
