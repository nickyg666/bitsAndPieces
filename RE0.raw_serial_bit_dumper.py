#!/usr/bin/env python3
import sys
import os
import time

try:
    import serial
except ImportError:
    print("[!] Error: missing serial library. Run: apt install python3-serial")
    sys.exit(1)

SERIAL_PORT = "/dev/ttyS0"
BAUD_RATE = 115200

def parse_raw_bitstream(bit_string):
    """Processes the raw bit alignments to pinpoint the keyboard scancode maps."""
    # The matrix chip indicates a valid keypress burst by pulling the line down.
    # We hunt for the exact bit boundary sequence that marks the packet start.
    sync_marker = "1101"

    if sync_marker in bit_string:
        # Split the stream at the synchronization marker point
        payload_segments = bit_string.split(sync_marker)

        for segment in payload_segments:
            # We look for active data blocks (discarding long idle 0/1 trails)
            if len(segment) >= 8 and "1" in segment and "0" in segment:
                # Pad out the segment to clean 8-bit byte bounds
                padded_segment = segment[:16].ljust(16, "0")

                # Convert the raw bit fragments into readable Hex values
                byte1 = int(padded_segment[0:8], 2)
                byte2 = int(padded_segment[8:16], 2)

                if byte1 != 0x00 and byte1 != 0xFF:
                    print(f"[MATCH FOUND] -> Sync: {sync_marker} | Frame Hex: 0x{byte1:02X} 0x{byte2:02X} | Bits: {padded_segment}")

def main():
    print(f"[-] Binding raw stream listener to {SERIAL_PORT}...")

    try:
        # Open the terminal node with a strict timeout to clear character windows
        ser = serial.Serial(SERIAL_PORT, baudrate=BAUD_RATE, timeout=0.02)
        ser.flushInput()
    except Exception as e:
        print(f"[!] Target serial port configuration failed: {e}")
        sys.exit(1)

    print("[+] Core bitstream assembler active. Press keys to read scancodes...\n")

    try:
        while True:
            raw_chunk = ser.read(64)

            if raw_chunk:
                # Convert every incoming character byte directly into an unbroken binary string
                bit_pool = "".join(f"{byte:08b}" for byte in raw_chunk)

                # Parse the raw stream block to extract the real hidden values
                parse_raw_bitstream(bit_pool)
            else:
                time.sleep(0.002)

    except KeyboardInterrupt:
        print("\n[-] Sniffing session ended cleanly.")
    finally:
        ser.close()

if __name__ == "__main__":
    if os.getuid() != 0:
        print("[!] Root access required to execute raw serial hooks.")
        sys.exit(1)
    main()
