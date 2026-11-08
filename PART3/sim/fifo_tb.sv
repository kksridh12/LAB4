

timeunit 1ns;
timeprecision 1ps;

// Define transaction kinds and scoreboard flags for the FIFO testbench.
typedef enum bit { WRITE_TXN, READ_TXN } transaction_kind_t;
typedef enum { WFULL, ALMOST_WFULL, REMPTY, ALMOST_REMPTY } scoreboard_flag_t;

interface dut_wif #(parameter int DSIZE = 8) (input logic clk);
   logic winc;
   logic [DSIZE-1:0] wdata;
   logic wfull;
   logic almost_wfull;
endinterface

interface dut_rif #(parameter int DSIZE = 8) (input logic clk);
   logic rinc;
   logic [DSIZE-1:0] rdata;
   logic rempty;
   logic almost_rempty;
endinterface

//////////////////////
//Transaction
/////////////////////
// A transaction is a single write or read operation, along with the associated
// status flags.  The monitor will create a transaction for each write and read
// operation, and the scoreboard will check the transaction against its expected
// values.
class transaction #(parameter int DSIZE = 8);
	transaction_kind_t kind;
	time timestamp;
	logic winc;
	logic [DSIZE-1:0] wdata;
	logic wfull;
	logic almost_wfull;
	logic rinc;
	logic [DSIZE-1:0] rdata;
	logic rempty;
	logic almost_rempty;

    function new();
    endfunction

