// The whole-machine bench's driver: sim/run_sys.sh builds it.
//   Vtb_top +IMAGE=<hexion.rom> [+DSW=FF4FFF] [+DUMPDIR=<dir> +DUMPFROM=f +DUMPTO=f +DUMPEVERY=n] <frames> <out prefix>
// Environment: SNAPEVERY=n (a picture every n frames), SNAPFRAMES=a,b,c, SCHED=play|test (the scripted inputs, the same as
// tools/lua/dump.lua's), AUDIO=1 (<prefix>.wav, 46,875 Hz mono, the core's 16-bit output), TRACE=1 (a line per frame).
// Pictures are written as <prefix>.f<frame>.ppm (512 x 256): frame f is the picture shown before the vblank that ends it, MAME's
// snapshot of frame f (MAME draws it at that vblank's start). With +VMODE=n, n > 0 (a raster of the picture's own, whose vblank is
// not the game's) a picture is written at its own vblank, as the frame of the game's vblank nearest to it.
#include "Vtb_top.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cstdint>
#include <set>
#include <string>
#include <vector>

static std::set<int> parse_list(const char *s) {
    std::set<int> r;
    if (!s) return r;
    const char *p = s;
    while (*p) { r.insert(atoi(p)); while (*p && *p != ',') p++; if (*p) p++; }
    return r;
}

static const int W = 512, H = 256;

static void write_ppm(const std::string &fn, const std::vector<uint8_t> &fb) {
    FILE *f = fopen(fn.c_str(), "wb");
    if (!f) return;
    fprintf(f, "P6\n%d %d\n255\n", W, H);
    fwrite(fb.data(), 1, fb.size(), f);
    fclose(f);
}

