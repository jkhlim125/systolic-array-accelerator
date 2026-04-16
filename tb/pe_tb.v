`timescale 1ns / 1ps

// -----------------------------------------------------------------------------
// PE Testbench
// - Verifies signed MAC behavior, valid gating, and clear_acc handling.
// - Exercises the PE in isolation before it is placed in the systolic mesh.
// -----------------------------------------------------------------------------
module pe_tb;

    parameter DATA_WIDTH = 8;
    parameter ACC_WIDTH  = 24;

    reg clk;
    reg rst_n;
    reg clear_acc;
    reg enable;
    reg signed [DATA_WIDTH-1:0] a_in;
    reg signed [DATA_WIDTH-1:0] b_in;
    reg a_valid_in;
    reg b_valid_in;

    wire signed [DATA_WIDTH-1:0] a_out;
    wire signed [DATA_WIDTH-1:0] b_out;
    wire a_valid_out;
    wire b_valid_out;
    wire signed [ACC_WIDTH-1:0] psum_out;
    wire mac_fire;

    pe #(
        .DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH(ACC_WIDTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .clear_acc(clear_acc),
        .enable(enable),
        .a_in(a_in),
        .b_in(b_in),
        .a_valid_in(a_valid_in),
        .b_valid_in(b_valid_in),
        .a_out(a_out),
        .b_out(b_out),
        .a_valid_out(a_valid_out),
        .b_valid_out(b_valid_out),
        .psum_out(psum_out),
        .mac_fire(mac_fire)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        $dumpfile("pe_tb.vcd");
        $dumpvars(0, pe_tb);
    end

    task apply_inputs;
        input signed [DATA_WIDTH-1:0] a_val;
        input signed [DATA_WIDTH-1:0] b_val;
        input a_valid_val;
        input b_valid_val;
        input clear_acc_val;
        input enable_val;
        begin
            a_in = a_val;
            b_in = b_val;
            a_valid_in = a_valid_val;
            b_valid_in = b_valid_val;
            clear_acc = clear_acc_val;
            enable = enable_val;
        end
    endtask

    task check_psum;
        input signed [ACC_WIDTH-1:0] expected;
        input [255:0] test_name;
        begin
            if (psum_out !== expected) begin
                $display("[FAIL] %0s at time %0t: expected psum=%0d, got psum=%0d",
                         test_name, $time, expected, psum_out);
                $finish;
            end else begin
                $display("[PASS] %0s at time %0t: psum=%0d", test_name, $time, psum_out);
            end
        end
    endtask

    always @(posedge clk) begin
        $display("T=%0t | rst_n=%0b clear_acc=%0b enable=%0b | a_in=%0d b_in=%0d | a_v=%0b b_v=%0b | mac_fire=%0b | a_out=%0d b_out=%0d | psum=%0d",
                 $time, rst_n, clear_acc, enable, a_in, b_in, a_valid_in, b_valid_in,
                 mac_fire, a_out, b_out, psum_out);
    end

    initial begin
        apply_inputs(0, 0, 1'b0, 1'b0, 1'b0, 1'b0);
        rst_n = 1'b0;

        #12;
        rst_n = 1'b1;

        // Test 1: basic positive MAC sequence.
        @(negedge clk);
        apply_inputs(3, 2, 1'b1, 1'b1, 1'b0, 1'b1);
        @(posedge clk);
        #1 check_psum(6, "basic_mac_step1");

        @(negedge clk);
        apply_inputs(4, 5, 1'b1, 1'b1, 1'b0, 1'b1);
        @(posedge clk);
        #1 check_psum(26, "basic_mac_step2");

        // Test 2: signed MAC sequence with negative operands.
        @(negedge clk);
        apply_inputs(-3, 4, 1'b1, 1'b1, 1'b0, 1'b1);
        @(posedge clk);
        #1 check_psum(14, "signed_mac_step1");

        @(negedge clk);
        apply_inputs(-2, -5, 1'b1, 1'b1, 1'b0, 1'b1);
        @(posedge clk);
        #1 check_psum(24, "signed_mac_step2");

        // Test 3: clear_acc must restart the local accumulation window.
        @(negedge clk);
        apply_inputs(7, 7, 1'b1, 1'b1, 1'b1, 1'b1);
        @(posedge clk);
        #1 check_psum(0, "clear_acc");

        @(negedge clk);
        apply_inputs(2, 3, 1'b1, 1'b1, 1'b0, 1'b1);
        @(posedge clk);
        #1 check_psum(6, "post_clear_mac");

        // Test 4: no accumulation should occur when either valid or enable is low.
        @(negedge clk);
        apply_inputs(9, 9, 1'b0, 1'b1, 1'b0, 1'b1);
        @(posedge clk);
        #1 check_psum(6, "a_valid_low_no_accumulate");

        @(negedge clk);
        apply_inputs(9, 9, 1'b1, 1'b0, 1'b0, 1'b1);
        @(posedge clk);
        #1 check_psum(6, "b_valid_low_no_accumulate");

        @(negedge clk);
        apply_inputs(9, 9, 1'b1, 1'b1, 1'b0, 1'b0);
        @(posedge clk);
        #1 check_psum(6, "enable_low_no_accumulate");

        @(negedge clk);
        apply_inputs(1, -8, 1'b1, 1'b1, 1'b0, 1'b1);
        @(posedge clk);
        #1 check_psum(-2, "final_signed_mac");

        $display("[PASS] All PE tests completed successfully.");
        #10;
        $finish;
    end

endmodule
