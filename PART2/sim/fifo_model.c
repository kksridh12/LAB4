// fifo_model.c
// ------------------------------------------------------------
// Golden reference model for the async FIFO, called from
// SystemVerilog through DPI-C (same style as dpi.c).
//
// The model keeps its own copy of the FIFO state and is stepped
// once per clock edge from fifo_checker.sv:
//   posedge wclk -> fifo_write(...)
//   posedge rclk -> fifo_read(...)
// The checker compares the DUT flags / rdata with the getters below.
//
// Pointers are kept as plain binary counters from 0 to 2*DEPTH-1.
// (The RTL uses Gray code only so the pointer can cross clock
// domains safely; the C model does not need that.)
//
// Build: vcs -sverilog <tb + rtl files> fifo_checker.sv fifo_model.c
// ------------------------------------------------------------

#include <stdio.h>

#define MAX_DEPTH 1024

// ---------------- configuration ----------------
int DEPTH;       // number of words = 2^ASIZE
int ALMOST;      // almost-full / almost-empty threshold
int PTR_RANGE;   // pointers count 0 .. 2*DEPTH-1
int ASYNC_MODE;  // 1 = two-flop synchronizers, 0 = direct connection

int mem[MAX_DEPTH];

// ---------------- write clock domain ----------------
int wbin;            // write pointer
int wbin_old;        // write pointer before its last update
long long wbin_time; // sim time of the last update
int wq1_rptr;        // read pointer, synchronizer stage 1
int wq2_rptr;        // read pointer, synchronizer stage 2
int wfull;
int almost_wfull;

// ---------------- read clock domain ----------------
int rbin;
int rbin_old;
long long rbin_time;
int rq1_wptr;
int rq2_wptr;
int rempty;
int almost_rempty;
int rdata_exp;       // data the DUT should show on the last accepted read

// Number of words between two pointers (handles wrap-around).
int distance(int from, int to) {
    return (to - from + PTR_RANGE) % PTR_RANGE;
}

// ---------------- resets ----------------

void fifo_wreset() {
    wbin = 0;
    wbin_old = 0;
    wbin_time = -1;
    wq1_rptr = 0;
    wq2_rptr = 0;
    wfull = 0;
    almost_wfull = 0;
}

void fifo_rreset() {
    rbin = 0;
    rbin_old = 0;
    rbin_time = -1;
    rq1_wptr = 0;
    rq2_wptr = 0;
    rempty = 1;
    almost_rempty = 1;
    rdata_exp = 0;
}

// Call once at the start of simulation.
void fifo_init(int asize, int async_mode) {
    DEPTH = 1 << asize;
    if (DEPTH > MAX_DEPTH) {
        printf("fifo_init: ASIZE=%d is too large for MAX_DEPTH\n", asize);
        DEPTH = MAX_DEPTH;
    }
    if (asize == 2)
        ALMOST = 1;
    else
        ALMOST = DEPTH / 4;
    PTR_RANGE = 2 * DEPTH;
    ASYNC_MODE = async_mode;
    fifo_wreset();
    fifo_rreset();
}

// When both clocks rise at the same time, the RTL flops see the other
// domain's pointer from BEFORE the edge. These two helpers return that
// value no matter which of fifo_write / fifo_read is called first.
int rptr_seen_by_write(long long t) {
    if (rbin_time == t)
        return rbin_old;
    return rbin;
}

int wptr_seen_by_read(long long t) {
    if (wbin_time == t)
        return wbin_old;
    return wbin;
}

// ---------------- posedge wclk ----------------
// winc/wdata are the values just before the edge.
// Returns 1 if the write was accepted.
int fifo_write(long long t, int winc, int wdata) {
    int rptr_now = rptr_seen_by_write(t);
    int rptr_used;      // read pointer the flag logic sees
    int accepted = 0;
    int wbin_next;

    if (ASYNC_MODE)
        rptr_used = wq2_rptr;
    else
        rptr_used = rptr_now;

    if (winc && !wfull) {
        accepted = 1;
        mem[wbin % DEPTH] = wdata;
    }

    wbin_next = (wbin + accepted) % PTR_RANGE;

    // Flags, registered on this edge
    wfull        = (distance(rptr_used, wbin_next) == DEPTH);
    almost_wfull = (distance(rptr_used, wbin_next) >= DEPTH - ALMOST);

    // Synchronizer shift
    wq2_rptr = wq1_rptr;
    wq1_rptr = rptr_now;

    // Update the pointer (remember the old value for same-time readers)
    wbin_old = wbin;
    wbin = wbin_next;
    wbin_time = t;

    return accepted;
}

// ---------------- posedge rclk ----------------
// rinc is the value just before the edge.
// Returns 1 if the read was accepted; fifo_rdata() then gives the
// word the DUT should have had on rdata.
int fifo_read(long long t, int rinc) {
    int wptr_now = wptr_seen_by_read(t);
    int wptr_used;
    int accepted = 0;
    int rbin_next;

    if (ASYNC_MODE)
        wptr_used = rq2_wptr;
    else
        wptr_used = wptr_now;

    if (rinc && !rempty) {
        accepted = 1;
        rdata_exp = mem[rbin % DEPTH];
    }

    rbin_next = (rbin + accepted) % PTR_RANGE;

    rempty        = (rbin_next == wptr_used);
    almost_rempty = (distance(rbin_next, wptr_used) <= ALMOST);

    rq2_wptr = rq1_wptr;
    rq1_wptr = wptr_now;

    rbin_old = rbin;
    rbin = rbin_next;
    rbin_time = t;

    return accepted;
}

// ---------------- getters ----------------
int fifo_wfull()         { return wfull; }
int fifo_almost_wfull()  { return almost_wfull; }
int fifo_rempty()        { return rempty; }
int fifo_almost_rempty() { return almost_rempty; }
int fifo_rdata()         { return rdata_exp; }
int fifo_count()         { return distance(rbin, wbin); }  // true number of words stored
