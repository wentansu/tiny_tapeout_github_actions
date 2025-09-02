# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles


# Utility: reverse bit order
def reverse_bits(val: int, size: int) -> int:
    result = 0
    for i in range(size):
        if (val >> i) & 1:
            result |= 1 << (size - 1 - i)
    return result


@cocotb.test()
async def test_project(dut):
    dut._log.info("Start JTAG test")

    # Set the clock period to 10 ns (100 MHz)
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    # Initialize
    dut.ena.value = 1       # use internal sequencer
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0

    # Enable VCD dumping
    cocotb.start_soon(dut._vcd_writer("tb.vcd"))

    # Hold reset a few cycles
    await ClockCycles(dut.clk, 4)
    dut.rst_n.value = 1

    # Wait enough cycles for full internal TMS/TDI sequence
    await ClockCycles(dut.clk, 80)

    # Expected values
    expected_tdr = 0b1111
    expected_output = reverse_bits(0b1001, 4)

    # Check result
    actual_tdr = int(dut.uo_out.value) >> 1 & 0b1111  # uo_out[4:1]
    dut._log.info(f"TDR observed = {actual_tdr:04b}, expected = {expected_tdr:04b}")

    assert actual_tdr == expected_tdr, (
        f"Mismatch TDR: expected {expected_tdr:04b}, got {actual_tdr:04b}"
    )

    dut._log.info("[PASS] TDR matches expected")

    dut._log.info("Simulation completed")