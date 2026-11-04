// fifo_checker.sv
// ------------------------------------------------------------
// Checker for the async FIFO using the DPI-C golden model in
// fifo_model.c (same pattern as the checker in dpi_2.sv).
//
// On every clock edge, for each domain:
//   1. Sample the DUT pins just before the edge (clocking block, #1step).
//   2. Compare the DUT flags (and rdata on an accepted read) with the model.
//   3. Step the model with the sampled inputs.
//
// The C model holds one FIFO, so use one checker per simulation.
//
// Hook-up example (in the testbench, next to the DUT):
//   fifo_checker #(DSIZE, ASIZE, ASYNC) u_chk (.*);
//
// Build:
//   vcs -sverilog <tb + rtl files> fifo_checker.sv fifo_model.c
// ------------------------------------------------------------

import "DPI-C" function void fifo_init(input int asize, input int async_mode);
import "DPI-C" function void fifo_wreset();
import "DPI-C" function void fifo_rreset();
import "DPI-C" function int  fifo_write(input int t, input int winc, input int wdata);
import "DPI-C" function int  fifo_read (input int t, input int rinc);
import "DPI-C" function int  fifo_wfull();
import "DPI-C" function int  fifo_almost_wfull();
import "DPI-C" function int  fifo_rempty();
import "DPI-C" function int  fifo_almost_rempty();
import "DPI-C" function int  fifo_rdata();
import "DPI-C" function int  fifo_count();

module fifo_checker #(parameter DSIZE = 8,
                      parameter ASIZE = 4,
                      parameter ASYNC = 1)
(
    input logic             wclk,
    input logic             wrst_n,
    input logic             winc,
    input logic [DSIZE-1:0] wdata,
    input logic             wfull,
    input logic             almost_wfull,
    input logic             rclk,
    input logic             rrst_n,
    input logic             rinc,
    input logic [DSIZE-1:0] rdata,
    input logic             rempty,
    input logic             almost_rempty
);

    int errors = 0;
    int writes = 0;
    int reads  = 0;

    initial fifo_init(ASIZE, ASYNC);

    final
        $display("[fifo_checker] writes=%0d reads=%0d left=%0d errors=%0d -> %s",
                 writes, reads, fifo_count(), errors, errors ? "FAIL" : "PASS");

    // Sample everything just before the clock edge.
    clocking wcb @(posedge wclk);
        default input #1step;
        input wrst_n, winc, wdata, wfull, almost_wfull;
    endclocking

    clocking rcb @(posedge rclk);
        default input #1step;
        input rrst_n, rinc, rdata, rempty, almost_rempty;
    endclocking

    // Asynchronous resets
    always @(negedge wrst_n) fifo_wreset();
    always @(negedge rrst_n) fifo_rreset();

    // Based on the sampled values, check the DUT write flags.
    always @(wcb) begin
        if (wcb.wrst_n !== 1'b1) begin
            fifo_wreset();
        end
        else begin
            if (wcb.wfull !== fifo_wfull()) begin
                errors++;
                $error("[%0t] wfull: DUT=%b model=%0d (count=%0d)", $time, wcb.wfull, fifo_wfull(), fifo_count());
            end
            if (wcb.almost_wfull !== fifo_almost_wfull()) begin
                errors++;
                $error("[%0t] almost_wfull: DUT=%b model=%0d (count=%0d)", $time, wcb.almost_wfull, fifo_almost_wfull(), fifo_count());
            end
            if (fifo_write($time, wcb.winc === 1'b1, wcb.wdata))
                writes++;
        end
    end

    // Based on the sampled values, check the DUT read flags.
    always @(rcb) begin
        if (rcb.rrst_n !== 1'b1) begin
            fifo_rreset();
        end
        else begin
            if (rcb.rempty !== fifo_rempty()) begin
                errors++;
                $error("[%0t] rempty: DUT=%b model=%0d (count=%0d)", $time, rcb.rempty, fifo_rempty(), fifo_count());
            end
            if (rcb.almost_rempty !== fifo_almost_rempty()) begin
                errors++;
                $error("[%0t] almost_rempty: DUT=%b model=%0d (count=%0d)", $time, rcb.almost_rempty, fifo_almost_rempty(), fifo_count());
            end
            if (fifo_read($time, rcb.rinc === 1'b1)) begin
                reads++;
                if (rcb.rdata !== fifo_rdata()) begin
                    errors++;
                    $error("[%0t] rdata: DUT=%h model=%h", $time, rcb.rdata, fifo_rdata());
                end
            end
        end
    end

endmodule
