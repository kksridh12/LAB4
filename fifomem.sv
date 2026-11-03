

module fifomem #(parameter DATASIZE = 8, // Memory data word width
                 parameter ADDRSIZE = 4) // Number of mem address bits
(
    mem_itf.mem_witf mem_witf,
    mem_itf.mem_ritf mem_ritf
);
    `ifdef VENDORRAM
       // instantiation of a vendor's dual-port RAM
       vendor_ram mem (.dout(mem_ritf.rdata), .din(mem_witf.wdata),
       .waddr(mem_witf.waddr), .raddr(mem_ritf.raddr),
       .wclken(mem_witf.winc),
       .wclken_n(mem_witf.wfull), .clk(mem_witf.wclk));
    `else
       // RTL Verilog memory model
       localparam DEPTH = 1<<ADDRSIZE;
       logic [DATASIZE-1:0] mem [0:DEPTH-1];
       assign mem_ritf.rdata = mem[mem_ritf.raddr];
       always_ff @(posedge mem_witf.wclk)
          if (mem_witf.winc && !mem_witf.wfull) mem[mem_witf.waddr] <= mem_witf.wdata;
    `endif
endmodule