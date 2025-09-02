module jtag_tap_controller #(
  parameter STATE_NUM       = 16,
  parameter INSTRUCTION_NUM = 4,
  parameter DATA_REG        = 5
) (
  input  wire                 tclk,
  input  wire                 trst_n,
  input  wire                 tdi,
  input  wire                 tms,

  output wire                 tdo,

  input  wire [DATA_REG-1:0]  parallel_inputs,
  output wire [DATA_REG-1:0]  tdr_data_outs
);

  // IR encoding
  localparam IR_WIDTH = $clog2(INSTRUCTION_NUM);
  localparam [IR_WIDTH-1:0] EXTEST = 2'b00;
  localparam [IR_WIDTH-1:0] SAMPLE = 2'b01;
  localparam [IR_WIDTH-1:0] BYPASS = 2'b10;
  localparam [IR_WIDTH-1:0] IDCODE = 2'b11;

  // TAP states
  localparam RESET         = 4'b0000;
  localparam Run_Test_IDLE = 4'b0001;
  localparam SELECT_DR     = 4'b0010;
  localparam SELECT_IR     = 4'b0011;

  localparam CAPTURE_IR    = 4'b0100;
  localparam SHIFT_IR      = 4'b0101;
  localparam EXIT1_IR      = 4'b0110;
  localparam PAUSE_IR      = 4'b0111;

  localparam EXIT2_IR      = 4'b1000;
  localparam UPDATE_IR     = 4'b1001;
  localparam CAPTURE_DR    = 4'b1010;
  localparam SHIFT_DR      = 4'b1011;

  localparam EXIT1_DR      = 4'b1100;
  localparam PAUSE_DR      = 4'b1101;
  localparam EXIT2_DR      = 4'b1110;
  localparam UPDATE_DR     = 4'b1111;

  // state
  reg [$clog2(STATE_NUM)-1:0] state, next_state;

  // regs
  reg  [IR_WIDTH-1:0] reg_ir, shadow_reg_ir;
  wire [DATA_REG-1:0] reg_bsr;
  reg                 reg_bypass;

  // enables (combinational)
  reg shift_en, capture_en, update_en;

  wire serial_output;
  reg  tdo_reg;

  // Boundary scan register
  data_registers #(
    .DATA_REG(DATA_REG)
  ) bsr0 (
    .tclk(tclk),
    .trst_n(trst_n),
    .serial_input(tdi),
    .shift_en(shift_en),
    .capture_en(capture_en),
    .update_en(update_en),
    .parallel_inputs(parallel_inputs),
    .serial_output(serial_output),
    .data_regs(reg_bsr)
  );

  // Sequential: state, IR/bypass, and TDO all in ONE process
  always @(posedge tclk or negedge trst_n) begin
    if (!trst_n) begin
      reg_bypass     <= 1'b0;
      reg_ir         <= SAMPLE;
      shadow_reg_ir  <= SAMPLE;
      state          <= RESET;
      tdo_reg        <= 1'b0;
    end else begin
      // state register
      state <= next_state;

      // IR/BYPASS updates based on current state
      case (state)
        CAPTURE_IR: reg_ir <= SAMPLE; // preload (per simplified model)
        SHIFT_IR:   reg_ir <= {tdi, reg_ir[IR_WIDTH-1:1]};
        UPDATE_IR:  shadow_reg_ir <= reg_ir;

        CAPTURE_DR: if (shadow_reg_ir == BYPASS)
                       reg_bypass <= 1'b0;
        SHIFT_DR:   if (shadow_reg_ir == BYPASS)
                       reg_bypass <= tdi;

        default: /* hold */;
      endcase

      // TDO register update
      if (state == SHIFT_IR)
        tdo_reg <= reg_ir[0];
      else if ((state == SHIFT_DR) && (shadow_reg_ir == BYPASS))
        tdo_reg <= reg_bypass;
      else if (state == SHIFT_DR)
        tdo_reg <= serial_output;
      else
        tdo_reg <= 1'b0;
    end
  end

  // Combinational: next state and enables
  always @* begin
    // safe defaults each cycle
    shift_en   = 1'b0;
    capture_en = 1'b0;
    update_en  = 1'b0;
    next_state = state;

    case (state)
      RESET:         begin next_state = tms ? RESET     : Run_Test_IDLE; end
      Run_Test_IDLE: begin next_state = tms ? SELECT_DR : Run_Test_IDLE; end
      SELECT_DR:     begin next_state = tms ? SELECT_IR : CAPTURE_DR;    end
      SELECT_IR:     begin next_state = tms ? RESET     : CAPTURE_IR;    end

      CAPTURE_IR:    begin next_state = tms ? EXIT1_IR  : SHIFT_IR;      end
      SHIFT_IR:      begin next_state = tms ? EXIT1_IR  : SHIFT_IR;      end
      EXIT1_IR:      begin next_state = tms ? UPDATE_IR : PAUSE_IR;      end
      PAUSE_IR:      begin next_state = tms ? EXIT2_IR  : PAUSE_IR;      end
      EXIT2_IR:      begin next_state = tms ? UPDATE_IR : SHIFT_IR;      end
      UPDATE_IR:     begin next_state = tms ? SELECT_DR : Run_Test_IDLE; end

      CAPTURE_DR: begin
        // capture into BSR unless BYPASS
        capture_en = (shadow_reg_ir != BYPASS);
        next_state = tms ? EXIT1_DR : SHIFT_DR;
      end

      SHIFT_DR: begin
        // shift through BSR unless BYPASS
        shift_en   = (shadow_reg_ir != BYPASS);
        next_state = tms ? EXIT1_DR : SHIFT_DR;
      end

      EXIT1_DR:   begin next_state = tms ? UPDATE_DR : PAUSE_DR; end
      PAUSE_DR:   begin next_state = tms ? EXIT2_DR  : PAUSE_DR; end
      EXIT2_DR:   begin next_state = tms ? UPDATE_DR : SHIFT_DR; end
      UPDATE_DR: begin
        // update from BSR unless BYPASS
        update_en  = (shadow_reg_ir != BYPASS);
        next_state = tms ? SELECT_DR : Run_Test_IDLE;
      end

      default: begin
        next_state = RESET;
      end
    endcase
  end

  assign tdo           = tdo_reg;
  assign tdr_data_outs = reg_bsr;

endmodule
