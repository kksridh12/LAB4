

// Description - 
// Synchronizes the write pointer from the write clock domain into the read
// clock domain. The pointer is Gray-coded so only one bit changes per step,
// limiting the effect of sampling it while it is changing.
module sync_w2r #(parameter ADDRSIZE = 4,
                  parameter ASYNC = 1)
 (
   // Two-stage synchronized write pointer used by read-domain flag logic.
    output logic [ADDRSIZE:0] rq2_wptr,
   // Gray-coded write pointer produced in the write clock domain.
    input  logic [ADDRSIZE:0] wptr,
    input  logic              rclk,
   // Active-low asynchronous reset for the read clock domain.
    input  logic              rrst_n);
    
   if (ASYNC) begin : gen_async
      // First stage may become metastable; the second stage provides the
      // stable pointer value consumed by the read-domain logic.
       logic [ADDRSIZE:0] rq1_wptr;
       
       always_ff @(posedge rclk or negedge rrst_n)
         // Reset both synchronizer stages so the read domain starts with a
         // zero write-pointer value.
          if (!rrst_n) {rq2_wptr,rq1_wptr} <= 0;
          else         {rq2_wptr,rq1_wptr} <= {rq1_wptr,wptr};
   
   end
   else begin
       assign rq2_wptr = wptr;
   end

endmodule