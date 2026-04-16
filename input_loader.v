`timescale 1ns / 1ps

// -----------------------------------------------------------------------------
// Input Loader
// - Latches one input tile of A and B per run.
// - Emits skewed operand streams that match the systolic array timing.
// - Provides a stream-cycle debug counter for waveform and trace inspection.
// -----------------------------------------------------------------------------
module input_loader #(
    parameter ARRAY_SIZE = 4,
    parameter DATA_WIDTH = 8
) (
    input clk,
    input rst_n,
    input load_en,
    input stream_en,
    input [ARRAY_SIZE*ARRAY_SIZE*DATA_WIDTH-1:0] a_matrix_flat,
    input [ARRAY_SIZE*ARRAY_SIZE*DATA_WIDTH-1:0] b_matrix_flat,
    output reg [ARRAY_SIZE*DATA_WIDTH-1:0] a_row_data_flat,
    output reg [ARRAY_SIZE-1:0] a_row_valid,
    output reg [ARRAY_SIZE*DATA_WIDTH-1:0] b_col_data_flat,
    output reg [ARRAY_SIZE-1:0] b_col_valid,
    output reg [15:0] stream_cycle_dbg
);

    reg [ARRAY_SIZE*ARRAY_SIZE*DATA_WIDTH-1:0] a_matrix_reg;
    reg [ARRAY_SIZE*ARRAY_SIZE*DATA_WIDTH-1:0] b_matrix_reg;

    integer row_idx;
    integer col_idx;
    integer a_elem_idx;
    integer b_elem_idx;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_matrix_reg      <= {(ARRAY_SIZE*ARRAY_SIZE*DATA_WIDTH){1'b0}};
            b_matrix_reg      <= {(ARRAY_SIZE*ARRAY_SIZE*DATA_WIDTH){1'b0}};
            a_row_data_flat   <= {(ARRAY_SIZE*DATA_WIDTH){1'b0}};
            a_row_valid       <= {ARRAY_SIZE{1'b0}};
            b_col_data_flat   <= {(ARRAY_SIZE*DATA_WIDTH){1'b0}};
            b_col_valid       <= {ARRAY_SIZE{1'b0}};
            stream_cycle_dbg  <= 16'd0;
        end else begin
            if (load_en) begin
                // Capture one full matrix tile per run.
                a_matrix_reg     <= a_matrix_flat;
                b_matrix_reg     <= b_matrix_flat;
                stream_cycle_dbg <= 16'd0;
            end

            if (stream_en) begin
                for (row_idx = 0; row_idx < ARRAY_SIZE; row_idx = row_idx + 1) begin
                    // A is stored row-major:
                    // A[row_idx][k] lives at flat index row_idx*ARRAY_SIZE + k.
                    // Row 'row_idx' emits element A[row_idx][stream_cycle-row_idx] when valid.
                    if ((stream_cycle_dbg >= row_idx) &&
                        ((stream_cycle_dbg - row_idx) < ARRAY_SIZE)) begin
                        a_elem_idx = (row_idx * ARRAY_SIZE) + (stream_cycle_dbg - row_idx);
                        a_row_data_flat[(row_idx*DATA_WIDTH) +: DATA_WIDTH]
                            <= a_matrix_reg[(a_elem_idx*DATA_WIDTH) +: DATA_WIDTH];
                        a_row_valid[row_idx] <= 1'b1;
                    end else begin
                        a_row_data_flat[(row_idx*DATA_WIDTH) +: DATA_WIDTH] <= {DATA_WIDTH{1'b0}};
                        a_row_valid[row_idx] <= 1'b0;
                    end
                end

                for (col_idx = 0; col_idx < ARRAY_SIZE; col_idx = col_idx + 1) begin
                    // B is also stored row-major:
                    // B[k][col_idx] lives at flat index k*ARRAY_SIZE + col_idx.
                    // Column 'col_idx' emits element B[stream_cycle-col_idx][col_idx] when valid.
                    if ((stream_cycle_dbg >= col_idx) &&
                        ((stream_cycle_dbg - col_idx) < ARRAY_SIZE)) begin
                        b_elem_idx = ((stream_cycle_dbg - col_idx) * ARRAY_SIZE) + col_idx;
                        b_col_data_flat[(col_idx*DATA_WIDTH) +: DATA_WIDTH]
                            <= b_matrix_reg[(b_elem_idx*DATA_WIDTH) +: DATA_WIDTH];
                        b_col_valid[col_idx] <= 1'b1;
                    end else begin
                        b_col_data_flat[(col_idx*DATA_WIDTH) +: DATA_WIDTH] <= {DATA_WIDTH{1'b0}};
                        b_col_valid[col_idx] <= 1'b0;
                    end
                end

                stream_cycle_dbg <= stream_cycle_dbg + 16'd1;
            end else begin
                // Drive zeros when the stream is idle so waveforms clearly show active windows.
                a_row_data_flat <= {(ARRAY_SIZE*DATA_WIDTH){1'b0}};
                a_row_valid     <= {ARRAY_SIZE{1'b0}};
                b_col_data_flat <= {(ARRAY_SIZE*DATA_WIDTH){1'b0}};
                b_col_valid     <= {ARRAY_SIZE{1'b0}};
            end
        end
    end

endmodule
