; Information block at $C000 and the trap for unimplemented jump table
; entries.

        .include "geos.inc"
        .include "hw.inc"

        .import ExtTable
        .export Trap, sysFlgCopy, BootGEOS, basicBuf, guMouse2

        .segment "INFO"
        .org $C000                      ; fixed addresses in this block

BootGEOS:       jmp Reboot              ; $C000: back from BASIC (RESTORE too)
ResetHandle:    jmp Reboot              ; $C003: the cold start is not resident
bootName:       .byte "GEOS BOOT"       ; $C006, what applications test
version:        .byte $20               ; $C00F: GEOS 2.0 interface
nationality:    .byte 0                 ; $C010: English
sysVersion:     .byte 0                 ; $C011
sysFlgCopy:     .byte 0                 ; $C012
c128Flag:       .byte 0                 ; $C013: C64
                .res 4, 0
dateCopy:       .res 3                  ; $C018: year, month, day

; Reboot: GeoUltra again from the cartridge (its boot ROM copies the
; system from ROM to the REU and starts it; mounted REU drives stay).
Reboot: sei
        lda #ROM_ALL
        sta CPU_PORT
        lda #MB_ON8K
        sta mbCtrl
        jmp ($8000)                     ; the cartridge's cold start

basicBuf:       .res 46                 ; ToBASIC: command, saved bytes
                .res $C0E0 - *, 0
guSignature:    .byte "GU"              ; $C0E0: GeoUltra present
guVersion:      .byte 0, 1              ; $C0E2: major, minor
guExtTable:     .word ExtTable          ; $C0E4: extension jump table (folders.s)
guMouse2:       .byte $80               ; $C0E6: the right mouse button (the 1351
                                        ; driver): bit 7 clear while held, bit 6
                                        ; set at each press (the reader clears it)
                .res $C0F1 - *, 0
trapAddress:    .word 0                 ; $C0F1: entry hit by Trap
        .reloc

        .segment "CODE"

; Unimplemented jump table entry: each one is `jsr Trap`. Stores the
; entry's address at trapAddress and cycles the border colour forever.
Trap:   sei
        pla
        sec
        sbc #2
        sta trapAddress
        pla
        sbc #0
        sta trapAddress+1
        lda #RAM_IO
        sta CPU_PORT
@loop:  inc vicBorder
        jmp @loop
