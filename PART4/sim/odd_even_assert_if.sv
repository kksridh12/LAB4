`timescale 1ns/1ps
// interface for the even/odd FIFO.
// Signals are driven by the testbench from the DUT hierarchy.
interface odd_even_assert_if #(parameter int DSIZE = 8) (
    input logic clock,
    input logic reset,
    input logic write_en,
    input logic [DSIZE-1:0] data_in,
    input logic odd_write_en,
    input logic even_write_en,
    input logic odd_read_en,
    input logic even_read_en
);

    // If an odd-valued byte is requested, only the odd FIFO is selected.
    ap_odd_routes_to_odd: assert property (
        @(posedge clock) disable iff (!reset)
        (write_en && data_in[0] === 1'b1)
            |-> (odd_write_en && !even_write_en)
    ) else $error("SVA: odd byte not routed exclusively to odd FIFO");

    // If an even-valued byte is requested, only the even FIFO is selected.
    ap_even_routes_to_even: assert property (
        @(posedge clock) disable iff (!reset)
        (write_en && data_in[0] === 1'b0)
            |-> (even_write_en && !odd_write_en)
    ) else $error("SVA: even byte not routed exclusively to even FIFO");

    // Both parity FIFOs must never be written in the same cycle.
    ap_no_dual_writes: assert property (
        @(posedge clock) disable iff (!reset)
        !(odd_write_en && even_write_en)
    ) else $error("SVA: both FIFO write enables asserted");

    // Read arbitration must never read both parity FIFOs simultaneously.
    ap_no_dual_reads: assert property (
        @(posedge clock) disable iff (!reset)
        !(odd_read_en && even_read_en)
    ) else $error("SVA: both FIFO read enables asserted");

    // With no write request, neither internal FIFO may be selected for writing.
    ap_no_write_without_request: assert property (
        @(posedge clock) disable iff (!reset)
        !write_en |-> (!odd_write_en && !even_write_en)
    ) else $error("SVA: internal write enable without external request");

    // Any internal write request must correspond to an external write request.
    ap_write_en_source: assert property (
        @(posedge clock) disable iff (!reset)
        (odd_write_en || even_write_en) |-> write_en
    ) else $error("SVA: stray internal FIFO write enable");

endinterface
