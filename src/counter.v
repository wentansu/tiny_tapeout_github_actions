module counter4bit (
    input wire clk,
    input wire rst,         // Synchronous reset
    input wire en,          // Enable counting
    input wire load,        // Load signal
    input wire [3:0] data_in, // Data to load
    output reg [3:0] count   // 4-bit counter output
);

    always @(posedge clk) begin
        if (rst) begin
            count <= 4'b0000;
        end else if (load) begin
            count <= data_in;
        end else if (en) begin
            count <= count + 1;
        end
    end

endmodule
