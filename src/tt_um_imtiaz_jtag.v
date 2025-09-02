`default_nettype none

module tt_um_imtiaz_jtag (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // Bidirectional inputs
    output wire [7:0] uio_out,  // Bidirectional outputs
    output wire [7:0] uio_oe,   // Bidirectional output enable (1 = output, 0 = input)
    input  wire       clk,      // Clock (map to TCK)
    input  wire       rst_n,    // Active-low reset (map to TRST_N)
    input  wire       ena       // Enable: 1=use internal sequencer, 0=use external pins
);

  // ---------------------------------------------------------------------------
  // Parameters 
  // ---------------------------------------------------------------------------
  parameter int STATE_NUM        = 16;
  parameter int INSTRUCTION_NUM  = 4;
  parameter int DATA_REG         = 4;
  parameter int DATA_SIZE        = 4;

  // data parameters
  // TEST_MODE is now 4 bits wide (one-hot or constant pattern)
  parameter [INSTRUCTION_NUM-1:0] TEST_MODE       = 4'b0001;
  parameter [3:0] PARALLEL_INPUTS = 4'b1111;

  // sequencing parameters
  localparam int FIXED_LEN   = 18;
  localparam int TMS_SEQ_LEN = FIXED_LEN + DATA_REG + INSTRUCTION_NUM - 1;
  localparam int INSTR_START = 10;
  localparam int INSTR_END   = INSTR_START + INSTRUCTION_NUM;
  localparam int DR_START    = INSTR_END + 5;
  localparam int DR_END      = DR_START + DATA_REG;

  // Default TMS sequence constant
  localparam [TMS_SEQ_LEN-1:0] DEFAULT_TMS = {
        5'b11111,                 // Test-Logic-Reset
        5'b01100,                 // go to Shift-IR path
        {INSTRUCTION_NUM{1'b0}},  // IR shift clocks
        5'b11100,                 // exit/update IR -> DR path
        {(DATA_REG-1){1'b0}},     // DR shift clocks
        3'b110                    // exit/update DR
  };

  // ---------------------------------------------------------------------------
  // Internal / External selection
  // ---------------------------------------------------------------------------
  wire use_internal = ena;

  // parallel inputs (4-bit) selection
  wire [3:0] parallel_inputs_ext = ui_in[5:2];
  wire [3:0] parallel_inputs_sel = use_internal ? PARALLEL_INPUTS : parallel_inputs_ext;

  // For IR instruction bits (now 4 bits wide)
  wire [INSTRUCTION_NUM-1:0] test_mode = TEST_MODE;

  // ---------------------------------------------------------------------------
  // Internal sequencer signals 
  // ---------------------------------------------------------------------------
  reg  tms_int, tdi_int;
  wire tdo;

  reg  [DATA_SIZE-1:0] output_data;
  reg  [$clog2(TMS_SEQ_LEN)-1:0]          tmsIDX;
  reg  [$clog2(DATA_SIZE)-1:0]            tdiIDX, tdoIDX;
  reg  [$clog2(INSTRUCTION_NUM)-1:0]      instructionIDX;

  // ---------------------------------------------------------------------------
  // TAP instance connections
  // ---------------------------------------------------------------------------
  wire tms_mux = use_internal ? tms_int     : ui_in[1]; // external TMS on ui_in[1]
  wire tdi_mux = use_internal ? tdi_int     : ui_in[0]; // external TDI on ui_in[0]

  wire [DATA_REG-1:0] tdr_data_outs;

  jtag_tap_controller #(
    .STATE_NUM       (STATE_NUM),
    .INSTRUCTION_NUM (INSTRUCTION_NUM),
    .DATA_REG        (DATA_REG)
  ) jtag0 (
    .tclk            (clk),
    .trst_n          (rst_n),
    .tdi             (tdi_mux),
    .tms             (tms_mux),
    .tdo             (tdo),
    .parallel_inputs (parallel_inputs_sel),
    .tdr_data_outs   (tdr_data_outs)
  );

  // ---------------------------------------------------------------------------
  // Internal sequencer: Drive TMS/TDI on negedge clk 
  // ---------------------------------------------------------------------------
  always @(negedge clk or negedge rst_n) begin
    if (!rst_n) begin
      tmsIDX         <= '0;
      tdiIDX         <= '0;
      tdoIDX         <= '0;
      instructionIDX <= '0;
      tms_int        <= 1'b1;
      tdi_int        <= 1'b0;
    end else begin
      if (use_internal) begin
        tms_int <= DEFAULT_TMS[TMS_SEQ_LEN-1 - tmsIDX];

        if ((tmsIDX >= INSTR_START) && (tmsIDX < INSTR_END)) begin
          tdi_int        <= test_mode[instructionIDX];
          instructionIDX <= instructionIDX + 1'b1;
        end else if ((tmsIDX >= DR_START) && (tmsIDX < DR_END)) begin
          tdi_int <= parallel_inputs_sel[tdiIDX];
          tdiIDX  <= tdiIDX + 1'b1;
        end else begin
          tdi_int <= 1'b0;
        end

        if (tmsIDX != TMS_SEQ_LEN-1) begin
          tmsIDX <= tmsIDX + 1'b1;
        end
      end else begin
        // In external mode, reset internal indices
        tms_int        <= 1'b1;
        tdi_int        <= 1'b0;
        tmsIDX         <= '0;
        tdiIDX         <= '0;
        instructionIDX <= '0;
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Sample TDO on negedge to match JTAG shift-out timing
  // ---------------------------------------------------------------------------
  always @(negedge clk or negedge rst_n) begin
    if (!rst_n) begin
      output_data <= '0;
      tdoIDX      <= '0;
    end else begin
      if (use_internal) begin
        if ((tmsIDX > DR_START) && (tmsIDX <= DR_END)) begin
          if ($unsigned(tdoIDX) < DATA_SIZE) begin
            output_data[DATA_SIZE-1-tdoIDX] <= tdo;
            tdoIDX <= tdoIDX + 1'b1;
          end
        end
      end else begin
        output_data <= output_data; // hold
        tdoIDX      <= '0;
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Tiny Tapeout pin mapping
  // ---------------------------------------------------------------------------
  assign uio_oe  = 8'b0;
  assign uo_out[0]   = tdo;                    // TDO
  assign uo_out[4:1] = tdr_data_outs[3:0];     // expose DR bits
  assign uo_out[7:5] = 3'b000;                 // unused
  assign uio_out     = 8'b0000_0000;           // bidirs not used

endmodule
