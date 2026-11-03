
// odd_even
// ------------------------------------------------------------
// This module accepts a byte stream and routes each byte into
// either the odd-byte FIFO or the even-byte FIFO depending on the
// LSB of the input byte. It then reads from the two FIFOs in an
// alternating schedule so that the output stream preserves the
// original odd/even ordering while allowing the same byte value to
// be emitted again when the design chooses to repeat the previous
// byte instead of switching to the opposite parity.
//
// The state machine decides which FIFO contributes the next output
// byte based on the current read enable, queue emptiness, and the
// first-byte selection flags that bias the first valid output.
// ------------------------------------------------------------

module odd_even #(parameter DSIZE = 8,
                  parameter ASIZE = 6,
                  parameter ASYNC = 0) (

    input  logic                clock,
    input  logic                reset,
    input  logic [DSIZE-1:0]    data_in,
    input  logic                write_en,
    input  logic                read_en,
    output logic [DSIZE-1:0]    data_out

);

   // Signals
   logic                 odd_write_en;
   logic                 odd_read_en;
   logic                 odd_wfull;
   logic                 odd_rempty;
   logic [DSIZE-1:0]     odd_rdata;
   logic [DSIZE-1:0]     odd_wdata;
   logic                 even_write_en;
   logic                 even_read_en;
   logic                 even_wfull;
   logic                 even_rempty;   
   logic [DSIZE-1:0]     even_rdata;
   logic [DSIZE-1:0]     even_wdata;
   logic [DSIZE-1:0]  data_out_shdw;

   logic                 odd_first_preflop;
   logic                 even_first_preflop;
   logic                 odd_read_en_preflop;
   logic                 even_read_en_preflop;             
   logic                 odd_first;
   logic                 even_first;

   typedef enum logic [1:0] { IDLE, EVEN, ODD, SPARE } STATE_TYPE;

   STATE_TYPE state, next_state;

   // Route incoming data to the correct sub-FIFO based on parity.
   // The FIFO write enable is asserted only when a valid write is
   // requested and the byte belongs to that parity bucket.
   always_comb begin
      case (data_in[0])
        1'b0 : begin even_wdata = data_in; even_write_en = write_en; odd_wdata = '0; odd_write_en = 1'b0; end
        1'b1 : begin odd_wdata  = data_in; odd_write_en  = write_en; even_wdata = '0; even_write_en = 1'b0; end
        default: begin 
            even_wdata = '0; even_write_en = 1'b0;
            odd_wdata  = '0; odd_write_en  = 1'b0;
        end
      endcase
   end

   // Separate FIFOs store odd and even bytes so the output can be
   // interleaved or repeated without merging the parity groups.
   fifo #(DSIZE, ASIZE, ASYNC) u_odd_fifo  (.wclk(clock), .rclk(clock), 
                                            .rdata(odd_rdata), .wdata(odd_wdata),
                                            .wfull(odd_wfull), .rempty(odd_rempty),
                                            .winc(odd_write_en), .rinc(odd_read_en),
                                            .wrst_n(reset), .rrst_n(reset),
                                            .almost_wfull(), .almost_rempty());

   fifo #(DSIZE, ASIZE, ASYNC) u_even_fifo (.wclk(clock), .rclk(clock), 
                                            .rdata(even_rdata), .wdata(even_wdata),
                                            .wfull(even_wfull), .rempty(even_rempty),
                                            .winc(even_write_en), .rinc(even_read_en),
                                            .wrst_n(reset), .rrst_n(reset),
                                            .almost_wfull(), .almost_rempty());

   // Read arbitration state machine.
   // The current state determines whether the next output should come
   // from the even FIFO or the odd FIFO, while honoring the external
   // read enable and the availability of data in each FIFO.
   // Advance the state only when the next state changes.
   always_ff @(posedge clock or negedge reset)
       if (!reset)                    state <= IDLE;
       else if (state != next_state)  state <= next_state;

   always_comb begin
       // Default all read enables to inactive unless the state machine
       // explicitly chooses a FIFO to advance.
       even_read_en_preflop = 1'b0;
       even_first_preflop = even_first;
       odd_first_preflop  = odd_first;
       odd_read_en_preflop = 1'b0;
       case (state) 
          IDLE:  begin 
                   next_state = IDLE;
                   // when both FIFOs are empty, save which FIFO was written to first.
                   if (even_rempty && odd_rempty) begin
                     if (even_write_en)     even_first_preflop = 1'b1;
                     else if (odd_write_en) odd_first_preflop  = 1'b1;
                   end 
                   // if read_en is available, choose the FIFO which was written to first and transition the SM to the other fifo.
                   else if (read_en & even_first) begin even_first_preflop = 1'b0; even_read_en_preflop = 1'b1; next_state = ODD; end
                   else if (read_en & odd_first)  begin even_first_preflop = 1'b0; odd_read_en_preflop  = 1'b1; next_state = EVEN; end
                 end
           EVEN: begin
                    // if FIFO is not empty and read_en is available , read out data from EVEN FIFO and transition SM to ODD.
                    // Otherwise, stay in EVEN if the ODD FIFO is empty but dont read from the EVEN FIFO. 
                    odd_read_en_preflop = 1'b0;
                    if (read_en & !even_rempty) begin
                       if (!even_read_en) even_read_en_preflop = 1'b1; 
                       else               even_read_en_preflop = 1'b0;
                       if (!odd_rempty)   next_state = ODD;
                       else               next_state = EVEN;
                    end else begin
                       even_read_en_preflop = 1'b0; next_state = EVEN;
                    end
                 end
           ODD:  begin
                    // if FIFO is not empty and read_en is available , read out data from ODD FIFO and transition SM to EVEN.
                    // Otherwise, stay in ODD if the EVEN FIFO is empty but dont read from the ODD FIFO. 
                    even_read_en_preflop = 1'b0;
                    if (read_en & !odd_rempty) begin
                       if (!odd_read_en) odd_read_en_preflop = 1'b1; 
                       else              odd_read_en_preflop = 1'b0;
                       if (!even_rempty) next_state = EVEN;
                       else              next_state = ODD;
                    end else begin
                       odd_read_en_preflop = 1'b0; next_state = ODD;
                    end
                 end
           SPARE  : begin {even_first_preflop, even_read_en_preflop, odd_first_preflop, odd_read_en_preflop} = 4'b0000; next_state = IDLE; end
           default: begin {even_first_preflop, even_read_en_preflop, odd_first_preflop, odd_read_en_preflop} = 4'b0000; next_state = IDLE; end
       endcase
   end

   // Save status flag for identifying which FIFO was written to so that it is the first FIFO read out of 
   // when read_en is available.
   always_ff @( posedge clock or negedge reset )
      if (!reset)   {even_read_en,odd_read_en,odd_first,even_first} <= 4'b0;
      else          {even_read_en,odd_read_en,odd_first,even_first} <= {even_read_en_preflop,odd_read_en_preflop,odd_first_preflop,even_first_preflop};
      
   // Shadow register used to hold the last valid output value when no
   // FIFO is being read in the current cycle.

   always_ff @(posedge clock or negedge reset) 
      if (!reset)            data_out_shdw <= '0;
      else if (even_read_en) data_out_shdw <= even_rdata;
      else if (odd_read_en)  data_out_shdw <= odd_rdata;
      else                   data_out_shdw <= data_out;

   // Drive the output from whichever FIFO is currently selected. If no
   // read is enabled, the previous value is held to maintain the output.
   always_comb begin
      if      (even_read_en) data_out = even_rdata;
      else if (odd_read_en)  data_out = odd_rdata;
      else                   data_out = data_out_shdw;
   end
   
endmodule
