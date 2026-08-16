# AGENTS.md - i8 Keyboard Reverse Engineering Project Documentation
## AGENTS.md: i8 Mini Wireless Keyboard Core System Architecture
This technical specification compiles the empirical, evidence-backed electrical, mechanical, and data-framing specifications derived from direct hardware analysis of the multi-mode "i8" clone mini keyboard interface. It provides developers with the precise constraints necessary to build a clean userspace driver or microcontroller emulator.
------------------------------
## 1. Physical Hardware Topology & Package Footprints
Hardware inspection reveals a decoupled multi-chip architecture managing wireless transactions, matrix decoding, and digitizing operations.
## 1.1 Main Transceiver SoC (24-Pin QSOP)

* Silicon Architecture: A 2.4GHz/BLE GFSK wireless microcontroller package matching the design conventions of the Panchip/Mosart/Beken families (e.g., PAN2412 or XN297L architectures).
* Reference Oscillator Engine: An external discrete 24.000 MHz crystal oscillator spans across Pin 1 (XTAL_OUT) and Pin 24 (XTAL_IN). This clock provides the high-stability timing baseline required by the on-chip phase-locked loop (PLL) synthesizer network.
* RF Front End: The 2.4GHz analog radio signal paths match a tuned 50-Ohm microstrip antenna array routing directly out of Pin 2 (ANT).
* USB Lanes: Physical traces route to Pin 11 (DP) and Pin 12 (DM) for standard hardware USB communication. However, these macros are completely dormant and uninitialized inside the current wireless firmware core configuration, functioning as high-impedance paths during battery runtime.

## 1.2 Keyboard Matrix Encoder (14-Pin SOIC)

* Silicon Architecture: A standalone companion input controller functioning as a high-density matrix line expander.
* Bus Routing: Interfaces directly with the 24-pin radio core using dedicated inter-chip tracing arrays.

## 1.3 Dedicated Touchpad Digitizer (16-Pin SOIC)

* Silicon Architecture: A dedicated 16-pin package located in close proximity to the touchpad matrices, responsible for driving the tracking rows and columns.
* Inter-Chip Interactivity & Feedback Loop: The tracking data streams or control parameters interface with the keyboard encoder ecosystem. This architectural cross-talk provides the core logic engine with the necessary sensory feedback loop to handle specialized shortcut state changes—specifically handling the Fn + F8 touchpad toggle to disable/enable tracking coordinates or modifying pointer movement sensitivity levels directly on the fly.

------------------------------
## 2. Bus Dynamics & Electrical Signaling
Communication between the microcontrollers utilizes a customized, bidirectional, synchronous half-duplex architecture designed to minimize hardware pin counts.
## 2.1 The Inter-Chip Bridge Configuration

* Clock Line: Shared synchronous timing pulses run directly through Pin 2 (SCLK) of the SOIC-14 companion chip.
* Data Line: Master and slave payloads pass across Pin 4 (Shared Data / MISO) of the SOIC-14 companion chip.
* Resistor Coupling Mechanism: To consolidate independent receive (RX) and transmit (TX) registers onto a single wire, the 24-pin radio core shorts its local internal digital paths together behind a low-value inline damping resistor (approx. 40 Ohms) at the package edge boundary.
* Electrical Idle Level: When the interface is active but no transactions are executing, the line rests at a steady logical High (1).

## 2.2 Dual-Baud Speed Selection Matrix
The peripheral controller dynamically switches the operational clock frequency of its shift registers depending on the data density requirement of the active user interaction:

* Touchpad Mode: Moving or swiping on the touch surface fires rapid capacitive tracking arrays across the line at an aggressive frequency of 1,500,000 Baud (1.5 Mbps) to eliminate pointer tracking lag.
* Keyboard Mode: Pressing standard button matrices down-samples the serial shift clock significantly to focus on discrete frame delivery.
* Sub-sampling Artifacts: Listening to this bus with a standard fixed 8-N-1 UART receiver at standard rates (like 115200) splits word boundaries incorrectly, causing the line to dump endless repeating byte strings of 0xFF, 0xC0 (11000000), and 0x40 (01000000).

