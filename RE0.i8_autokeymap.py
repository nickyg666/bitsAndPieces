#!/usr/bin/env python3
import sys
import os
import time
import select

try:
    import serial
except ImportError:
    print("[!] Missing serial module. Run: apt install python3-serial")
    sys.exit(1)

SERIAL_PORT = "/dev/ttyS0"
BAUD_RATE = 115200

I8_KEY_LIST = [
    # Multimedia Shortcuts
    "LEFT_CLICK_BUTTON", "RIGHT_CLICK_BUTTON", "VOLUME_UP", "VOLUME_DOWN",
    "PLAY_PAUSE", "NEXT_TRACK", "PREVIOUS_TRACK", "MUTE", "HOME_PAGE", "MAIL_APP",

    # Navigation D-Pad Group
    "DPAD_UP", "DPAD_DOWN", "DPAD_LEFT", "DPAD_RIGHT", "DPAD_OK_CENTER",

    # Special Function / Mode Toggles
    "FN_FUNCTION_MODIFIER", "MOUSE_SENSITIVITY_TOGGLE", "TOUCHPAD_TOGGLE_FN_F8",

    # Core Matrix Keys
    "ESCAPE", "ENTER", "SPACE", "BACKSPACE", "TAB", "LEFT_CTRL", "LEFT_ALT", "DELETE",
    "KEY_A", "KEY_Q", "KEY_W", "KEY_E", "KEY_R", "KEY_T", "KEY_Y", "KEY_1",

    # Function Array
    "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10",

    # Layered Function Combos
    "FN_F9_F11_COMBINATION", "FN_F10_F12_COMBINATION", "FN_DEL_CTRL_ALT_DEL", "END_KEY"
]

def capture_indefinite_matrix_event(ser):
    """Listens forever until a clean bitframe drops or the user skips via SBC keyboard."""
    sync_marker = "1101"

    while True:
        # Check if the user hit Enter on the SBC terminal to skip this key
        # select.select monitors stdin (file descriptor 0) without blocking
        rlist, _, _ = select.select([sys.stdin], [], [], 0.001)
        if rlist:
            sys.stdin.readline() # Clear the input buffer
            return "SKIP"

        # Read an expanded window block to capture wide macro bytes
        raw_chunk = ser.read(64)
        if raw_chunk:
            bit_pool = "".join(f"{byte:08b}" for byte in raw_chunk)

            if sync_marker in bit_pool:
                segments = bit_pool.split(sync_marker)
                for seg in segments:
                    # Look for active bit segments containing coordinate transitions
                    if len(seg) >= 16 and "1" in seg and "0" in seg:
                        padded = seg[:16].ljust(16, "0")
                        byte1 = int(padded[0:8], 2)
                        byte2 = int(padded[8:16], 2)

                        # Filter system artifacts, idle recovery, and key release codes (0xF0)
                        if byte1 not in (0x00, 0x40, 0xC0, 0xF0, 0xFF):
                            return (byte1, byte2)
        else:
            time.sleep(0.002)

def main():
    if os.getuid() != 0:
        print("[!] Root privileges required to claim system serial ports.")
        sys.exit(1)

    print("=========================================================")
    print("     i8 MULTI-MODE LAYOUT WIZARD (INDEFINITE LISTEN)     ")
    print("=========================================================")

    try:
        ser = serial.Serial(SERIAL_PORT, baudrate=BAUD_RATE, timeout=0.01)
        ser.flushInput()
    except Exception as e:
        print(f"[!] Serial engine allocation failed: {e}")
        sys.exit(1)

    discovered_maps = {}

    print("\n[!] OPERATING INSTRUCTIONS:")
    print("    1. Press and hold the requested key on the i8 keyboard layout.")
    print("    2. The script will wait indefinitely until you press it.")
    print("    3. To SKIP a key, press [ENTER] on your Banana Pi terminal keyboard.\n")
    print("[-] Starting live capture loop now...")

    for target_key in I8_KEY_LIST:
        print(f"\n[>>>] TARGET: [ {target_key} ]")
        print("      (Hold key on i8 OR press Enter on SBC to skip)... ", end="", flush=True)

        # Keep flushing old line noise until the exact moment we poll
        ser.flushInput()

        result = capture_indefinite_matrix_event(ser)

        if result == "SKIP":
            print("-> SKIPPED BY USER")
        elif result:
            row_hex, col_hex = result
            discovered_maps[result] = target_key
            print(f"-> MATCH CAUGHT! (Row: 0x{row_hex:02X}, Col: 0x{col_hex:02X})")

            # Flush trailing release codes (0xF0) before prompting for the next key
            time.sleep(0.3)
            ser.flushInput()

    ser.close()

    print("\n=========================================================")
    print("             FINAL GENERATED KEYMAP DICTIONARY           ")
    print("=========================================================\n")
    print("I8_KEY_MAP = {")
    for (r, c), key_name in discovered_maps.items():
        print(f"    (0x{r:02X}, 0x{c:02X}): \"{key_name}\",")
    print("}")
    print("\n[-] Configuration array generation complete.")

if __name__ == "__main__":
    main()
