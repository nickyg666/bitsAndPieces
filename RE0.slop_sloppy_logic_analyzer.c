#define _POSIX_C_SOURCE 199309L  // Unlocks modern POSIX system clocks
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <time.h>                // Standard POSIX clock mapping
#include <unistd.h>

#define GPIO_PAGE_BASE   0x01C20000
#define MAP_SIZE         4096
#define PIO_OFFSET       0x800
#define PIO_A_DATA       0x10    // Port A status mapping data register

uint64_t get_time_ns() {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ((uint64_t)ts.tv_sec * 1000000000ULL) + ts.tv_nsec;
}

int main() {
    int mem_fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (mem_fd < 0) {
        perror("[!] Root privileges required to probe memory map");
        return 1;
    }

    void *page_map = mmap(NULL, MAP_SIZE, PROT_READ, MAP_SHARED, mem_fd, GPIO_PAGE_BASE);
    close(mem_fd);
    if (page_map == MAP_FAILED) {
        perror("[!] Hardware memory mapping failed");
        return 1;
    }

    // Direct pointer to Port A data register structure
    volatile uint32_t *data_reg = (volatile uint32_t *)((char *)page_map + PIO_OFFSET + PIO_A_DATA);

    printf("[-] Microsecond Waveform Analyzer Running...\n");
    printf("[-] Listening continuously on UART0-RX (PA5)...\n\n");

    // PA5 is Bit 5 of the register snapshot
    uint32_t last_bit = (*data_reg >> 5) & 1;
    uint64_t last_transition_time = get_time_ns();

    while (1) {
        uint32_t current_bit = (*data_reg >> 5) & 1;

        // Capture whenever the physical voltage line flips state
        if (current_bit != last_bit) {
            uint64_t current_time = get_time_ns();
            uint64_t pulse_duration_ns = current_time - last_transition_time;
            double pulse_us = (double)pulse_duration_ns / 1000.0;

            // Log transitions that fall inside active communication ranges (2us to 100ms)
            if (pulse_us > 2.0 && pulse_us < 100000.0) {
                printf("Line flipped -> %s | Held for: %.2f us\n",
                       current_bit ? "HIGH" : "LOW ", pulse_us);
                fflush(stdout);
            }

            last_bit = current_bit;
            last_transition_time = current_time;
        }
    }

    munmap(page_map, MAP_SIZE);
    return 0;
}