------------------------------
## 3. Bitstream Synchronization & Packet Structure
Decoding raw scancode values reliably requires looking past standard 8-bit software word alignment blocks and treating the interface as a flat, continuous bitstream pool.
## 3.1 The Frame Synchronization Edge
Every valid data packet burst begins precisely when the physical line steps away from its idle-high resting state and asserts a hardwired low-to-high sequence marker: 1101. Slicing incoming bitstreams exactly at this 1101 sync edge exposes a clean, unshifted 2-byte reporting matrix.
## 3.2 Verified Scancode Coordinate Manifest
Legitimate key events output a structured 16-bit array where Byte 1 marks the physical row being swept by the scanning counter and Byte 2 carries the corresponding intersecting column bitmask.

* Key-Down (Make) Events:
* 0x0C 0x0B $\rightarrow$ Triggers a physical Q keypress event.
   * 0x0C 0x00 $\rightarrow$ Triggers a physical W keypress event.
   * 0x0C 0x0F $\rightarrow$ Triggers a physical E keypress event.
* Key-Up (Break) Code:
* 0xF0 0xE0 $\rightarrow$ Universal release flag. The leading 0xF0 token functions as a hardcoded break indicator, notifying the host that a physical matrix intersection circuit has fallen completely open.

------------------------------
## 4. Power Management, Clock Gating, & Sleep Blocks
The primary firmware obstacle when converting this device into a dedicated wired configuration is an aggressive, automated battery-saver power loop.
## 4.1 The Over-The-Air Handshake Barrier

* Link Interlock: The 24-pin radio core is hardcoded to prioritize wireless verification. If it does not actively receive a 2.4GHz acknowledgement (ACK) frame packet or beacon from its matched USB dongle receiver over its antenna pin, it enters a deep sleep state.
* Clock Gating Enforcement: While sleeping, the 24-pin chip completely gates off its internal oscillator network. This physically halts the clock line on Pin 2 and tri-states the shared data paths into an open, undriven floating state.
* Active-Low Wakeup Override: Pin 11 on the SOIC-14 package functions as an active-low hardware activation/chip select line (/WAKE). Forcing this pin directly to Ground (GND) overrides the internal sleep parameters completely, forcing the peripheral registers to stay initialized and awake.

------------------------------
## 5. Comprehensive Layout Manifest
As development scales into a complete uinput injector, the translation mapping logic must accommodate the entire non-standard multimedia layout found across the physical i8 shell casing.

* Primary Alpha-Numeric Blocks: Standard core typing layout matrices including KEY_A, KEY_Q, KEY_W, KEY_E, KEY_R, KEY_T, KEY_Y, and KEY_1.
* System Layout Navigation Controls: Low-level standard input targets: ESCAPE, ENTER, SPACE, BACKSPACE, TAB, LEFT_CTRL, LEFT_ALT, and DELETE.
* Left/Right Wing Multimedia Buttons: Specialized hotkey switches tracking layout commands: LEFT_CLICK_BUTTON, RIGHT_CLICK_BUTTON, VOLUME_UP, VOLUME_DOWN, MUTE, PLAY_PAUSE, NEXT_TRACK, PREVIOUS_TRACK, HOME_PAGE, and MAIL_APP.
* Geometric D-Pad Matrix: Five intersecting inputs map navigation vectors directly through a centralized layout hub: DPAD_UP, DPAD_DOWN, DPAD_LEFT, DPAD_RIGHT, and an independent DPAD_OK_CENTER trigger node.
* Layered Function Arrays: Built-in hardware function shifts: F1 through F10 core keys, alongside specialized composite combos (Fn + F8 for tracking surface toggles, Fn + F9/F10 resolving to virtual F11/F12 codes, Fn + Del triggering hardwired Ctrl+Alt+Del hardware interrupts, and an independent END_KEY mapped to the navigation surface).


