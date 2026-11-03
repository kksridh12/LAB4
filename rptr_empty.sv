

// Description - 
// Read-pointer controller for the asynchronous FIFO.
// Maintains the binary and Gray-coded read pointers, generates the memory
// read address, and registers empty and almost-empty status in the read
// clock domain using the synchronized write pointer.
module rptr_empty #(parameter ADDRSIZE = 4)
(
    // Read-domain empty status and memory address outputs.
    output logic                rempty,
    output logic                almost_rempty,
    output logic [ADDRSIZE-1:0] raddr,
    output logic [ADDRSIZE :0]  rptr,
    input  logic [ADDRSIZE :0]  rq2_wptr,
    input  logic                rinc,
    input  logic                rclk,
    input  logic                rrst_n);
    
    logic [ADDRSIZE:0] rbin;
    logic [ADDRSIZE:0] wptr_bin;
    logic [ADDRSIZE:0] rgraynext, rbinnext;
    logic rempty_val;
    logic almost_rempty_val;
    
    // Threshold used to assert the almost-empty indication.
    localparam logic [ADDRSIZE:0] ALMOST = (ADDRSIZE == 2) ? 1 : ((1 << ADDRSIZE) / 4);
    //-------------------
    // Register the binary and Gray read pointers in the read clock domain.
    //-------------------
    always_ff @(posedge rclk or negedge rrst_n)
       if (!rrst_n) {rbin, rptr} <= 0;
       else         {rbin, rptr} <= {rbinnext, rgraynext};
    
    // Generate the next read pointer and its Gray-code representation.
    // The binary pointer indexes memory; the Gray pointer crosses clock domains.
    always_comb begin
        raddr     = rbin[ADDRSIZE-1:0];
        rbinnext  = rbin + (rinc & ~rempty);
        rgraynext = (rbinnext>>1) ^ rbinnext;
    end
    
    // Convert the synchronized write Gray pointer to binary for distance checks.
    // Gray-code values cannot be ordered numerically, so the almost-empty
    // threshold is evaluated using the binary pointer distance instead.
    always_comb 
    begin
        wptr_bin = '0;
        wptr_bin[ADDRSIZE] = rq2_wptr[ADDRSIZE];
        for (int i = ADDRSIZE - 1; i >= 0; i--) begin
            wptr_bin[i] = wptr_bin[i + 1] ^ rq2_wptr[i];
        end
    end
    // The FIFO is empty when the next read pointer catches the synchronized
    // write pointer. The look-ahead comparison also drives almost-empty.
    // EMPTY flag asserts when Write pointer and read pointer coincide.
    // Almost-empty uses the next read pointer, so the flag reflects the
    // occupancy after a read accepted on the current clock edge.
    always_comb begin
        rempty_val        = (rgraynext == rq2_wptr);
        // Pointer subtraction is modulo 2**(ADDRSIZE+1), which handles wraparound.
        almost_rempty_val = (wptr_bin - rbinnext) <= ALMOST;
    end

    // Empty flags are registered in the read clock domain.
    always_ff @(posedge rclk or negedge rrst_n)
       if (!rrst_n) {rempty, almost_rempty} <= {1'b1, 1'b1};
       else         {rempty, almost_rempty} <= {rempty_val, almost_rempty_val};

endmodule