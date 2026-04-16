`timescale 1ns / 1ps

// -----------------------------------------------------------------------------
// Systolic Array Testbench
// - Drives edge streams directly into the array without the controller/loader.
// - Verifies operand propagation, distributed MAC activity, and PE-local sums.
// -----------------------------------------------------------------------------
module systolic_array_tb;

    parameter ARRAY_SIZE = 4;
    parameter DATA_WIDTH = 8;
    parameter ACC_WIDTH  = 24;

    reg clk;
    reg rst_n;
    reg clear_acc;
    reg enable;
    reg [ARRAY_SIZE*DATA_WIDTH-1:0] a_row_data_flat;
    reg [ARRAY_SIZE-1:0] a_row_valid;
    reg [ARRAY_SIZE*DATA_WIDTH-1:0] b_col_data_flat;
    reg [ARRAY_SIZE-1:0] b_col_valid;

    wire [ARRAY_SIZE*ARRAY_SIZE*ACC_WIDTH-1:0] c_psum_flat;
    wire [ARRAY_SIZE*ARRAY_SIZE-1:0] pe_mac_fire_flat;

    integer cycle_count;
    integer i;
    integer j;
    integer step;

    reg signed [DATA_WIDTH-1:0] row_wave1 [0:ARRAY_SIZE-1];
    reg signed [DATA_WIDTH-1:0] col_wave1 [0:ARRAY_SIZE-1];
    reg signed [DATA_WIDTH-1:0] row_wave2 [0:ARRAY_SIZE-1];
    reg signed [DATA_WIDTH-1:0] col_wave2 [0:ARRAY_SIZE-1];

    systolic_array #(
        .ARRAY_SIZE(ARRAY_SIZE),
        .DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH(ACC_WIDTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .clear_acc(clear_acc),
        .enable(enable),
        .a_row_data_flat(a_row_data_flat),
        .a_row_valid(a_row_valid),
        .b_col_data_flat(b_col_data_flat),
        .b_col_valid(b_col_valid),
        .c_psum_flat(c_psum_flat),
        .pe_mac_fire_flat(pe_mac_fire_flat)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        $dumpfile("systolic_array_tb.vcd");
        $dumpvars(0, systolic_array_tb);
    end

    task clear_stream_inputs;
        begin
            a_row_data_flat = {ARRAY_SIZE*DATA_WIDTH{1'b0}};
            a_row_valid = {ARRAY_SIZE{1'b0}};
            b_col_data_flat = {ARRAY_SIZE*DATA_WIDTH{1'b0}};
            b_col_valid = {ARRAY_SIZE{1'b0}};
        end
    endtask

    task drive_skewed_outer_product_step;
        input integer local_step;
        input integer wave_sel;
        integer idx;
        begin
            clear_stream_inputs;

            for (idx = 0; idx < ARRAY_SIZE; idx = idx + 1) begin
                if (local_step == idx) begin
                    // Edge injection uses one row operand and one column operand per step.
                    if (wave_sel == 1) begin
                        a_row_data_flat[(idx*DATA_WIDTH) +: DATA_WIDTH] = row_wave1[idx];
                        b_col_data_flat[(idx*DATA_WIDTH) +: DATA_WIDTH] = col_wave1[idx];
                    end else begin
                        a_row_data_flat[(idx*DATA_WIDTH) +: DATA_WIDTH] = row_wave2[idx];
                        b_col_data_flat[(idx*DATA_WIDTH) +: DATA_WIDTH] = col_wave2[idx];
                    end

                    a_row_valid[idx] = 1'b1;
                    b_col_valid[idx] = 1'b1;
                end
            end
        end
    endtask

    task check_psum_value;
        input integer row_idx;
        input integer col_idx;
        input integer expected;
        reg signed [ACC_WIDTH-1:0] actual;
        begin
            actual = c_psum_flat[((row_idx*ARRAY_SIZE + col_idx)*ACC_WIDTH) +: ACC_WIDTH];
            if (actual !== expected) begin
                $display("[FAIL] PE(%0d,%0d) expected %0d, got %0d at time %0t",
                         row_idx, col_idx, expected, actual, $time);
                $finish;
            end
        end
    endtask

    task check_wave1_results;
        begin
            check_psum_value(0, 0,   4);
            check_psum_value(0, 1,  -2);
            check_psum_value(0, 2,   5);
            check_psum_value(0, 3,   1);

            check_psum_value(1, 0,   8);
            check_psum_value(1, 1,  -4);
            check_psum_value(1, 2,  10);
            check_psum_value(1, 3,   2);

            check_psum_value(2, 0,  -4);
            check_psum_value(2, 1,   2);
            check_psum_value(2, 2,  -5);
            check_psum_value(2, 3,  -1);

            check_psum_value(3, 0,  12);
            check_psum_value(3, 1,  -6);
            check_psum_value(3, 2,  15);
            check_psum_value(3, 3,   3);
        end
    endtask

    task check_wave2_results;
        begin
            for (i = 0; i < ARRAY_SIZE; i = i + 1) begin
                for (j = 0; j < ARRAY_SIZE; j = j + 1) begin
                    check_psum_value(i, j,
                                     (row_wave1[i] * col_wave1[j]) +
                                     (row_wave2[i] * col_wave2[j]));
                end
            end
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cycle_count <= 0;
        end else begin
            cycle_count <= cycle_count + 1;
        end
    end

    always @(posedge clk) begin
        $display("T=%0t cycle=%0d clear_acc=%0b enable=%0b a_valid=%b b_valid=%b mac_fire=%b",
                 $time, cycle_count, clear_acc, enable, a_row_valid, b_col_valid, pe_mac_fire_flat);
    end

    initial begin
        row_wave1[0] =  1;  row_wave1[1] =  2;  row_wave1[2] = -1;  row_wave1[3] =  3;
        col_wave1[0] =  4;  col_wave1[1] = -2;  col_wave1[2] =  5;  col_wave1[3] =  1;

        row_wave2[0] =  1;  row_wave2[1] =  1;  row_wave2[2] =  1;  row_wave2[3] =  1;
        col_wave2[0] =  1;  col_wave2[1] =  1;  col_wave2[2] =  1;  col_wave2[3] =  1;

        rst_n = 1'b0;
        clear_acc = 1'b0;
        enable = 1'b0;
        cycle_count = 0;
        clear_stream_inputs;

        #12;
        rst_n = 1'b1;

        // Start with a clean accumulator state before injecting any streams.
        @(negedge clk);
        clear_acc = 1'b1;
        enable = 1'b1;
        clear_stream_inputs;

        @(negedge clk);
        clear_acc = 1'b0;

        // Wave 1:
        // Row i and column i are injected on the same step.
        // Registered forwarding makes them meet at PE(row, col) after row+col hops.
        for (step = 0; step < (2*ARRAY_SIZE); step = step + 1) begin
            @(negedge clk);
            drive_skewed_outer_product_step(step, 1);
        end

        @(posedge clk);
        #1;
        check_wave1_results();
        $display("[PASS] Wave 1 produced the expected outer-product pattern across the full mesh.");

        // Wave 2 should accumulate on top of the existing PE-local partial sums.
        for (step = 0; step < (2*ARRAY_SIZE); step = step + 1) begin
            @(negedge clk);
            drive_skewed_outer_product_step(step, 2);
        end

        @(posedge clk);
        #1;
        check_wave2_results();
        $display("[PASS] Wave 2 accumulated correctly on every PE.");

        // clear_acc should zero all output-stationary accumulators in one cycle.
        @(negedge clk);
        clear_acc = 1'b1;
        clear_stream_inputs;

        @(posedge clk);
        #1;
        for (i = 0; i < ARRAY_SIZE; i = i + 1) begin
            for (j = 0; j < ARRAY_SIZE; j = j + 1) begin
                check_psum_value(i, j, 0);
            end
        end
        $display("[PASS] clear_acc reset all PE accumulators.");

        @(negedge clk);
        clear_acc = 1'b0;
        clear_stream_inputs;

        #20;
        $display("[PASS] All systolic array tests completed successfully.");
        $finish;
    end

endmodule
