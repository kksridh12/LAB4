`timescale 1ns/1ps

// assertions for the Lab 1 even/odd FIFO.
// The testbench connects internal DUT signals using hierarchical references.
interface odd_even_assert_if #(parameter int DSIZE = 8) (
    input logic clock,
    input logic reset,  // Active-low reset (0 = reset asserted)
    input logic write_en,
    input logic [DSIZE-1:0] data_in,
    input logic odd_write_en,
    input logic even_write_en,
    input logic odd_read_en,
    input logic even_read_en,
    input logic odd_rempty,
    input logic even_rempty
);
    // A1: An odd-valued write must select only the odd FIFO.
    ap_odd_routes_to_odd: assert property (
        @(posedge clock) disable iff (!reset)
        (write_en && (data_in[0] === 1'b1))
        |-> (odd_write_en && !even_write_en)
    ) else $error("SVA FAIL A1: odd input not routed exclusively to odd FIFO");

    // A2: An even-valued write must select only the even FIFO.
    ap_even_routes_to_even: assert property (
        @(posedge clock) disable iff (!reset)
        (write_en && (data_in[0] === 1'b0))
        |-> (even_write_en && !odd_write_en)
    ) else $error("SVA FAIL A2: even input not routed exclusively to even FIFO");

    // A3: The two sub-FIFOs must never receive writes simultaneously.
    ap_no_dual_writes: assert property (
        @(posedge clock) disable iff (!reset)
        !(odd_write_en && even_write_en)
    ) else $error("SVA FAIL A3: both FIFO write enables asserted");

    // A4: The read arbitration must never read both sub-FIFOs at once.
    ap_no_dual_reads: assert property (
        @(posedge clock) disable iff (!reset)
        !(odd_read_en && even_read_en)
    ) else $error("SVA FAIL A4: both FIFO read enables asserted");

    // A5: No internal FIFO write may occur without an external write request.
    ap_no_write_without_request: assert property (
        @(posedge clock) disable iff (!reset)
        !write_en |-> (!odd_write_en && !even_write_en)
    ) else $error("SVA FAIL A5: internal write with no external write request");

    // A6: Active-low reset clears the registered read enables.
    // Do NOT use disable iff (!reset) for this property: reset is the condition tested.
    ap_reset_clears_reads: assert property (
        @(posedge clock)
        !reset |-> (!odd_read_en && !even_read_en)
    ) else $error("SVA FAIL A6: read enables not cleared during reset");

    // A7: Do not read odd FIFO twice consecutively
    // when the even FIFO has data.
    ap_no_back_to_back_odd: assert property (
        @(posedge clock) disable iff (!reset)
        (odd_read_en && !even_rempty)
        |=> !odd_read_en
    ) else $error("SVA FAIL A7: back-to-back odd reads");

    // A8: Do not read even FIFO twice consecutively
    // when the odd FIFO has data.
    ap_no_back_to_back_even: assert property (
        @(posedge clock) disable iff (!reset)
        (even_read_en && !odd_rempty)
        |=> !even_read_en
    ) else $error("SVA FAIL A8: back-to-back even reads");

endinterface
