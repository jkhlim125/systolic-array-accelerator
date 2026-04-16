`timescale 1ns / 1ps

// -----------------------------------------------------------------------------
// Top-Level Accelerator Testbench
// - Runs end-to-end matrix multiplication tests through controller, loader,
//   systolic array, and output collector.
// - Generates both waveforms and a CSV trace for later visualization.
// -----------------------------------------------------------------------------
module top_tb;

    parameter ARRAY_SIZE = 4;
    parameter DATA_WIDTH = 8;
    parameter ACC_WIDTH  = 24;

    reg clk;
    reg rst_n;
    reg start;
    reg [ARRAY_SIZE*ARRAY_SIZE*DATA_WIDTH-1:0] a_matrix_flat;
    reg [ARRAY_SIZE*ARRAY_SIZE*DATA_WIDTH-1:0] b_matrix_flat;

    wire busy;
    wire done;
    wire c_valid;
    wire [ARRAY_SIZE*ARRAY_SIZE*ACC_WIDTH-1:0] c_matrix_flat;
    wire [2:0] dbg_state;
    wire [15:0] dbg_cycle;
    wire [15:0] dbg_stream_cycle;
    wire dbg_c_valid;
    wire [ARRAY_SIZE*DATA_WIDTH-1:0] dbg_a_row_data_flat;
    wire [ARRAY_SIZE-1:0] dbg_a_row_valid;
    wire [ARRAY_SIZE*DATA_WIDTH-1:0] dbg_b_col_data_flat;
    wire [ARRAY_SIZE-1:0] dbg_b_col_valid;
    wire [ARRAY_SIZE*ARRAY_SIZE*ACC_WIDTH-1:0] dbg_pe_psum_flat;
    wire [ARRAY_SIZE*ARRAY_SIZE-1:0] dbg_pe_mac_fire_flat;

    integer cycle_count;
    integer i;
    integer j;
    integer wait_count;
    integer start_cycle;
    integer done_cycle;
    integer observed_latency;
    integer actual_value;
    integer trace_file;
    reg trace_enable;

    integer a_matrix_ref [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1];
    integer b_matrix_ref [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1];
    integer c_expected_ref [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1];

    top #(
        .ARRAY_SIZE(ARRAY_SIZE),
        .DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH(ACC_WIDTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .a_matrix_flat(a_matrix_flat),
        .b_matrix_flat(b_matrix_flat),
        .busy(busy),
        .done(done),
        .c_valid(c_valid),
        .c_matrix_flat(c_matrix_flat),
        .dbg_state(dbg_state),
        .dbg_cycle(dbg_cycle),
        .dbg_stream_cycle(dbg_stream_cycle),
        .dbg_c_valid(dbg_c_valid),
        .dbg_a_row_data_flat(dbg_a_row_data_flat),
        .dbg_a_row_valid(dbg_a_row_valid),
        .dbg_b_col_data_flat(dbg_b_col_data_flat),
        .dbg_b_col_valid(dbg_b_col_valid),
        .dbg_pe_psum_flat(dbg_pe_psum_flat),
        .dbg_pe_mac_fire_flat(dbg_pe_mac_fire_flat)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        $dumpfile("top_tb.vcd");
        $dumpvars(0, top_tb);
    end

    initial begin
        trace_enable = 1'b0;
        trace_file = $fopen("trace.csv", "w");
        $fwrite(trace_file,
                "cycle,state,stream_cycle,c_valid,busy,done,pe_mac_fire_flat,psum_flat\n");
        trace_enable = 1'b1;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cycle_count <= 0;
        end else begin
            cycle_count <= cycle_count + 1;
        end
    end

    always @(posedge clk) begin
        if (trace_enable) begin
            // Trace one sample per clock so Python can reconstruct control flow
            // and PE activity without depending on the VCD parser.
            $fwrite(trace_file,
                    "%0d,%0d,%0d,%0d,%0d,%0d,%h,%h\n",
                    dbg_cycle,
                    dbg_state,
                    dbg_stream_cycle,
                    c_valid,
                    busy,
                    done,
                    dbg_pe_mac_fire_flat,
                    dbg_pe_psum_flat);
        end
    end

    task pack_input_matrices;
        integer row_idx;
        integer col_idx;
        integer flat_idx;
        begin
            a_matrix_flat = {(ARRAY_SIZE*ARRAY_SIZE*DATA_WIDTH){1'b0}};
            b_matrix_flat = {(ARRAY_SIZE*ARRAY_SIZE*DATA_WIDTH){1'b0}};

            for (row_idx = 0; row_idx < ARRAY_SIZE; row_idx = row_idx + 1) begin
                for (col_idx = 0; col_idx < ARRAY_SIZE; col_idx = col_idx + 1) begin
                    // A and B both use row-major flattening:
                    // flat index = row_idx * ARRAY_SIZE + col_idx.
                    flat_idx = (row_idx * ARRAY_SIZE) + col_idx;
                    a_matrix_flat[(flat_idx*DATA_WIDTH) +: DATA_WIDTH] = a_matrix_ref[row_idx][col_idx];
                    b_matrix_flat[(flat_idx*DATA_WIDTH) +: DATA_WIDTH] = b_matrix_ref[row_idx][col_idx];
                end
            end
        end
    endtask

    task compute_expected_matrix;
        integer row_idx;
        integer col_idx;
        integer mul_idx;
        integer sum;
        begin
            for (row_idx = 0; row_idx < ARRAY_SIZE; row_idx = row_idx + 1) begin
                for (col_idx = 0; col_idx < ARRAY_SIZE; col_idx = col_idx + 1) begin
                    sum = 0;
                    for (mul_idx = 0; mul_idx < ARRAY_SIZE; mul_idx = mul_idx + 1) begin
                        sum = sum + (a_matrix_ref[row_idx][mul_idx] * b_matrix_ref[mul_idx][col_idx]);
                    end
                    c_expected_ref[row_idx][col_idx] = sum;
                end
            end
        end
    endtask

    task print_matrix_a;
        begin
            $display("Matrix A:");
            for (i = 0; i < ARRAY_SIZE; i = i + 1) begin
                $display("  [%0d %0d %0d %0d]",
                         a_matrix_ref[i][0], a_matrix_ref[i][1],
                         a_matrix_ref[i][2], a_matrix_ref[i][3]);
            end
        end
    endtask

    task print_matrix_b;
        begin
            $display("Matrix B:");
            for (i = 0; i < ARRAY_SIZE; i = i + 1) begin
                $display("  [%0d %0d %0d %0d]",
                         b_matrix_ref[i][0], b_matrix_ref[i][1],
                         b_matrix_ref[i][2], b_matrix_ref[i][3]);
            end
        end
    endtask

    task print_expected_matrix;
        begin
            $display("Expected C:");
            for (i = 0; i < ARRAY_SIZE; i = i + 1) begin
                $display("  [%0d %0d %0d %0d]",
                         c_expected_ref[i][0], c_expected_ref[i][1],
                         c_expected_ref[i][2], c_expected_ref[i][3]);
            end
        end
    endtask

    task print_actual_matrix;
        integer flat_idx;
        begin
            $display("RTL C:");
            for (i = 0; i < ARRAY_SIZE; i = i + 1) begin
                // c_matrix_flat is row-major over output coordinates.
                actual_value = $signed(c_matrix_flat[(((i*ARRAY_SIZE) + 0)*ACC_WIDTH) +: ACC_WIDTH]);
                $write("  [%0d", actual_value);

                for (j = 1; j < ARRAY_SIZE; j = j + 1) begin
                    flat_idx = (i * ARRAY_SIZE) + j;
                    actual_value = $signed(c_matrix_flat[(flat_idx*ACC_WIDTH) +: ACC_WIDTH]);
                    $write(" %0d", actual_value);
                end

                $write("]\n");
            end
        end
    endtask

    task check_results;
        integer row_idx;
        integer col_idx;
        integer flat_idx;
        begin
            for (row_idx = 0; row_idx < ARRAY_SIZE; row_idx = row_idx + 1) begin
                for (col_idx = 0; col_idx < ARRAY_SIZE; col_idx = col_idx + 1) begin
                    flat_idx = (row_idx * ARRAY_SIZE) + col_idx;
                    actual_value = $signed(c_matrix_flat[(flat_idx*ACC_WIDTH) +: ACC_WIDTH]);

                    if (actual_value !== c_expected_ref[row_idx][col_idx]) begin
                        $display("[FAIL] Mismatch at C[%0d][%0d]: expected %0d, got %0d",
                                 row_idx, col_idx, c_expected_ref[row_idx][col_idx], actual_value);
                        $finish;
                    end
                end
            end
        end
    endtask

    task wait_for_done_with_timeout;
        begin
            wait_count = 0;
            while ((done !== 1'b1) && (wait_count < 40)) begin
                @(posedge clk);
                wait_count = wait_count + 1;
            end

            if (done !== 1'b1) begin
                $display("[FAIL] Timed out waiting for done.");
                $finish;
            end
        end
    endtask

    task run_test;
        input [255:0] test_name;
        begin
            compute_expected_matrix();
            pack_input_matrices();

            $display("\n========================================");
            $display("Running full-system test: %0s", test_name);
            print_matrix_a();
            print_matrix_b();
            print_expected_matrix();

            @(negedge clk);
            start = 1'b1;
            start_cycle = cycle_count;

            @(negedge clk);
            start = 1'b0;

            wait_for_done_with_timeout();
            done_cycle = cycle_count;
            observed_latency = done_cycle - start_cycle;

            $display("Observed start-to-done latency: %0d cycles", observed_latency);
            print_actual_matrix();
            check_results();
            $display("[PASS] %0s", test_name);

            @(negedge clk);
        end
    endtask

    task load_test_identity_times_random;
        begin
            // Identity * B should reproduce B exactly.
            for (i = 0; i < ARRAY_SIZE; i = i + 1) begin
                for (j = 0; j < ARRAY_SIZE; j = j + 1) begin
                    a_matrix_ref[i][j] = (i == j) ? 1 : 0;
                end
            end

            b_matrix_ref[0][0] =  3;  b_matrix_ref[0][1] = -1;  b_matrix_ref[0][2] =  4;  b_matrix_ref[0][3] =  2;
            b_matrix_ref[1][0] =  0;  b_matrix_ref[1][1] =  5;  b_matrix_ref[1][2] = -2;  b_matrix_ref[1][3] =  1;
            b_matrix_ref[2][0] = -3;  b_matrix_ref[2][1] =  6;  b_matrix_ref[2][2] =  7;  b_matrix_ref[2][3] = -4;
            b_matrix_ref[3][0] =  8;  b_matrix_ref[3][1] = -5;  b_matrix_ref[3][2] =  2;  b_matrix_ref[3][3] =  9;
        end
    endtask

    task load_test_all_ones_times_small;
        begin
            // All-ones rows should turn each output row into the column-wise sum of B.
            for (i = 0; i < ARRAY_SIZE; i = i + 1) begin
                for (j = 0; j < ARRAY_SIZE; j = j + 1) begin
                    a_matrix_ref[i][j] = 1;
                end
            end

            b_matrix_ref[0][0] =  1;  b_matrix_ref[0][1] =  2;  b_matrix_ref[0][2] =  3;  b_matrix_ref[0][3] =  4;
            b_matrix_ref[1][0] = -1;  b_matrix_ref[1][1] =  0;  b_matrix_ref[1][2] =  1;  b_matrix_ref[1][3] =  2;
            b_matrix_ref[2][0] =  2;  b_matrix_ref[2][1] = -2;  b_matrix_ref[2][2] =  1;  b_matrix_ref[2][3] =  0;
            b_matrix_ref[3][0] =  3;  b_matrix_ref[3][1] =  1;  b_matrix_ref[3][2] = -1;  b_matrix_ref[3][3] =  2;
        end
    endtask

    task load_test_signed_values;
        begin
            // Mixed-sign values stress signed multiplication and accumulation through the full path.
            a_matrix_ref[0][0] =  2;  a_matrix_ref[0][1] = -1;  a_matrix_ref[0][2] =  3;  a_matrix_ref[0][3] =  0;
            a_matrix_ref[1][0] = -2;  a_matrix_ref[1][1] =  4;  a_matrix_ref[1][2] = -1;  a_matrix_ref[1][3] =  2;
            a_matrix_ref[2][0] =  1;  a_matrix_ref[2][1] =  0;  a_matrix_ref[2][2] = -3;  a_matrix_ref[2][3] =  5;
            a_matrix_ref[3][0] =  3;  a_matrix_ref[3][1] = -2;  a_matrix_ref[3][2] =  1;  a_matrix_ref[3][3] = -4;

            b_matrix_ref[0][0] = -1;  b_matrix_ref[0][1] =  2;  b_matrix_ref[0][2] =  0;  b_matrix_ref[0][3] =  3;
            b_matrix_ref[1][0] =  4;  b_matrix_ref[1][1] = -2;  b_matrix_ref[1][2] =  1;  b_matrix_ref[1][3] = -1;
            b_matrix_ref[2][0] =  2;  b_matrix_ref[2][1] =  1;  b_matrix_ref[2][2] = -3;  b_matrix_ref[2][3] =  0;
            b_matrix_ref[3][0] = -2;  b_matrix_ref[3][1] =  3;  b_matrix_ref[3][2] =  2;  b_matrix_ref[3][3] = -4;
        end
    endtask

    task load_test_zero_matrix;
        begin
            // Zero-valued A should keep every PE accumulator at zero.
            for (i = 0; i < ARRAY_SIZE; i = i + 1) begin
                for (j = 0; j < ARRAY_SIZE; j = j + 1) begin
                    a_matrix_ref[i][j] = 0;
                end
            end

            b_matrix_ref[0][0] =  5;  b_matrix_ref[0][1] = -3;  b_matrix_ref[0][2] =  2;  b_matrix_ref[0][3] =  1;
            b_matrix_ref[1][0] = -4;  b_matrix_ref[1][1] =  6;  b_matrix_ref[1][2] = -2;  b_matrix_ref[1][3] =  0;
            b_matrix_ref[2][0] =  7;  b_matrix_ref[2][1] =  1;  b_matrix_ref[2][2] =  3;  b_matrix_ref[2][3] = -5;
            b_matrix_ref[3][0] =  2;  b_matrix_ref[3][1] = -1;  b_matrix_ref[3][2] =  4;  b_matrix_ref[3][3] =  8;
        end
    endtask

    initial begin
        rst_n = 1'b0;
        start = 1'b0;
        a_matrix_flat = {(ARRAY_SIZE*ARRAY_SIZE*DATA_WIDTH){1'b0}};
        b_matrix_flat = {(ARRAY_SIZE*ARRAY_SIZE*DATA_WIDTH){1'b0}};

        #20;
        rst_n = 1'b1;

        // Test 1: identity matrix sanity check.
        load_test_identity_times_random();
        run_test("identity_times_random");

        // Test 2: dense accumulation with repeated rows.
        load_test_all_ones_times_small();
        run_test("all_ones_times_small");

        // Test 3: signed arithmetic through the full accelerator path.
        load_test_signed_values();
        run_test("signed_values");

        // Test 4: zero activity in the arithmetic result space.
        load_test_zero_matrix();
        run_test("zero_matrix");

        $display("\n[PASS] All full-system accelerator tests completed successfully.");
        trace_enable = 1'b0;
        $fclose(trace_file);
        trace_file = 0;
        #20;
        $finish;
    end

endmodule