// The scripted inputs, the same as tools/lua/dump.lua's sched(): MAME takes the values set in frame f's frame_done from the vblank
// that ends frame f on, the frame_tick at which `frame` here is f. Bits as MAME's ports (active low): P1 0 left, 1 right, 2 up, 3 down,
// 4 button 1, 5 button 2, 7 start; SYSTEM 0 coin 1.
struct In { uint8_t p1, p2, sys; };
static In sched_in(const char *sched, int f) {
    In in = {0xff, 0xff, 0xf7};
    if (!sched) return in;
    if (!strcmp(sched, "test")) {                          // with the service mode DIP on (+DSW=FF4FFB): the test menu's
        for (int s : {400, 420, 440, 460})                 // MASK ROM CHECK (down four times, start), which reads the tile ROMs
            if (f >= s && f < s + 6) in.p1 &= ~0x08;       // through the f500 window
        if (f >= 500 && f < 506) in.p1 &= ~0x80;
        return in;
    }
    if (f >= 300 && f < 306) in.sys &= ~0x01;              // coin 1
    if (f >= 400 && f < 406) in.p1 &= ~0x80;               // start 1
    if (!strcmp(sched, "play") && f >= 600) {
        if ((f / 10) % 6 == 0) in.p1 &= ~0x10;             // button 1
        if ((f / 10) % 6 == 3) in.p1 &= ~0x20;             // button 2
        if ((f / 45) % 4 == 1) in.p1 &= ~0x01;             // left
        if ((f / 45) % 4 == 3) in.p1 &= ~0x02;             // right
        if ((f / 30) % 5 == 4) in.p1 &= ~0x08;             // down
    }
    return in;
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    std::vector<const char *> pos;
    for (int i = 1; i < argc; i++) if (argv[i][0] != '+') pos.push_back(argv[i]);
    if (pos.size() < 2) { fprintf(stderr, "usage: Vtb_top +IMAGE=<file> <frames> <out prefix>\n"); return 2; }
    int frames = atoi(pos[0]);
    std::string pre = pos[1];
    int snap_every = getenv("SNAPEVERY") ? atoi(getenv("SNAPEVERY")) : 0;
    std::set<int> snaps = parse_list(getenv("SNAPFRAMES"));
    const char *sched = getenv("SCHED");
    bool audio = getenv("AUDIO") && atoi(getenv("AUDIO"));
    bool m263 = false;      // the picture on a raster of its own
    for (int i = 1; i < argc; i++) if (!strncmp(argv[i], "+VMODE=", 7) && atoi(argv[i] + 7) != 0) m263 = true;
    bool trace = getenv("TRACE") && atoi(getenv("TRACE"));

    Vtb_top *top = new Vtb_top;
    std::vector<uint8_t> fb(W * H * 3, 0);
    std::vector<int16_t> wav;
    int x = 0, y = 0, frame = 0;
    bool prev_hb = true, line_had = false, prev_vb = true;
    uint64_t cyc = 0, run_at = 0, ft_at = 0;
    const uint64_t FRAME = 8ull * 768 * 288;
    In in = sched_in(nullptr, 0);
    top->in_p1 = in.p1; top->in_p2 = in.p2; top->in_sys = in.sys;

    top->reset_in = 1;
    for (int i = 0; i < 20; i++) { top->clk = 0; top->eval(); top->clk = 1; top->eval(); }
    top->reset_in = 0;

    while (!Verilated::gotFinish()) {
        bool ce = top->ce_pix;
        bool ft = top->frame_tick;
        top->clk = 0; top->eval();
        top->clk = 1; top->eval();
        cyc++;
        if (!top->running) { run_at = cyc; continue; }
        if (audio && ((cyc - run_at) % 2048) == 0) wav.push_back(top->audio);
        if (ft) {
            if (trace) printf("F %d cyc %llu pc %04x\n", frame, (unsigned long long)(cyc - run_at), top->dbg_pc);
            if ((snap_every && frame % snap_every == 0) || snaps.count(frame))
                write_ppm(pre + ".f" + std::to_string(frame) + ".ppm", fb);
            // frame_done of this frame: MAME's Lua sets the inputs of sched(frame) here
            in = sched_in(sched, frame);
            top->in_p1 = in.p1; top->in_p2 = in.p2; top->in_sys = in.sys;
            frame++;
            if (frame >= frames) break;
        }
        if (ce) {
            // the outputs of this dot appeared at this edge
            bool hb = top->hblank, vb = top->vblank;
            if (m263 && vb && !prev_vb && frame > 0) {
                int f = (cyc - ft_at < FRAME / 2) ? frame - 1 : frame;
                if ((snap_every && f % snap_every == 0) || snaps.count(f)) write_ppm(pre + ".f" + std::to_string(f) + ".ppm", fb);
            }
            prev_vb = vb;
            if (vb) { y = 0; x = 0; line_had = false; }
            else if (!hb) {
                if (x < W && y < H) {
                    uint8_t *p = &fb[(y * W + x) * 3];
                    p[0] = top->r; p[1] = top->g; p[2] = top->b;
                }
                x++; line_had = true;
            } else if (!prev_hb && line_had) { y++; x = 0; line_had = false; }
            prev_hb = hb;
        }
    }
    if (audio) {
        FILE *f = fopen((pre + ".wav").c_str(), "wb");
        if (f) {
            uint32_t n = wav.size() * 2, rate = 46875, br = rate * 2;
            fwrite("RIFF", 1, 4, f); uint32_t v = 36 + n; fwrite(&v, 4, 1, f); fwrite("WAVEfmt ", 1, 8, f);
            v = 16; fwrite(&v, 4, 1, f); uint16_t s = 1; fwrite(&s, 2, 1, f); s = 1; fwrite(&s, 2, 1, f);
            fwrite(&rate, 4, 1, f); fwrite(&br, 4, 1, f); s = 2; fwrite(&s, 2, 1, f); s = 16; fwrite(&s, 2, 1, f);
            fwrite("data", 1, 4, f); fwrite(&n, 4, 1, f); fwrite(wav.data(), 2, wav.size(), f); fclose(f);
        }
    }
    top->final();
    printf("done: %d frames, %llu clocks\n", frame, (unsigned long long)cyc);
    delete top;
    return 0;
}
