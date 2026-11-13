; Information block at $C000 and the trap for unimplemented jump table
; entries.

        .include "geos.inc"
        .include "hw.inc"

        .import ExtTable
        .export Trap, sysFlgCopy, BootGEOS, basicBuf, guMouse2, ptrColour
        .export progColours, guClockFresh

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
guVersion:      .byte VERSION_MAJOR, VERSION_MINOR
                                        ; $C0E2: major, minor (the Makefile)
guExtTable:     .word ExtTable          ; $C0E4: extension jump table (folders.s)
guMouse2:       .byte $80               ; $C0E6: the right mouse button (the 1351
                                        ; driver): bit 7 clear while held, bit 6
                                        ; set at each press (the reader clears it)
                .res $C0F1 - *, 0
trapAddress:    .word 0                 ; $C0F1: entry hit by Trap
ptrColour:      .byte 6                 ; $C0F3: the pointer's colour (blue;
                                        ; pointer.s sets it, load.s's module 0
                                        ; gives it at each program's start)
progColours:    .byte $BF               ; $C0F4: programs' colours (ink << 4 |
                                        ; paper; FirstInit gives them; the
                                        ; desktop's theme, programs=, sets it)
guBuild:        .byte VERSION_PATCH     ; $C0F5: the patch number, then the
                .byte BUILD_YEAR, BUILD_MONTH, BUILD_DAY, BUILD_HOUR, BUILD_MINUTE
                                        ; build's time stamp (the year from
                                        ; 2000; the Makefile): GeoUltra info
guClockFresh:   .byte 0                 ; $C0FB: 1 when the cold start took
                                        ; the time from the Ultimate's clock
                                        ; (hibernate.s RtcClock) and nothing
                                        ; set it since (FE_SETTIME clears it):
                                        ; the desktop then adds SETTINGS.INI's
                                        ; [time] adjust= (the user, 2026-11-13)
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
