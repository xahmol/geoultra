; Arithmetic, memory, strings and calls: DShiftLeft, DShiftRight, BBMult,
; BMult, DMult, Ddiv, DSdiv, Dabs, Dnegate, Ddec, ClearRam, FillRam,
; i_FillRam, InitRam, CopyString, CopyFString, CmpString, CmpFString,
; CallRoutine, DoInlineReturn, GetRandom, GetSerialNumber. Written from
; the HG2G2022 descriptions (registers in and out, "Destroys");
; checked with tests/conformance/misc.py.

        .include "geos.inc"

        .export DShiftLeft, DShiftRight, BBMult, BMult, DMult, Ddiv, DSdiv
        .export Dabs, Dnegate, Ddec, ClearRam, FillRam, i_FillRam, InitRam
        .export CopyString, CopyFString, CmpString, CmpFString, CallRoutine
        .export DoInlineReturn, GetRandom, GetSerialNumber, serialNumber
        .import OvlCall
.ifdef BYPASS
        .export bypassOn
        .import ExpectedSerial
.else
        .export ProtExecute, ProtStatus
.endif

returnAddress   = $3D           ; word: inline routines' return address
random          = $850A         ; word

        .segment "DATA"

mulA:   .res 1
saveX:  .res 1
saveY:  .res 1
sign:   .res 1
fixLen: .res 1

        .segment "KCODE"                ; (not under I/O: GEOS 2.0 allows it with I/O on)

; --- Arithmetic ---------------------------------------------------------

; DShiftLeft: X = zero page word, Y = count. Carry = last bit out.
; A, X unchanged; Y ends at $FF.
DShiftLeft:
        dey
        bmi @end
        asl $00,x
        rol $01,x
        jmp DShiftLeft
@end:   rts

; DShiftRight: X = zero page word, Y = count. Carry = last bit out.
DShiftRight:
        dey
        bmi @end
        lsr $01,x
        ror $00,x
        jmp DShiftRight
@end:   rts

; BBMult: X = word (low byte used) *= byte at zero page Y. Destroys A,
; r7L, r8.
BBMult:
        lda $00,y
        sta r8H                 ; multiplier
        lda $00,x
        sta r7L                 ; multiplicand
        lda #0
        sta r8L                 ; result high byte
        sty saveY
        ldy #8
@bit:   lsr r8H
        bcc @no
        clc
        adc r7L
@no:    ror
        ror r8L
        dey
        bne @bit
        sta $01,x
        lda r8L
        sta $00,x
        ldy saveY
        rts

; BMult: X = word *= low byte of the word at Y (its high byte becomes 0).
; Destroys A, r6-r8.
BMult:
        lda #0
        sta $01,y

; DMult: X = word *= word at Y (16-bit result). Destroys A, r6-r8.
DMult:  stx saveX
        sty saveY
        lda $00,x               ; r6 = multiplicand, r7 = multiplier
        sta r6L
        lda $01,x
        sta r6H
        lda $00,y
        sta r7L
        lda $01,y
        sta r7H
        lda #0
        sta r8L
        sta r8H
        ldy #16
@bit:   asl r8L                 ; result <<= 1, add when multiplier bit set
        rol r8H
        asl r7L
        rol r7H
        bcc @no
        clc
        lda r8L
        adc r6L
        sta r8L
        lda r8H
        adc r6H
        sta r8H
@no:    dey
        bne @bit
        ldx saveX
        lda r8L
        sta $00,x
        lda r8H
        sta $01,x
        ldy saveY
        rts

; Ddiv: X = word /= word at Y; r8 = remainder. Destroys A, r9.
Ddiv:   stx saveX
        sty saveY
        lda $00,y               ; r9 = divisor
        sta r9L
        lda $01,y
        sta r9H
        lda #0
        sta r8L
        sta r8H
        ldy #16
