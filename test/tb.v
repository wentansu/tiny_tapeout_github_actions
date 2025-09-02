`default_nettype none
`timescale 1ns / 1ps

module tb ();

  // Parameters for reference
  localparam STATE_NUM       = 16;
  localparam INSTRUCTION_NUM = 4;
  localparam DATA_REG        = 4;
  localparam DATA_SIZE       = 4;

  // ------------------------------------------------------------------
  // DUT interface signals
  // ------------------------------------------------------------------
  reg         clk;
  reg         rst_n;
  reg         ena;
  reg  [7:0]  ui_in;
  reg  [7:0]  uio_in;
  wire [7:0]  uo_out;
  wire [7:0]  uio_out;
  wire [7:0]  uio_oe;

  // DUT instance
  tt_um_imtiaz_jtag user_project (
      .ui_in   (ui_in),    // Dedicated inputs
      .uo_out  (uo_out),   // Dedicated outputs
      .uio_in  (uio_in),   // IOs: Input path
      .uio_out (uio_out),  // IOs: Output path
      .uio_oe  (uio_oe),   // IOs: Enable path (active high: 0=input, 1=output)
      .ena     (ena),      // enable - goes high when design is selected
      .clk     (clk),      // clock
      .rst_n   (rst_n)     // not reset
  );

  // ------------------------------------------------------------------
  // Clock generation
  // ------------------------------------------------------------------
  initial begin
    clk = 0;
    forever #5 clk = ~clk; // 100 MHz
  end

  // ------------------------------------------------------------------
  // Utility: reverse bit order
  // ------------------------------------------------------------------
  function automatic [DATA_SIZE-1:0] reverse_bits(input [DATA_SIZE-1:0] val);
    integer i;
    begin
      for (i = 0; i < DATA_SIZE; i++) begin
        reverse_bits[i] = val[DATA_SIZE-1-i];
      end
    end
  endfunction

  // ------------------------------------------------------------------
  // Scoreboard check
  // ------------------------------------------------------------------
  task automatic check_result(
      input [DATA_SIZE-1:0] exp_output,
      input [DATA_REG-1:0]  exp_tdr);
    begin
      @(posedge clk);

      if (uo_out[4:1] !== exp_tdr) begin
        $error("[%0t] Mismatch TDR: Expected=0x%b, Got=0x%b",
               $time, exp_tdr, uo_out[4:1]);
      end else begin
        $display("[%0t] [PASS] TDR matches expected: 0x%b",
                 $time, uo_out[4:1]);
      end
    end
  endtask

  // ------------------------------------------------------------------
  // Stimulus
  // ------------------------------------------------------------------
  initial begin
      $dumpfile("waveform.vcd");
      $dumpvars(0, tb);
  end
  
  initial begin
    // // Dump waves
    // $dumpfile("tb.vcd");
    // $dumpvars(0, tb);

    // Initialize
    rst_n   = 0;
    ena     = 1;   // use internal sequencer
    ui_in   = 8'h00;
    uio_in  = 8'h00;

    // Hold reset a few cycles
    repeat (4) @(posedge clk);
    rst_n = 1;

    // Waiting enough cycles for full internal TMS/TDI sequence
    repeat (80) @(posedge clk);
    check_result(reverse_bits(4'b1001), 4'b1111);

    $display("Simulation completed");
    $finish;
  end

endmodule