# RAM clear testbench

`tb_ram_clear.v` tests `rtl/ram_clear.v` together with a copy of the RAM write-port
mux from `BBCMicro.sv` (keep the two in step), over the full 12 x 16K RAM array:

- busy lasts exactly 196,608 clocks (about 2 ms at 96 MHz) and reset is held throughout
- every byte reads back zero afterwards: co-processor RAM, sideways RAM slots 4-7,
  main memory, Master filing system/private/shadow RAM and the SWMMFS workspace
- CPU writes work normally after the clear, and write strobes during it are ignored
- a trigger held high longer than the clear runs it once only

Run (OSS CVC):

    cvc64 tb_ram_clear.v ../../rtl/ram_clear.v
    ./cvcsim
