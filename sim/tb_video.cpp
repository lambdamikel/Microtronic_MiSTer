// Runs a scenario on board + video and writes frames as PPM.
// Extra ops: "mic <file>" streams a .MIC file through the hardware loader, "frame <out.ppm>",
// "red <0-3>" holds the red keys, "speed <n>" a step every n clocks (default 6; 600 is the original speed), "sramhash" prints the 2114 hash (to compare loader vs. JS writeWord).
#include "Vsim_top.h"
#include "Vsim_top___024root.h"
#include "verilated.h"
#include <cstdio>
#include <cstdint>
#include <string>
#include <map>
#include <vector>
#include <fstream>
#include <sstream>
static Vsim_top *t;
static uint64_t steps = 0;
static int phase = 0, every = 6;
static void tick() {               // one clock; a step every 6 clocks ("speed 600" = the original speed at 50 MHz)
	t->step = (++phase % every) == 0;
	t->clk = 0; t->eval(); t->clk = 1; t->eval();
	if (t->executed) steps++;
}
static std::map<std::string, int> KEY = {
	{"0",0},{"1",4},{"2",8},{"3",12},{"CCE",16},{"PGM",20},{"4",1},{"5",5},{"6",9},{"7",13},{"RUN",17},{"HALT",21},
	{"8",2},{"9",6},{"A",10},{"B",14},{"BKP",18},{"STEP",22},{"C",3},{"D",7},{"E",11},{"F",15},{"NEXT",19},{"REG",23}};
static void frame(const char *fn) {
	while (!t->VBlank) tick();
	while (t->VBlank) tick();                     // first visible line
	std::vector<uint8_t> img; img.reserve(640 * 480 * 3);
	while (img.size() < 640 * 480 * 3) {
		tick();
		if (t->ce_pix) {                          // outputs registered on ce: sample on the next ce
		}
		static int last = 0;
		if (t->ce_pix == 0 && last == 1) { if (!t->HBlank && !t->VBlank) { img.push_back(t->R); img.push_back(t->G); img.push_back(t->B); } }
		last = t->ce_pix;
	}
	FILE *f = fopen(fn, "wb"); fprintf(f, "P6\n640 480\n255\n"); fwrite(img.data(), 1, img.size(), f); fclose(f);
	printf("frame %s at step %llu\n", fn, (unsigned long long)steps);
}
int main(int argc, char **argv) {
	Verilated::commandArgs(argc, argv);
	t = new Vsim_top;
	t->reset = 1; tick(); tick(); t->reset = 0;
	std::ifstream f(argv[1]); std::string line; unsigned keys = 0;
	while (std::getline(f, line)) {
		std::istringstream ss(line); std::string op; ss >> op;
		if (op == "run") { long n; ss >> n; uint64_t end = steps + n; while (steps < end) tick(); }
		else if (op == "down") { std::string k; ss >> k; keys |= 1u << KEY.at(k); t->keys = keys; }
		else if (op == "up")   { std::string k; ss >> k; keys &= ~(1u << KEY.at(k)); t->keys = keys; }
		else if (op == "din")  { int v; ss >> v; t->din = v; }
		else if (op == "red")  { int v; ss >> v; t->redkeys = v; }
		else if (op == "clock") { int v; ss >> v; t->clock_in = v; }
		else if (op == "speed") { ss >> every; }
		else if (op == "mic") { std::string fn; ss >> fn; std::ifstream m(fn, std::ios::binary);
			std::string data((std::istreambuf_iterator<char>(m)), std::istreambuf_iterator<char>());
			t->dl = 1; tick(); for (unsigned char c : data) { t->dbyte = c; t->wr = 1; tick(); t->wr = 0; tick(); tick(); }
			t->dl = 0; tick(); tick(); }
		else if (op == "frame") { std::string fn; ss >> fn; frame(fn.c_str()); }
		else if (op == "sramhash") { uint32_t h = 2166136261u; auto &r = t->rootp;
			for (int i = 0; i < 1024; i++) { int b = i >> 8, a = i & 255;
				unsigned v = b == 0 ? r->sim_top__DOT__board__DOT__bank0[a] : b == 1 ? r->sim_top__DOT__board__DOT__bank1[a] : b == 2 ? r->sim_top__DOT__board__DOT__bank2[a] : r->sim_top__DOT__board__DOT__bank3[a];
				h ^= v; h *= 16777619u; }
			printf("sram %08x\n", h); }
	}
	delete t; return 0;
}