@bit:   asl $00,x               ; dividend bit into the remainder
        rol $01,x
        rol r8L
        rol r8H
        sec
        lda r8L
        sbc r9L
        pha
        lda r8H
        sbc r9H
        bcc @no
        sta r8H
        pla
        sta r8L
        inc $00,x               ; quotient bit
        bcs @next
@no:    pla
@next:  dey
        bne @bit
        ldy saveY
        rts

; DSdiv: signed X = word /= word at Y (which becomes its absolute value);
; r8 = remainder. Destroys A, r9.
DSdiv:  lda $01,x
        eor $01,y
        sta sign                ; bit 7: result negative
        jsr Dabs
        stx saveX
        tya
        tax
        jsr Dabs
        ldx saveX
        jsr Ddiv
        bit sign
        bpl @end
        jmp Dnegate
@end:   rts

; Dabs: X = word = |word|. Destroys A.
Dabs:   lda $01,x
        bpl Ddone

; Dnegate: X = word = -word. Destroys A.
Dnegate:
        lda $00,x
        eor #$FF
        clc
        adc #1
        sta $00,x
        lda $01,x
        eor #$FF
        adc #0
        sta $01,x
Ddone:  rts

; Ddec: X = word - 1; Z set when the result is $0000. Destroys A.
Ddec:   lda $00,x
        bne @low
        dec $01,x
@low:   dec $00,x
        lda $00,x
        ora $01,x
        rts

; --- Memory -------------------------------------------------------------

; ClearRam: r0 = count, r1 = address. Destroys A, Y, r0, r1, r2L.
ClearRam:
        lda #0
        sta r2L

; FillRam: r0 = count, r1 = address, r2L = value. Destroys A, Y, r0, r1.
FillRam:
        lda r2L
        ldy #0
@page:  ldx r0H                 ; whole pages first
        beq @rest
@full:  sta (r1),y
        iny
        bne @full
        inc r1H
        dec r0H                 ; (more whole pages: on; Y is 0 again)
        bne @full
@rest:  ldx r0L
        beq @end
@byte:  sta (r1),y
        iny
        dex
        bne @byte
@end:   rts

; i_FillRam: .word count, address, .byte value follow the jsr.
i_FillRam:
        pla
        sta returnAddress
        pla
        sta returnAddress+1
        ldy #5
@args:  lda (returnAddress),y
        sta r0-1,y
        dey
        bne @args
        jsr FillRam
        php
        lda #6
        jmp DoInlineReturn

; InitRam: r0 = table (.word address, .byte count (0 = 256), data ...,
; ending with .word NULL). Destroys A, X, Y, r0-r2L.
InitRam:
@block: ldy #0
        lda (r0),y
        sta r1L
        iny
        lda (r0),y
        sta r1H
        ora r1L
        beq @end
        iny
        lda (r0),y
        sta r2L                 ; count
        clc                     ; r0 = the data
        lda r0L
        adc #3
        sta r0L
        bcc @copy
        inc r0H
@copy:  ldy #0
@byte:  lda (r0),y
        sta (r1),y
        iny
        cpy r2L
        bne @byte
        tya                     ; r0 past the data (count 0: 256 bytes)
        clc
        adc r0L
        sta r0L
        bcc @hi
        inc r0H
@hi:    lda r2L
        bne @block
        inc r0H                 ; (never 0: the table would end past $FFFF)
        bne @block
@end:   rts

; --- Strings ------------------------------------------------------------

; CopyString: X = zero page pointer to the source, Y = to the destination;
; copies up to and including the NULL (at most 256 bytes). Destroys A, X, Y.
CopyString:
        lda #0

; CopyFString: as CopyString, A = length (0 = up to the NULL).
CopyFString:
        stx saveX
        sty saveY
        sta fixLen
        lda $00,x
        sta r0Copy
        lda $01,x
        sta r0Copy+1
        lda $00,y
        sta r1Copy
        lda $01,y
        sta r1Copy+1
        ldx #0
CopyByte:  lda $FFFF,x
r0Copy  = * - 2
        sta $FFFF,x
