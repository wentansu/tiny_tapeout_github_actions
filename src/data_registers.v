module data_registers #(
  parameter DATA_REG = 4
) (
  input  wire                 tclk,
  input  wire                 trst_n,
  input  wire                 serial_input,     // TDI
  input  wire                 shift_en,
  input  wire                 capture_en,
  input  wire                 update_en,
  input  wire [DATA_REG-1:0]  parallel_inputs,  // same size as data registers

  output wire                 serial_output,    // TDO
  output reg  [DATA_REG-1:0]  data_regs         // scan chain contents
);

  reg [DATA_REG-1:0] shadow_data_regs;

  // One process for posedge tclk + async reset
  always @(posedge tclk or negedge trst_n) begin
    if (!trst_n) begin
      data_regs        <= {DATA_REG{1'b0}};
      shadow_data_regs <= {DATA_REG{1'b0}};
    end else begin
      // capture/shift into scan chain
      if (capture_en)
        data_regs <= parallel_inputs;
      else if (shift_en)
        data_regs <= {serial_input, data_regs[DATA_REG-1:1]};

      // update shadow on command
      if (update_en)
        shadow_data_regs <= data_regs;
    end
  end

  assign serial_output = data_regs[0];

endmodule
