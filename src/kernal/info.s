; Information block at $C000 and the trap for unimplemented jump table
; entries.

        .include "geos.inc"
        .include "hw.inc"

        .import ColdStart
        .export Trap

        .segment "INFO"
        .org $C000                      ; fixed addresses in this block

BootGEOS:       jmp ColdStart           ; $C000
ResetHandle:    jmp ColdStart           ; $C003
bootName:       .byte "GEOS BOOT"       ; $C006, what applications test
version:        .byte $20               ; $C00F: GEOS 2.0 interface
nationality:    .byte 0                 ; $C010: English
sysVersion:     .byte 0                 ; $C011
sysFlgCopy:     .byte 0                 ; $C012
c128Flag:       .byte 0                 ; $C013: C64
                .res $C0E0 - *, 0
guSignature:    .byte "GU"              ; $C0E0: GeoUltra present
guVersion:      .byte 0, 1              ; $C0E2: major, minor
guExtTable:     .word 0                 ; $C0E4: extension jump table (later)
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
