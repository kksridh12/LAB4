timeunit 1ns;
timeprecision 1ps;

module odd_even_tb;

	localparam int DSIZE = 8;
	localparam int ASIZE = 6;
	localparam int TOTAL_ITEMS = 160;

	logic [DSIZE-1:0] data_in;
	logic [DSIZE-1:0] data_out;
	logic             write_en;
	logic             read_en;
	logic             clock;
	logic             reset;

	int               errors;
	int               output_count;

	odd_even #(
		.DSIZE(DSIZE),
		.ASIZE(ASIZE),
		.ASYNC(0)
	) dut (
		.clock   (clock),
		.reset   (reset),
		.data_in (data_in),
		.write_en(write_en),
		.read_en (read_en),
		.data_out(data_out)
	);

	// 10 ns clock period
	initial begin
		clock = 1'b0;
		forever #5 clock = ~clock;
	end

	task automatic reset_design;
		data_in      = '0;
		write_en     = 1'b0;
		read_en      = 1'b0;
		reset        = 1'b0;
		errors       = 0;
		output_count = 0;
		repeat (3) @(posedge clock);
		reset = 1'b1;
		repeat (2) @(posedge clock);
	endtask

	// ============================================================
	// Worst-case input ordering:
	//
	// 40 ODD  | 40 EVEN | 40 EVEN | 40 ODD
	//
	// 01,03,...4F
	// 00,02,...4E
	// 50,52,...9E
	// 51,53,...9F
	//
	// Each group of 80 contains 40 odd and 40 even values.
	// ============================================================
	task automatic set_input(input int item);
		if (item < 40) begin
			// First 40 values: ODD
			// 01, 03, 05, ... 4F
			data_in = DSIZE'((item * 2) + 1);
		end
		else if (item < 80) begin
			// Next 40 values: EVEN
			// 00, 02, 04, ... 4E
			data_in = DSIZE'((item - 40) * 2);
		end
		else if (item < 120) begin
			// Next 40 values: EVEN
			// 50, 52, 54, ... 9E
			data_in = DSIZE'(
				8'h50 + ((item - 80) * 2)
			);
		end
		else begin
			// Final 40 values: ODD
			// 51, 53, 55, ... 9F
			data_in = DSIZE'(
				8'h51 + ((item - 120) * 2)
			);
		end
	endtask

	// ============================================================
	// Expected output:
	//
	// 01,00,03,02,...4F,4E,
	// 51,50,53,52,...9F,9E
	//
	// Output alternates odd/even while preserving ordering
	// inside each parity stream.
	// ============================================================
	task automatic check_output;
		logic [DSIZE-1:0] expected_value;
		if ((output_count % 2) == 0)
			expected_value = DSIZE'(output_count + 1);
		else
			expected_value = DSIZE'(output_count - 1);

		if (data_out !== expected_value) begin
			$error(
				"Output error: expected %h, got %h at time %0t",
				expected_value,
				data_out,
				$time
			);
			errors++;
		end
		output_count++;
	endtask

	// ============================================================
	// Consumer
	//
	// read_en = 1 for 8 out of every 10 cycles.
	//
	// The consumer runs for a fixed number of cycles so
	// simulation cannot hang forever.
	// ============================================================
	task automatic run_consumer;
		for (int cycle = 0; cycle < 300; cycle++) begin
			@(negedge clock);
			if ((cycle % 10) < 8)
				read_en = 1'b1;
			else
				read_en = 1'b0;
			// Allow combinational DUT logic to settle
			#1;
			// Only check data when the DUT actually reads
			// from one of the two FIFOs.
			if (dut.even_read_en || dut.odd_read_en) begin
				if (output_count < TOTAL_ITEMS)
					check_output();
			end
			@(posedge clock);
		end
		@(negedge clock);
		read_en = 1'b0;
	endtask

	// ============================================================
	// TEST 1:
	// FIFO Depth Calculation Case 9 - Case 4
	//
	// Cycles   0-19  : IDLE
	// Cycles  20-179 : continuous WRITE
	// Cycles 180-199 : IDLE
	//
	// This gives:
	//
	// First 100 cycles  -> 80 writes
	// Second 100 cycles -> 80 writes
	//
	// This is the worst-case timing pattern identified
	// in the FIFO depth calculation document.
	// ============================================================
	task automatic test_case4;
		int item;
		reset_design();
		item = 0;

		fork
			begin : producer
				for (int cycle = 0; cycle < 200; cycle++) begin
					@(negedge clock);
					if ((cycle >= 20) &&
					    (cycle < 180)) begin
						write_en = 1'b1;
						set_input(item);
						item++;
					end
					else begin
						write_en = 1'b0;
					end
					@(posedge clock);
				end
				@(negedge clock);
				write_en = 1'b0;
			end

			begin : consumer
				run_consumer();
			end
		join

		if (output_count != TOTAL_ITEMS) begin
			$error(
				"Expected %0d outputs, got %0d",
				TOTAL_ITEMS,
				output_count
			);
			errors++;
		end

		if (errors == 0)
			$display(
				"TEST 1: Case 9 - Case 4 PASSED"
			);
		else
			$display(
				"TEST 1: Case 9 - Case 4 FAILED with %0d errors",
				errors
			);
	endtask

	// ============================================================
	// TEST 2:
	// FIFO Depth Calculation Case 9 - Case 5
	//
	// Random-style idle cycles.
	//
	// Each 100-cycle section contains:
	// 80 write cycles
	// 20 idle cycles
	//
	// The idle positions are fixed so the testcase is
	// repeatable every time it is simulated.
	// ============================================================
	task automatic test_case5;
		int item;
		int slot;
		logic idle_cycle;
		reset_design();
		item = 0;

		fork
			begin : producer
				for (int cycle = 0; cycle < 200; cycle++) begin
					@(negedge clock);
					slot = cycle % 100;

					// 20 irregular idle positions
					// during every 100 cycles
					case (slot)
						3, 9, 14, 18, 27,
						31, 36, 44, 49, 53,
						61, 67, 72, 78, 83,
						87, 91, 94, 97, 99:
							idle_cycle = 1'b1;
						default:
							idle_cycle = 1'b0;
					endcase

					if (!idle_cycle) begin
						write_en = 1'b1;
						set_input(item);
						item++;
					end
					else begin
						write_en = 1'b0;
					end
					@(posedge clock);
				end
				@(negedge clock);
				write_en = 1'b0;
			end

			begin : consumer
				run_consumer();
			end
		join

		if (output_count != TOTAL_ITEMS) begin
			$error(
				"Expected %0d outputs, got %0d",
				TOTAL_ITEMS,
				output_count
			);
			errors++;
		end

		if (errors == 0)
			$display(
				"TEST 2: Case 9 - Case 5 PASSED"
			);
		else
			$display(
				"TEST 2: Case 9 - Case 5 FAILED with %0d errors",
				errors
			);
	endtask


	// ============================================================
	// Select testcase from command line
	// ============================================================
	string testname;

	initial begin
		if (!$value$plusargs("TEST=%s", testname))
			testname = "case4";

		case (testname)

			"case4": begin
				$fsdbDumpfile("test1_case4.fsdb");
				$fsdbDumpvars(0, "+mda");
				test_case4();
			end

			"case5": begin
				$fsdbDumpfile("test2_case5.fsdb");
				$fsdbDumpvars(0, "+mda");
				test_case5();
			end

			default: begin
				$display(
					"ERROR: Unknown testcase '%s'",
					testname
				);
				$display("Use:");
				$display("  +TEST=case4");
				$display("  +TEST=case5");
			end
		endcase
		$finish;
	end
endmodule