

// Description - 
// Synchronizes the read pointer from the read clock domain into the write
// clock domain. The pointer is Gray-coded so only one bit changes per step,
// limiting the effect of sampling it while it is changing.

module sync_r2w #(parameter ADDRSIZE = 4,
                  parameter ASYNC = 1)
(
    // Two-stage synchronized read pointer used by write-domain flag logic.
    output logic [ADDRSIZE:0] wq2_rptr,
    // Gray-coded read pointer produced in the read clock domain.
    input  logic [ADDRSIZE:0] rptr,
    input  logic              wclk,
    // Active-low asynchronous reset for the write clock domain.
    input  logic              wrst_n);
    
    if (ASYNC) begin : gen_async
    // First stage may become metastable; the second stage provides the
    // stable pointer value consumed by the write-domain logic.
    logic [ADDRSIZE:0] wq1_rptr;
    
    always_ff @(posedge wclk or negedge wrst_n)
       // Reset both synchronizer stages so the write domain starts with an
       // empty read-pointer value.
       if (!wrst_n) {wq2_rptr,wq1_rptr} <= 0;
       else         {wq2_rptr,wq1_rptr} <= {wq1_rptr,rptr};

    end
    else begin
        assign wq2_rptr = rptr;
    end
endmodule