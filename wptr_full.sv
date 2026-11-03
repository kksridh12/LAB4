

// Description - 
// Write-pointer controller for the asynchronous FIFO.
// Maintains the binary and Gray-coded write pointers, generates the memory
// write address, and registers full and almost-full status in the write
// clock domain using the synchronized read pointer.
module wptr_full #(parameter ADDRSIZE = 4)
 (
    // Write-domain full status and memory address outputs.
    output logic                wfull,
    output logic                almost_wfull,
    output logic [ADDRSIZE-1:0] waddr,
    output logic [ADDRSIZE :0]  wptr,
    input  logic [ADDRSIZE :0]  wq2_rptr,
    input  logic                winc, 
    input  logic                wclk, 
    input  logic                wrst_n);
    
    logic [ADDRSIZE:0] wbin;
    logic [ADDRSIZE:0] rptr_bin;
    logic [ADDRSIZE:0] wgraynext, wbinnext;
    logic              wfull_val;
    logic              almost_wfull_val;


    // Threshold used to assert the almost-full indication.
    localparam logic [ADDRSIZE:0] ALMOST = (ADDRSIZE == 2) ? 1 : ((1 << ADDRSIZE) / 4);
    
    // Register the binary and Gray write pointers in the write clock domain.
    always_ff @(posedge wclk or negedge wrst_n)
       if (!wrst_n) {wbin, wptr} <= 0;
       else         {wbin, wptr} <= {wbinnext, wgraynext};
    
    // Generate the next write pointer and its Gray-code representation.
    // The binary pointer indexes memory; the Gray pointer crosses clock domains.
    // Generate almost full pointer ALMOST locations from current write pointer. 
    always_comb begin
        waddr     = wbin[ADDRSIZE-1:0];
        wbinnext  = wbin + (winc & ~wfull);
        wgraynext = (wbinnext>>1) ^ wbinnext;
    end
    
    // Convert the synchronized read Gray pointer to binary for almost full computation.
    // The Gray pointer remains useful for CDC, but binary values are required
    // for an ordered occupancy comparison.
    always_comb 
    begin
        rptr_bin = '0;
        rptr_bin[ADDRSIZE] = wq2_rptr[ADDRSIZE];
        for (int i = ADDRSIZE - 1; i >= 0; i--) begin
            rptr_bin[i] = rptr_bin[i + 1] ^ wq2_rptr[i];
        end
    end

    // Full uses the standard Gray-code equality with the two inverted
    // wrap bits. Almost-full uses the next write pointer and modulo binary
    // distance, avoiding incorrect ordering across pointer wraparound.
    always_comb begin
        wfull_val          = (wgraynext == {~wq2_rptr[ADDRSIZE:ADDRSIZE-1], wq2_rptr[ADDRSIZE-2:0]});
        almost_wfull_val   = (wbinnext - rptr_bin >= ((1<<ADDRSIZE) - ALMOST));
    end

    // Full flags are registered in the write clock domain.
    always_ff @(posedge wclk or negedge wrst_n)
       if (!wrst_n) {wfull, almost_wfull} <= {1'b0, 1'b0};
       else         {wfull, almost_wfull} <= {wfull_val, almost_wfull_val};

endmodule