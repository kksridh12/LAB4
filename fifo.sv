

interface mem_itf #(
    parameter DSIZE = 8,
    parameter ASIZE = 4
)
(); 
    // Shared memory signals. Write-side controls and addresses
    // are driven by the FIFO's write-pointer logic; read data is returned
    // from the memory using the read address.
    logic [DSIZE-1:0]    rdata;
    logic [ASIZE-1:0]    waddr;
    logic [ASIZE-1:0]    raddr;
    logic                wfull;
    logic [DSIZE-1:0]    wdata;
    logic                winc;
    logic                wclk;
    logic                wrst_n;

    // Memory write view: the memory receives write data, address, enable,
    // and clock, and returns the full status used to block writes.
    modport mem_witf (
        output            wfull,
        input             wdata,
        input             waddr,
        input             winc,
        input             wclk
    );

    // Memory read view: the memory receives the read address and returns
    // the corresponding data word.
    modport mem_ritf (
        output            rdata,
        input             raddr
    );

endinterface

module fifo  #(parameter DSIZE = 8,
               parameter ASIZE = 4,
               parameter ASYNC = 1)
 (
    output logic [DSIZE-1:0]    rdata,
    output logic                wfull,
    output logic                almost_wfull,
    output logic                rempty,
    output logic                almost_rempty,
    input  logic [DSIZE-1:0]    wdata,
    input  logic                winc,
    input  logic                wclk,
    input  logic                wrst_n,
    input  logic                rinc,
    input  logic                rclk,
    input  logic                rrst_n);
    
    logic [ASIZE-1:0] waddr, raddr;
    logic [ASIZE:0]   wptr, rptr, wq2_rptr, rq2_wptr;

    // Cross each Gray-coded pointer through a two-stage synchronizer into
    // the opposite clock domain before using it for flag generation.
    sync_r2w #(ASIZE, ASYNC) u_sync_r2w (.*);
    sync_w2r #(ASIZE, ASYNC) u_sync_w2r (.*);

    // The interface keeps the dual-port memory connections grouped by
    // read and write domain while the FIFO exposes the public signals.
    mem_itf #(DSIZE, ASIZE) mem_if ();

    assign mem_if.wdata = wdata;
    assign mem_if.winc  = winc;
    assign mem_if.wclk  = wclk;
    assign wfull        = mem_if.wfull;
    assign rdata        = mem_if.rdata;

    // The memory writes in the write clock domain and reads asynchronously
    // through the registered read address supplied by rptr_empty.
    fifomem #(DSIZE, ASIZE) u_fifomem (.mem_witf(mem_if.mem_witf), .mem_ritf(mem_if.mem_ritf));

    // Read-pointer logic owns the read address and read-domain flags.
    rptr_empty #(ASIZE) u_rptr_empty (.raddr (mem_if.raddr), .*);

    // Write-pointer logic owns the write address and write-domain flags.
    wptr_full #(ASIZE) u_wptr_full ( 
        .waddr (mem_if.waddr),
        .wfull (mem_if.wfull),
        .winc (mem_if.winc), 
        .wclk (mem_if.wclk),
        .*);

endmodule