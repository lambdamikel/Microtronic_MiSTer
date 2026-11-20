// Lockstep test: runs a stimulus script on the Verilog board and prints the same
// checkpoint hashes as lockstep.js does on the browser emulator's core.
#include "Vmicrotronic.h"
#include "Vmicrotronic___024root.h"
#include "verilated.h"
#include <cstdio>
#include <cstdint>
#include <cstring>
#include <string>
#include <map>
#include <fstream>
#include <sstream>

static Vmicrotronic *t;
static uint64_t steps = 0;
static uint32_t h = 2166136261u;
static inline void fnv(uint32_t &x, unsigned v) { x ^= (v & 255); x *= 16777619u; }

static void tick() { t->clk = 0; t->eval(); t->clk = 1; t->eval(); }

#define R(n) t->rootp->microtronic__DOT__cpu__DOT__##n
static void step() {
	t->step = 1; tick(); t->step = 0; tick(); tick(); tick(); tick();
	steps++;
	unsigned rr = t->r;
	unsigned v[] = { R(pc), R(pa), R(pb), R(ca), R(cb), R(x), R(y), R(a), R(s), R(sl), t->o, rr & 255, rr >> 8 };
	for (unsigned x : v) fnv(h, x);
}
static void check() {
	uint32_t hr = 2166136261u, hs = 2166136261u;
	for (int i = 0; i < 128; i++) fnv(hr, R(ram)[i]);
	auto &b0 = t->rootp->microtronic__DOT__bank0, &b1 = t->rootp->microtronic__DOT__bank1,
	     &b2 = t->rootp->microtronic__DOT__bank2, &b3 = t->rootp->microtronic__DOT__bank3;
	for (int i = 0; i < 1024; i++) {
		int b = i >> 8, a = i & 255;
		fnv(hs, b == 0 ? b0[a] : b == 1 ? b1[a] : b == 2 ? b2[a] : b3[a]);
	}
	printf("chk %llu %08x %08x %08x\n", (unsigned long long)steps, h, hr, hs);
}

static std::map<std::string, int> KEY = {
	{"0",0},{"1",4},{"2",8},{"3",12},{"CCE",16},{"PGM",20},
	{"4",1},{"5",5},{"6",9},{"7",13},{"RUN",17},{"HALT",21},
	{"8",2},{"9",6},{"A",10},{"B",14},{"BKP",18},{"STEP",22},
	{"C",3},{"D",7},{"E",11},{"F",15},{"NEXT",19},{"REG",23}};

int main(int argc, char **argv) {
	Verilated::commandArgs(argc, argv);
	t = new Vmicrotronic;
	t->reset = 1; tick(); tick(); t->reset = 0; tick();
	std::ifstream f(argv[1]); std::string line;
	unsigned keys = 0;
	while (std::getline(f, line)) {
		std::istringstream ss(line); std::string op; ss >> op;
		if (op == "run") { long n, every = 0; ss >> n >> every;
			for (long i = 0; i < n; i++) { step(); if (every && steps % every == 0) check(); } }
		else if (op == "down") { std::string k; ss >> k; keys |= 1u << KEY.at(k); t->keys = keys; }
		else if (op == "up")   { std::string k; ss >> k; keys &= ~(1u << KEY.at(k)); t->keys = keys; }
		else if (op == "din")  { int v; ss >> v; t->din = v; }
		else if (op == "clock") { int v; ss >> v; t->clock_in = v; }
		else if (op == "patch") { int o, i; ss >> o >> i; t->patch = t->patch | (1u << (o * 4 + i)); }
		else if (op == "unpatch") { t->patch = 0; }
		else if (op == "load") { unsigned a; ss >> std::hex >> a; unsigned w;
			while (ss >> std::hex >> w) { t->ld_addr = a++; t->ld_word = w; t->ld_we = 1; tick(); t->ld_we = 0; } tick(); }
		else if (op == "reset") { t->reset = 1; tick(); t->reset = 0; tick(); }
		else if (op == "check") check();
	}
	check();
	delete t;
	return 0;
}
