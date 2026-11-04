`ifndef AUX_PZT_CONFIG_VH
`define AUX_PZT_CONFIG_VH
// Nominal user specification: 5 V spans about 200 MHz, direction is NOT assumed.
// Board photograph labels DAC output +/-1 V. Use an external gain/offset stage
// before the PZT input. Calibrate the complete code -> PZT voltage transfer.
// EXAMPLES, NOT CALIBRATION: confirm analogue ranges before enabling the loop.
// Default /1 forwards 50 MHz; /10 gives 5 MHz. Neither is a measured beat value.
// Allowed: 1 (50 MHz ODDR forward) or an even integer >=2.
`define LO_DIVIDE 1
`define PZT_INIT_CODE 16'h8000
`define PZT_MIN_CODE  16'h7800
`define PZT_MAX_CODE  16'h8800
`define TARGET_FV_CODE  16'h8000
// 50 MHz * 0.5 s; replace after measuring F/V + auxiliary laser/PZT + thermal settling time.
`define UPDATE_CYCLES 25000000
`define SAMPLE_TIMEOUT_CYCLES 5000000
`define KP_Q16 4096
`define KI_Q16 256
`define KII_Q16 1
`define KD_Q16 128
`define D_FILTER_SHIFT 2
`define TELEMETRY_CYCLES 5000000
`define PZT_STEP_MAX 64
`define SCAN_STEP 64
`define LOCK_TOL 64
`define UNLOCK_TOL 256
`define LOCK_CONFIRM 8
`define UNLOCK_CONFIRM 3
`endif
