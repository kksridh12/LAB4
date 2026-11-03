

timeunit 1ns;
timeprecision 1ps;

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

	fifo #(
		.DSIZE(DSIZE),
		.ASIZE(ASIZE)
	) dut (
		.rdata (rdata),
		.wfull (wfull),
		.rempty(rempty),
		.almost_wfull(almost_wfull),
		.almost_rempty(almost_rempty),
		.wdata (wdata),
		.winc  (winc),
		.wclk  (wclk),
		.wrst_n(wrst_n),
		.rinc  (rinc),
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

	task automatic check_flag(
		input logic actual,
		input logic expected,
		input string name
	);
		if (actual !== expected) begin
			$error("%s: expected %b, got %b at time %0t", name, expected, actual, $time);
			errors++;
		end
	endtask

	task automatic write_word(input logic [DSIZE-1:0] value);
		@(negedge wclk);
		wdata = value;
		winc = 1'b1;
		@(negedge wclk);
		winc = 1'b0;
	endtask

	task automatic read_word(input logic [DSIZE-1:0] expected);
		@(negedge rclk);
		rinc = 1'b1;
		#1;
		if (rdata !== expected) begin
			$error("read data: expected %h, got %h at time %0t", expected, rdata, $time);
			errors++;
		end
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
		errors = 0;

		repeat (2) @(posedge wclk);
		repeat (2) @(posedge rclk);

		wrst_n = 1'b1;
		rrst_n = 1'b1;

		#1;
	endtask

	// ============================================================
	// TEST 1: Empty -> Full -> Empty
	// ============================================================
	task automatic test_full_empty;
		reset_fifo();

		check_flag(wfull, 1'b0, "wfull after reset");
		check_flag(rempty, 1'b1, "rempty after reset");

		// Fill FIFO with 0x10 through 0x1F
		for (int index = 0; index < DEPTH; index++) begin
			write_word(DSIZE'(index + 8'h10));
		end

		@(negedge wclk);
		check_flag(wfull, 1'b1, "wfull after filling FIFO");

		// Attempt one extra write while full
		write_word(8'hff);
		check_flag(wfull, 1'b1, "wfull after blocked write");
		repeat (3) @(posedge rclk);

		// Empty FIFO
		for (int index = 0; index < DEPTH; index++) begin
			read_word(DSIZE'(index + 8'h10));
		end

		@(negedge rclk);
		check_flag(rempty, 1'b1, "rempty after draining FIFO");

		// Attempt one extra read while empty
		attempt_read();
		check_flag(rempty, 1'b1, "rempty after blocked read");

		if (errors == 0)
			$display("TEST 1: FIFO full/empty PASSED");
		else
			$display("TEST 1: FIFO full/empty FAILED with %0d errors", errors);
	endtask


	// ============================================================
	// TEST 2: Almost Full / Almost Empty
	// ============================================================
	task automatic test_almost_flags;
		reset_fifo();

		// Write 11 entries so almost_wfull should still be 0.
		for (int index = 0; index < 11; index++) begin
			write_word(DSIZE'(index + 8'h10));
		end

		check_flag(
			almost_wfull,
			1'b0,
			"almost_wfull before 3/4 full"
		);

		// Write 12th entry, so now its 3/4 full (12/16 entries).
		write_word(8'h1b);

		check_flag(
			almost_wfull,
			1'b1,
			"almost_wfull at 12/16 entries"
		);

		// Write 13th entry which is past the exact threshold for almost_wfull, so it should return to 0.
		write_word(8'h1c);

		check_flag(
			almost_wfull,
			1'b1,
			"almost_wfull stays asserted after threshold"
		);

		// Fill remaining three entries: 0x2D, 0x2E, 0x2F
		for (int index = 13; index < DEPTH; index++) begin
			write_word(DSIZE'(index + 8'h10));
		end

		repeat (3) @(posedge rclk);

		// Read 11 entries so almost_rempty should still be 0.
		for (int index = 0; index < 11; index++) begin
			read_word(DSIZE'(index + 8'h10));
		end

		check_flag(
			almost_rempty,
			1'b0,
			"almost_rempty before threshold"
		);

		// Read 12th entry so now its 3/4 empty (4/16 entries remaining).
		read_word(8'h1b);

		check_flag(
			almost_rempty,
			1'b1,
			"almost_rempty at 4/16 entries remaining"
		);

		// Read one more entry which is past the exact threshold for almost_rempty, so it should return to 0.
		read_word(8'h1c);

		check_flag(
			almost_rempty,
			1'b1,
			"almost_rempty remains asserted after threshold"
		);

		if (errors == 0)
			$display("TEST 2: Almost-full/almost-empty PASSED");
		else
			$display(
				"TEST 2: Almost-full/almost-empty FAILED with %0d errors",
				errors
			);
	endtask


	// ============================================================
	// TEST 3: Simultaneous asynchronous reads/writes
	// ============================================================
	task automatic test_async_rw;
		reset_fifo();

    check_flag(wfull, 1'b0, "wfull after reset");
    check_flag(rempty, 1'b1, "rempty after reset");

    // Preload four entries so the read side has data available before simultaneous reading and writing begins.
    for (int index = 0; index < 4; index++) begin
        write_word(DSIZE'(index + 8'h10));
    end

    // Allow the write pointer to synchronize into the read domain.
    repeat (3) @(posedge rclk);

    // Perform writes and reads at the same time.
    // Writer adds 0x14 through 0x1F.
    // Reader checks the complete sequence 0x10 through 0x1F.
    fork

        begin : writer
            for (int index = 4; index < DEPTH; index++) begin
                write_word(DSIZE'(index + 8'h10));
            end
        end

        begin : reader
            for (int index = 0; index < DEPTH; index++) begin
                read_word(DSIZE'(index + 8'h10));
            end
        end

    join

    // Allow empty status to propagate through the read domain.
    repeat (2) @(posedge rclk);
    @(negedge rclk);

    check_flag(rempty, 1'b1,
               "rempty after simultaneous read/write test");

    if (errors == 0)
        $display("TEST 3: Async simultaneous read/write PASSED");
    else
        $display(
            "TEST 3: Async simultaneous read/write FAILED with %0d errors",
            errors
        );
	endtask


	// ============================================================
	// Select testcase from command line
	// ============================================================
	string testname;

	initial begin
		if (!$value$plusargs("TEST=%s", testname))
			testname = "full_empty";

		case (testname)

			"full_empty": begin
				$fsdbDumpfile("test1_full_empty.fsdb");
				$fsdbDumpvars(0, "+mda");
				test_full_empty();
			end

			"almost": begin
				$fsdbDumpfile("test2_almost.fsdb");
				$fsdbDumpvars(0, "+mda");
				test_almost_flags();
			end

			"async_rw": begin
				$fsdbDumpfile("test3_async_rw.fsdb");
				$fsdbDumpvars(0, "+mda");
				test_async_rw();
			end

			default: begin
				$display("ERROR: Unknown testcase '%s'", testname);
				$display("Use:");
				$display("  +TEST=full_empty");
				$display("  +TEST=almost");
				$display("  +TEST=async_rw");
			end

		endcase

		$finish;
	end
endmodule