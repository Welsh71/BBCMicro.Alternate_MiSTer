# CLAUDE.md

Notes for Claude Code working in this repository. Read this before changing anything.

## The project

- **BBCMicro.Alternate**: an enhanced BBC Micro Model B / Master 128 core for MiSTer (DE10-Nano),
  maintained by Paul Stewart (GitHub **Welsh71**). Repo: https://github.com/Welsh71/BBCMicro.Alternate_MiSTer
  (renamed from `Welsh71BeebFpga_MiSTer` in Nov 2026; GitHub redirects the old URL).
- Naming, used everywhere: core/OSD name and `games/`/`config/`/`saves/` folder `BBCMicro.Alternate`;
  release file `BBCMicro.Alternate._YYYYMMDD.rbf`; OSD version line `Alternate-YYMMDD`; Quartus
  project/revision and top file `BBCMicro_Alternate` (`.qpf/.qsf/.sv/.sdc/.srf`; no dot, Quartus
  doesn't like dots in project names). The `emu|BBCMicro|...` paths in the SDC are the core's
  *instance* name inside `emu`, not the project name; leave them.
- It continues sharpie7/BeebFpga_MiSTer (inactive since 2022; no PRs go there), which put
  hoglet67's BeebFPGA emulation on the official core's harness. The official core
  (MiSTer-devel/BBCMicro_MiSTer) is a separate project and is left alone.
- Hardware: DE10-Nano with SDRAM board, I/O board (secondary SD card, ADC used for tape input).
- PC: Windows 10, **Quartus Prime 17.0.2 Lite**. MiSTer cores must be built with 17.0.x.
  Working copy: `C:\fpga\BeebFpga_MiSTer_2026` (to be renamed `C:\fpga\BBCMicro.Alternate_MiSTer`). Test images (`.uef`, `.ssd`, `.dsd`) are in `C:\fpga`.

## Branches and releases

- `main` = the released code (currently v20261104: RAM clear, core name `BBCMicro.Alternate`,
  Mode 7 default, timing fixes). Keep it equal to the latest release so its Readme matches the
  released `.rbf`.
- Unreleased work stacks on branches and is released together, because Paul doesn't want to
  push too many releases on users. `swram-clear` and `alt-config-names` are fully released
  in v20261104. Unreleased:
  - `m7-576i-field` (from `main`): Mode 7 with *M7 Analogue Video* = 576i looked jagged on
    HDMI because `VGA_F1` had the wrong field polarity after the hoglet67 6845 port; now
    `VGA_F1` follows `odd_field`. Tested on hardware (HDMI) 5 Nov 2026: smooth, same as 576p.
  - **Branch new work from the newest unreleased branch**, not from `main`.
- `old-main` and `PSMain` are history. Never push `old-main`.
- Release file name: `BBCMicro.Alternate._YYYYMMDD.rbf` (rename `output_files\BBCMicro_Alternate.rbf`).
  For each release, Claude prepares the renamed `.rbf`, release notes and a pre-filled
  "new release" link, and commits the same `.rbf` to `releases/` (check checksums match).
  **Paul creates the tags and GitHub releases himself.**
- Commit identity: `Welsh71 <101995724+Welsh71@users.noreply.github.com>` (already set as the
  repo-level git config). Never use a personal email address.
- `BBCMicro_Alternate.qsf` has a deliberate uncommitted local change (`SMART_RECOMPILE OFF`). Don't commit it
  and don't revert it.

## Building and checking timing

1. Clean build after any framework, constraint or placement-sensitive change: run `clean.bat`,
   then `quartus_sh --flow compile BBCMicro_Alternate` (Quartus 17.0 `bin64` must be on PATH;
   `scripts/report_failing_paths.bat` shows the usual install locations). A build takes a while.
2. Timing report: run `quartus_sta -t scripts\report_failing_paths.tcl` directly (the `.bat`
   ends with `pause`, which would hang a non-interactive run). It runs single-threaded on
   purpose: multi-threaded quartus_sta crashes on Quartus 17.
3. Check, and compare with the last good build:
   - `output_files\fail_hold.txt` and `fail_setup_summary.txt` should say "Nothing to report".
   - `BBCMicro_Alternate.sta.summary`: setup and hold slack for the emu PLL (clk_sys, 96 MHz) and pll_hdmi.
   - `fail_setup_worst15.txt` for the worst paths.
   - M10K blocks and LABs in `BBCMicro_Alternate.fit.rpt` (block RAM is nearly full: about 545/553 M10K).
   - Count "Ignored filter" in `BBCMicro_Alternate.sta.rpt`: should be 0. An SDC line that matches nothing
     silently does nothing.
   A compile that "succeeds" with negative slack is a failed build. Even a trivial source change can
   move placement and expose a marginal path, so check every build.
4. Last good build: `m7-576i-field` (3bd76f9), 5 Nov 2026: core setup +0.383 ns, hold +0.429 ns,
   HDMI +0.451/+0.260 ns, 545 M10K, 3,205 LABs. Worst paths: `hps_io|img_size -> vsd_sel`,
   then `tape_store/inflate`. The `disk_osd|ce_r` path below didn't show this time, but it is
   placement-dependent, so keep watching it.
   Before that: Mode 7 default (OSD lists 7,0..6), 4 Nov 2026: core setup +0.167 ns, hold
   +0.434 ns, HDMI +0.410/+0.260 ns, 545 M10K. Worst paths are now `ttxt_clken`/`vid_clken ->
   disk_osd|ce_r` with about -6.5 ns clock skew: watch this one; registering `ce_pix` before
   `disk_osd` would likely win the margin back.
   Before that: project renamed to `BBCMicro_Alternate`, 4 Nov 2026:
   core setup +0.659 ns, hold +0.426 ns, HDMI +0.450/+0.216 ns, 545 M10K, 3,244 LABs. Worst core
   paths: `ext_nWE -> ram_we_r` and the framework's `ascal` (sys/, not ours to edit).
   Before that: 72f7f8a (drive-sound SDC exceptions) +0.629 ns; `swram-clear` (2 Nov) +0.370 ns;
   70cddf5 alone +0.203 ns.
5. If the compile flow's own TimeQuest step crashes ("Fatal Error: Access Violation"), the `.rbf`
   is already written by the Assembler. Kill the hung `quartus_sta`/`quartus_sh` and rerun
   `quartus_sta --parallel=1 BBCMicro_Alternate -c BBCMicro_Alternate` to regenerate the
   `.sta.summary`/`.sta.rpt`, then the report script.

## Timing lessons from this core

- clk_sys is 96 MHz (10.4 ns). Register wide combinational ORs before large fan-outs (the
  tape ADC reset is registered for this reason), and keep indexed muxes + adders + compares out of
  single cycles (see `rtl/drive_sound.v`'s precomputed `pos_nx`/`wrap`).
- Signals crossing from the gated clk_48 domain are captured into clk_sys first.
- Never make the main ROM a non-power-of-two size: a 17-bank ROM made Quartus mis-plan block
  RAM and push the OSD/HQ2x memories into flip-flops. DNFS 1.20 is its own 16K ROM for this reason.
- Any NMI re-assertion must stay low for at least one CPU cycle; the T65 samples NMI once per cycle.

## Code rules

- **Never edit `sys/`.** Replace it wholesale from Template_MiSTer when updating the framework.
- Add new source files to `files.qip`, not through the Quartus IDE.
- `Readme.md` and `files.qip` use **CRLF** (files.qip has one stray LF line, `rtl/rtc_chip.v`);
  RTL files use LF. Preserve line endings when editing. Git Bash's `sed -i` silently converts
  CRLF files to LF, so edit them with the Edit tool or Python in binary mode.
- CONF_STR (OSD menu) text: never use a comma inside a menu label (a comma ends the field), and keep
  labels short (about 24 characters).
- Status bits in use: 0, 2-16, 21-22, 25-30, 32-39. Bit 39 is the RAM-clear trigger.
- Core name (first CONF_STR field) is `BBCMicro.Alternate`. Main_MiSTer names `config/` files,
  `saves/` and the `games/` folder after it, so don't change it casually.
- Licences: b-em is GPL v2 and may be used as a reference; beebjit is GPL v3 and is only used to
  check behaviour, never copied. BeebEm's drive sound samples are GPL v2.
- Update the Readme when user-visible behaviour changes (menus, folders, file names).

## Simulation

Testbenches live in `sim/` (`fdc`, `osd`, `tape`, `i8271`, `sound`, `ramclr`), each with a README.
They were written for OSS CVC (Linux). On Windows, use WSL with CVC, or Icarus Verilog (`iverilog`),
which may need small syntax changes. Known CVC quirks: writes to bit/part-selects of array words are
dropped, `<<<` behaved as a right shift, and C-style `reg [7:0] ram[N]` with a parameter N is
rejected (use `[0:N-1]`). Run a feature's testbench after changing its RTL.

## Hardware testing (Paul does this)

Test on both Model B and Master 128: MMFS and DFS (DFS 1.2 with the 8271 and DFS 1770 on the Model B),
tape loading from compressed and uncompressed UEFs, drive sounds, Mode 7, and graphics-heavy games
such as Elite and Revs.

## Open items and ideas

- Not implemented: saving to tape; Master CMOS persistence (idea: an `SC3` image slot); Video NuLA.
- ICE (AtomBusMon) build not rebuilt on the new framework.
- Still to check with the 8271: `.dsd` side 2, MMFS + DFS 1.2 combinations.
- Ideas: SCSI hard disc for ADFS, Z80 second processor (T80 already in the tree), copy-protected `.fsd`.
- A fuller project history is kept in the claude.ai Project briefing
  (`claude/BBC_Micro_core_briefing.md`); this file is the working summary.