endclass
//////////////////////
//Monitor
/////////////////////
class monitor #(parameter int DSIZE = 8);

	virtual dut_wif #(DSIZE) w_vif;
	virtual dut_rif #(DSIZE) r_vif;
	mailbox #(transaction #(DSIZE)) mbx;
	int txn_msg = 0;

	function new(virtual dut_wif #(DSIZE) w_vif, virtual dut_rif #(DSIZE) r_vif);
		this.w_vif = w_vif;
		this.r_vif = r_vif;
    endfunction


	task monitor_write();
        forever begin
			@(posedge w_vif.clk);
			if (w_vif.winc) begin
				transaction #(DSIZE) txn;
				txn = new();
				txn.timestamp = $time;
				txn.kind = WRITE_TXN;
				txn.winc = w_vif.winc;
				txn.wdata = w_vif.wdata;
				txn.wfull = w_vif.wfull;
				txn.almost_wfull = w_vif.almost_wfull;
				if (txn_msg == 2) begin
					$display("[%0t] Monitor posted WRITE transaction: winc=%b wdata=%h wfull=%b almost_wfull=%b",
					         txn.timestamp, txn.winc, txn.wdata, txn.wfull, txn.almost_wfull);
				end
				else if (txn_msg == 1) begin
					$display("[%0t] Monitor posted WRITE transaction: winc=%b wdata=%h", txn.timestamp, txn.winc, txn.wdata);
				end
				else if (txn_msg == 0) begin
					$display("[%0t] Monitor posted WRITE transaction", txn.timestamp);
				end
				mbx.put(txn);
			end
        end
    endtask

	task monitor_read();
		forever begin
			@(posedge r_vif.clk);
			if (r_vif.rinc) begin
				transaction #(DSIZE) txn;
				txn = new();
				txn.timestamp = $time;
				txn.kind = READ_TXN;
				txn.rinc = r_vif.rinc;
				txn.rdata = r_vif.rdata;
				txn.rempty = r_vif.rempty;
				txn.almost_rempty = r_vif.almost_rempty;
				if (txn_msg == 2) begin
					$display("[%0t] Monitor posted READ transaction: rinc=%b rdata=%h rempty=%b almost_rempty=%b",
					         txn.timestamp, txn.rinc, txn.rdata, txn.rempty, txn.almost_rempty);
				end
				else if (txn_msg == 1) begin
					$display("[%0t] Monitor posted READ transaction: rinc=%b rdata=%h", txn.timestamp, txn.rinc, txn.rdata);
				end
				else if (txn_msg == 0) begin
					$display("[%0t] Monitor posted READ transaction", txn.timestamp);
				end
				mbx.put(txn);
			end
		end
	endtask

	task run();
		if (!$value$plusargs("TXN_MSG=%d", txn_msg))
			txn_msg = 0;
		fork
			monitor_write();
			monitor_read();
		join
	endtask

endclass

//////////////////////
//Scoreboard
/////////////////////
class scoreboard #(parameter int FIFO_DEPTH = 16, parameter int DSIZE = 8);

	mailbox #(transaction #(DSIZE)) mbx;
	transaction #(DSIZE) txn;
	logic [DSIZE-1:0] expected_data;
	logic [DSIZE-1:0] fifo_data[$];
	logic [DSIZE-1:0] expected_reads[$];
	scoreboard_flag_t expected_flags[$];
	logic expected_flag_values[$];
	string expected_flag_names[$];
	int errors = 0;
	int writes = 0;
	int reads = 0;

    function new();
    endfunction 

    task run(virtual dut_wif #(DSIZE) w_vif, virtual dut_rif #(DSIZE) r_vif);
		fork
			begin : process_transactions
				forever begin
					mbx.get(txn);
					if (txn.kind == WRITE_TXN) begin
						if (txn.winc && !txn.wfull) begin
							if (fifo_data.size() >= FIFO_DEPTH) begin
								errors++;
								$error("[%0t] write accepted while scoreboard FIFO is full", $time);
							end
							else begin
								fifo_data.push_back(txn.wdata);
								writes++;
							end
						end
					end
					else begin
						if (txn.rinc && !txn.rempty) begin
							if (fifo_data.size() == 0) begin
								errors++;
								$error("[%0t] read accepted while scoreboard FIFO is empty", $time);
							end
							else begin
								expected_data = fifo_data.pop_front();
								reads++;
								if (txn.rdata !== expected_data) begin
									errors++;
									$error("[%0t] rdata mismatch: expected %h, observed %h",
									       $time, expected_data, txn.rdata);
								end
								if (expected_reads.size() != 0 &&
								    txn.rdata !== expected_reads.pop_front()) begin
									errors++;
									$error("[%0t] test read expectation mismatch", $time);
								end
							end
						end
					end
				end
			end
			begin : check_write_flags
				forever begin
					transaction #(DSIZE) observed;
					@(posedge w_vif.clk);
					observed = new();
					observed.wfull = w_vif.wfull;
					observed.almost_wfull = w_vif.almost_wfull;
					check_flags(observed, WFULL, ALMOST_WFULL);
				end
			end
			begin : check_read_flags
				forever begin
					transaction #(DSIZE) observed;
					@(posedge r_vif.clk);
					observed = new();
					observed.rempty = r_vif.rempty;
					observed.almost_rempty = r_vif.almost_rempty;
					check_flags(observed, REMPTY, ALMOST_REMPTY);
				end
			end
		join
    endtask

    // Intermediate task to check the expected flags against the observed flags in a transaction.
	task expect_flag(scoreboard_flag_t flag, logic expected, string name);
		expected_flags.push_back(flag);
		expected_flag_values.push_back(expected);
		expected_flag_names.push_back(name);
	endtask

	task expect_read_data(logic [DSIZE-1:0] expected);
		expected_reads.push_back(expected);
	endtask

	task check_flags(transaction #(DSIZE) observed, scoreboard_flag_t first, scoreboard_flag_t second);
		for (int index = 0; index < expected_flags.size();) begin
			if (expected_flags[index] == first ||
			    expected_flags[index] == second) begin
				logic actual;
				case (expected_flags[index])
					WFULL:         actual = observed.wfull;
					ALMOST_WFULL:  actual = observed.almost_wfull;
					REMPTY:        actual = observed.rempty;
					ALMOST_REMPTY: actual = observed.almost_rempty;
				endcase
				if (actual !== expected_flag_values[index]) begin
					errors++;
					$error("[%0t] FAIL: %s: expected %b, observed %b",
					       $time, expected_flag_names[index],
					       expected_flag_values[index], actual);
				end
				else begin
					$display("[%0t] PASS: %s: expected %b, observed %b",
					         $time, expected_flag_names[index],
					         expected_flag_values[index], actual);
				end
				expected_flags.delete(index);
				expected_flag_values.delete(index);
				expected_flag_names.delete(index);
			end
			else
				index++;
		end
	endtask

	task report(string test_name);
		wait (expected_flags.size() == 0);
		if (expected_reads.size() != 0) begin
			errors += expected_reads.size();
			$error("%s: %0d expected read(s) were not observed", test_name, expected_reads.size());
			expected_reads.delete();
		end
		if (errors == 0)
			$display("%s PASSED (writes=%0d reads=%0d)", test_name, writes, reads);
		else
			$display("%s FAILED with %0d scoreboard errors", test_name, errors);
	endtask

endclass

module fifo_tb;

	localparam int DSIZE = 8;
	localparam int ASIZE = 4;
	localparam int DEPTH = 1 << ASIZE;

	logic [DSIZE-1:0] wdata;
	logic [DSIZE-1:0] rdata;
	logic             winc;
	logic             rinc;
	logic             wclk;
	logic             rclk;
	logic             wrst_n;
	logic             rrst_n;
	logic             wfull;
	logic             rempty;
	logic             almost_wfull;
	logic             almost_rempty;
	int               errors;

    dut_wif dut_wif_inst(wclk);
	dut_rif dut_rif_inst(rclk);

    assign dut_wif_inst.winc = winc;
	assign dut_wif_inst.wdata = wdata;
	assign wfull = dut_wif_inst.wfull;
	assign almost_wfull = dut_wif_inst.almost_wfull;

    assign dut_rif_inst.rinc = rinc;
	assign rdata = dut_rif_inst.rdata;
	assign rempty = dut_rif_inst.rempty;
	assign almost_rempty = dut_rif_inst.almost_rempty;



	fifo #(
		.DSIZE(DSIZE),
		.ASIZE(ASIZE)
	) dut (
		.rdata (dut_rif_inst.rdata),
		.wfull (dut_wif_inst.wfull),
		.rempty(dut_rif_inst.rempty),
		.almost_wfull(dut_wif_inst.almost_wfull),
		.almost_rempty(dut_rif_inst.almost_rempty),
		.wdata (dut_wif_inst.wdata),
		.winc  (dut_wif_inst.winc),
		.wclk  (wclk),
		.wrst_n(wrst_n),
		.rinc  (dut_rif_inst.rinc),
		.rclk  (rclk),
		.rrst_n(rrst_n)
	);

	initial begin
		wclk = 1'b0;
		forever #5 wclk = ~wclk;
	end

	initial begin
		rclk = 1'b0;
		forever #7 rclk = ~rclk;
	end

    // Create testbench components 
	mailbox #(transaction #(DSIZE)) mbx;
	monitor #(.DSIZE(DSIZE)) mon;
	scoreboard #(.FIFO_DEPTH(DEPTH), .DSIZE(DSIZE)) sb;

	initial begin
		mon = new(dut_wif_inst, dut_rif_inst);
		sb = new();
		mbx = new();
		mon.mbx = mbx;
		sb.mbx = mbx;
		fork
			mon.run();
			sb.run(dut_wif_inst, dut_rif_inst);
		join
	end
		   
	task automatic write_word(input logic [DSIZE-1:0] value);
		@(negedge wclk);
		wdata = value;
		winc = 1'b1;
		@(negedge wclk);
		winc = 1'b0;
	endtask

	function automatic logic [DSIZE-1:0] data_for_index(input int index);
		data_for_index = index + 8'h10;
	endfunction

	task automatic read_word(input logic [DSIZE-1:0] expected);
		sb.expect_read_data(expected);
		@(negedge rclk);
		rinc = 1'b1;
		@(negedge rclk);
		rinc = 1'b0;
	endtask

	task automatic attempt_read;
		@(negedge rclk);
		rinc = 1'b1;
		@(negedge rclk);
		rinc = 1'b0;
	endtask

	task automatic reset_fifo;
		wdata  = '0;
		winc   = 1'b0;
		rinc   = 1'b0;
		wrst_n = 1'b0;
		rrst_n = 1'b0;

		repeat (2) @(posedge wclk);
		repeat (2) @(posedge rclk);

		// Release reset away from active clock edges to avoid races with
		// the DUT flops and the checker's #1step sampling.
		@(negedge wclk);
		wrst_n = 1'b1;
		rrst_n = 1'b1;

		#1;
	endtask

	// ============================================================
	// TEST 1: Empty -> Full -> Empty
	// ============================================================
	task automatic test_full_empty;
		reset_fifo();

		sb.expect_flag(WFULL, 1'b0, "wfull after reset");
		sb.expect_flag(REMPTY, 1'b1, "rempty after reset");

		// Fill FIFO with 0x10 through 0x1F
		for (int index = 0; index < DEPTH; index++) begin
			write_word(data_for_index(index));
		end

		@(negedge wclk);
		sb.expect_flag(WFULL, 1'b1, "wfull after filling FIFO");

		// Attempt one extra write while full
		write_word(8'hff);
		sb.expect_flag(WFULL, 1'b1, "wfull after blocked write");
		repeat (3) @(posedge rclk);

		// Empty FIFO
		for (int index = 0; index < DEPTH; index++) begin
			read_word(data_for_index(index));
		end

		@(negedge rclk);
		sb.expect_flag(REMPTY, 1'b1, "rempty after draining FIFO");

		// Attempt one extra read while empty
		attempt_read();
		sb.expect_flag(REMPTY, 1'b1, "rempty after blocked read");
		sb.report("TEST 1: FIFO full/empty");
	endtask

	// ============================================================
	// TEST 0: Empty FIFO must block reads
	// ============================================================
	task automatic test_empty_read;
		reset_fifo();

		// With no writes, the read pointer must remain empty after the
		// synchronized-pointer pipeline has had several read clocks.
		repeat (3) @(posedge rclk);
		@(negedge rclk);
		sb.expect_flag(REMPTY, 1'b1, "rempty with no writes");

		// An attempted read on an empty FIFO must not advance the pointer.
		rinc = 1'b1;
		@(negedge rclk);
		rinc = 1'b0;
		sb.expect_flag(REMPTY, 1'b1, "rempty after blocked read on empty FIFO");
		sb.report("TEST 0: Empty FIFO read blocking");
	endtask


	// ============================================================
	// TEST 2: Almost Full / Almost Empty
	// ============================================================
	task automatic test_almost_flags;
		reset_fifo();

		// Write 11 entries so almost_wfull should still be 0.
		for (int index = 0; index < 11; index++) begin
			write_word(data_for_index(index));
		end

		sb.expect_flag(ALMOST_WFULL, 1'b0, "almost_wfull before 3/4 full");

		// Write 12th entry, so now its 3/4 full (12/16 entries).
		write_word(8'h1b);

		sb.expect_flag(ALMOST_WFULL, 1'b1, "almost_wfull at 12/16 entries");

		// Write 13th entry which is past the exact threshold for almost_wfull, so it should return to 0.
		write_word(8'h1c);

		sb.expect_flag(ALMOST_WFULL, 1'b1, "almost_wfull stays asserted after threshold");

		// Fill remaining three entries: 0x2D, 0x2E, 0x2F
		for (int index = 13; index < DEPTH; index++) begin
			write_word(data_for_index(index));
		end

		repeat (3) @(posedge rclk);

		// Read 11 entries so almost_rempty should still be 0.
		for (int index = 0; index < 11; index++) begin
			read_word(data_for_index(index));
		end

		sb.expect_flag(ALMOST_REMPTY, 1'b0, "almost_rempty before threshold");

		// Read 12th entry so now its 3/4 empty (4/16 entries remaining).
		read_word(8'h1b);

		sb.expect_flag(ALMOST_REMPTY, 1'b1, "almost_rempty at 4/16 entries remaining");

		// Read one more entry which is past the exact threshold for almost_rempty, so it should return to 0.
		read_word(8'h1c);

		sb.expect_flag(ALMOST_REMPTY, 1'b1, "almost_rempty remains asserted after threshold");
		sb.report("TEST 2: Almost-full/almost-empty");
	endtask


	// ============================================================
	// TEST 3: Simultaneous asynchronous reads/writes
	// ============================================================
	task automatic test_async_rw;
		reset_fifo();

	sb.expect_flag(WFULL, 1'b0, "wfull after reset");
	sb.expect_flag(REMPTY, 1'b1, "rempty after reset");

    // Preload four entries so the read side has data available before simultaneous reading and writing begins.
    for (int index = 0; index < 4; index++) begin
		write_word(data_for_index(index));
    end

    // Allow the write pointer to synchronize into the read domain.
    repeat (3) @(posedge rclk);

    // Perform writes and reads at the same time.
    // Writer adds 0x14 through 0x1F.
    // Reader checks the complete sequence 0x10 through 0x1F.
    fork

        begin : writer
            for (int index = 4; index < DEPTH; index++) begin
				write_word(data_for_index(index));
            end
        end

        begin : reader
            for (int index = 0; index < DEPTH; index++) begin
				read_word(data_for_index(index));
            end
        end

    join

    // Allow empty status to propagate through the read domain.
    repeat (2) @(posedge rclk);
    @(negedge rclk);

	sb.expect_flag(REMPTY, 1'b1,
				   "rempty after simultaneous read/write test");
	sb.report("TEST 3: Async simultaneous read/write");
	endtask


	// ============================================================
	// Select testcase from command line
	// ============================================================
	string testname;
	string fsdb_prefix;

	initial begin
		if (!$value$plusargs("TEST=%s", testname))
			testname = "full_empty";

		`ifdef BUG
		   fsdb_prefix = "bug_";
		`else
		   fsdb_prefix = "normal_";
		`endif

		case (testname)

			"empty_read": begin
				$fsdbDumpfile($sformatf("%stest0_empty_read.fsdb", fsdb_prefix));
				$fsdbDumpvars(0, "+mda");
				$fsdbDumpvars(fifo_tb, "+class","+object_level=4");
				test_empty_read();
			end

			"full_empty": begin
				$fsdbDumpfile($sformatf("%stest1_full_empty.fsdb", fsdb_prefix));
				$fsdbDumpvars(0, "+mda");
				$fsdbDumpvars(fifo_tb, "+class","+object_level=4");
				test_full_empty();
			end

			"almost": begin
				$fsdbDumpfile($sformatf("%stest2_almost.fsdb", fsdb_prefix));
				$fsdbDumpvars(0, "+mda");
				$fsdbDumpvars(fifo_tb, "+class","+object_level=4");
				test_almost_flags();
			end

			"async_rw": begin
				$fsdbDumpfile($sformatf("%stest3_async_rw.fsdb", fsdb_prefix));
				$fsdbDumpvars(0, "+mda");
				$fsdbDumpvars(fifo_tb, "+class","+object_level=4");
				test_async_rw();
			end

			default: begin
				$display("ERROR: Unknown testcase '%s'", testname);
				$display("Use:");
				$display("  +TEST=empty_read");
				$display("  +TEST=full_empty");
				$display("  +TEST=almost");
				$display("  +TEST=async_rw");
			end

		endcase

		$finish;
	end
endmodule
