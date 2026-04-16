`timescale 1ns / 1ps

// -----------------------------------------------------------------------------
// Output Collector
// - Captures the final PE accumulator image at the end of a run.
// - Presents a stable flattened output matrix to the top level.
// - Generates a one-cycle c_valid pulse during collection.
// -----------------------------------------------------------------------------
module output_collector #(
    parameter ARRAY_SIZE = 4,
    parameter ACC_WIDTH  = 24
) (
    input clk,
    input rst_n,
    input collect_en,
    input [ARRAY_SIZE*ARRAY_SIZE*ACC_WIDTH-1:0] c_psum_flat_in,
    output reg [ARRAY_SIZE*ARRAY_SIZE*ACC_WIDTH-1:0] c_matrix_flat,
    output reg c_valid
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            c_matrix_flat <= {(ARRAY_SIZE*ARRAY_SIZE*ACC_WIDTH){1'b0}};
            c_valid       <= 1'b0;
        end else begin
            // c_psum_flat_in is row-major over PE outputs:
            // flat index = row * ARRAY_SIZE + col.
            if (collect_en) begin
                c_matrix_flat <= c_psum_flat_in;
            end

            // c_valid is a one-cycle event pulse for each completed run.
            c_valid <= collect_en;
        end
    end

endmodule