r1Copy  = * - 2
        inx
        ldy fixLen
        bne CopyFixed
        cmp #0
        beq CopyEnd
        cpx #0
        bne CopyByte
        beq CopyEnd
CopyFixed: cpx fixLen
        bne CopyByte
CopyEnd:   rts

; CmpString: X / Y = zero page pointers to the strings; flags as a
; compare of the first differing byte (Z set when equal). Destroys A, X, Y.
CmpString:
        lda #0

; CmpFString: as CmpString, A = length (0 = up to the NULL; NULLs inside
; a fixed length do not end it).
CmpFString:
        sta fixLen
        lda $00,x
        sta r0Cmp
        lda $01,x
        sta r0Cmp+1
        lda $00,y
        sta r1Cmp
        lda $01,y
        sta r1Cmp+1
        ldx #0
CmpByte:  lda $FFFF,x
r0Cmp   = * - 2
        cmp $FFFF,x
r1Cmp   = * - 2
        bne CmpEnd
        ldy fixLen
        bne CmpFixed
        cmp #0                  ; both NULL here: equal
        beq CmpEnd
        inx
        bne CmpByte
        beq CmpEnd
CmpFixed: inx
        cpx fixLen
        bne CmpByte
        lda #0                  ; equal: Z set
CmpEnd:   rts

; --- Calls ---------------------------------------------------------------

; CallRoutine: A/X = address (low/high); $0000 is ignored.
CallRoutine:
        cmp #0
        bne @call
        cpx #0
        beq @end
@call:  sta @jmp+1
        stx @jmp+2
@jmp:   jmp $FFFF
@end:   rts

; DoInlineReturn (entered with jmp): A = inline data bytes + 1, the
; status to return on the stack (php), returnAddress = the jsr's return
; address. Continues after the data with that status. X, Y unchanged.
DoInlineReturn:
        clc
        adc returnAddress
        sta returnAddress
        bcc @plp
        inc returnAddress+1
@plp:   plp
        jmp (returnAddress)

; --- Random and serial ---------------------------------------------------

        .segment "CODE"                 ; GetRandom: also from the IRQ

; GetRandom: a new 16-bit pseudo random number in random (a Galois LFSR,
; also stepped every frame by the interrupt level). Destroys A.
GetRandom:
        lsr random+1
        ror random
        bcc @end
        lda random+1
        eor #$B4
        sta random+1
@end:   lda random
        ora random+1
        bne @ok
        inc random              ; never stuck at zero
@ok:    rts

; GetSerialNumber: r0 = the serial number: the one [serials] lists for
; the running application (serials.s), else with the bypass the one the
; application stored (bypass.s), else GeoUltra's own or the one in
; SETTINGS.INI ([system] serial=, read at boot), so that applications
; installed under another GEOS serial number run. Destroys A.
GetSerialNumber:
        jsr SerialFor           ; r0: [serials]' (C clear) or the system's
.ifdef BYPASS                   ; own (serials.s module 127)
        bcc @end
        bit bypassOn            ; [system] protection=bypass: the number
        bpl @end                ; the calling application stored (bypass.s)
        stx bypassX
        tsx
        lda $0101,x
        sta r0L
        lda $0102,x
        sta r0H
        ldx bypassX
        jmp ExpectedSerial
.endif
@end:   rts

; SerialFor: module 127 (serials.s Lookup): C clear, r0 = the serial.
SerialFor:
        jsr OvlCall
        .byte 127, 0

        .segment "DATA"

serialNumber:   .word SERIAL

.ifndef BYPASS
        .segment "KCODE"        ; (runs with the C64 Kernal ROM in)

; ProtExecute / ProtStatus: an application's check for its original disk
; fails (built without src/kernal/bypass.s, see src/drivers/reudrv.s).
ProtExecute:
        rts
ProtStatus:
        ldx #DEV_NOT_FOUND
        rts

        .segment "DATA"
.endif
.ifdef BYPASS
bypassOn:       .byte 0         ; $80: answer per application (bypass.s)
bypassX:        .byte 0
.endif
