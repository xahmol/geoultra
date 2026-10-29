; GeoUltra -- serial number per application (optional module).
;
; NOTICE: this module is meant for running GEOS applications of which you
; own a licensed copy, installed under another GEOS boot disk than the one
; GeoUltra uses (for example after the original disks wore out). GEOS and
; its applications are still under copyright; using this module is your
; own responsibility. It contains no code or data from any application.
; It is off unless SETTINGS.INI says [system] protection=bypass, and
; `make BYPASS=0` builds GeoUltra without it (docs/DESIGN.md, "Serial
; number").
;
; How: an application that checks the serial number compares the result
; of GetSerialNumber (r0) with the number it stored when it was installed,
; right after the call. This module reads the instructions after the
; caller's return address, finds an absolute address whose content is
; compared with r0L or r0H, and answers with the number stored there. When
; nothing is found, or the stored number is 0 (not installed yet), the
; answer is the system's own serial number.
; The idea of reading the expected value from the application is described
; in "Copy Protection Traps in GEOS for C64" (Michael Steil, pagetable.com,
; https://www.pagetable.com/?p=149); the recognition here is GeoUltra's own.

        .include "geos.inc"

        .export ExpectedSerial, ProtExecute, ProtStatus
        .import OvlCall, serialNumber, bypassOn

SCAN_LENGTH     = 32            ; bytes after the call that are examined

        .segment "CODE"

; ExpectedSerial (from GetSerialNumber, entered with jmp): r0 = the
; caller's return address as pushed by its jsr. Returns r0 = the serial
; number. A destroyed; X, Y unchanged.
ExpectedSerial:
        jsr OvlCall
        .byte 4, 0

; ProtExecute / ProtStatus: what an application's check for its original
; disk calls instead of executing drive code (found behind NewDisk, see
; src/drivers/reudrv.s). With the module on, the check passes (X = 0) and
; the application installs itself under the system's serial number, as it
; would on a 1541; else X = DEV_NOT_FOUND. In KCODE: they run between
; InitForIO and DoneWithIO, with the C64 Kernal ROM over $E000-$FFFF.
        .segment "KCODE"

ProtExecute:
        rts
ProtStatus:
        ldx #0
        bit bypassOn
        bmi @end
        ldx #DEV_NOT_FOUND
@end:   rts

        .segment "OVL4"

        jmp Expected            ; entry 0

; Module variables (the module is fetched again for every call).
saveX:  .byte 0
saveY:  .byte 0
hiAddr: .word 0                 ; where the stored high byte is, 0: none
loAddr: .word 0                 ; where the stored low byte is, 0: none
which:  .byte 0                 ; r0L or r0H

Expected:
        stx saveX
        sty saveY
        lda #0
        sta hiAddr+1
        sta loAddr+1
        inc r0L                 ; the first byte after the jsr
        bne @scan
        inc r0H
@scan:  ldy #0
@next:  lda (r0),y
        jsr IsLoad              ; ld? zp / ld? abs: C clear, X = compare
        bcs @step               ; opcode for the other operand form
        cmp #ABS_FORM
        beq @absFirst
        iny                     ; ld? r0L/r0H, then cp? abs
        lda (r0),y
        jsr IsR0
        bcs @back1
        sta which
        iny
        txa
        cmp (r0),y              ; the matching compare with abs?
        bne @back2
        iny
        lda which
        jsr Found               ; abs at (r0),y
        iny
        jmp @step
@absFirst:                      ; ld? abs, then cp? r0L/r0H
        iny
        iny
        iny
        txa
        cmp (r0),y
        bne @back3
        iny
        lda (r0),y
        jsr IsR0
        bcs @back4
        pha
        dey                     ; abs is at (r0),y-3 .. y-2
        dey
        dey
        pla
        jsr Found
        iny
        iny
        jmp @step
@back4: dey
@back3: dey
        dey
        dey
        jmp @step
@back2: dey
@back1: dey
@step:  iny
        cpy #SCAN_LENGTH
        bne @next

        lda serialNumber        ; the system's own number by default
        sta r0L
        lda serialNumber+1
        sta r0H
        jsr Fetch
        ldx saveX
        ldy saveY
        rts

; Fetch: the stored bytes into r0 when they are not both 0.
Fetch:  lda hiAddr+1
        ora loAddr+1
        beq @end
        lda r1L                 ; r1 is free here: use it as pointer
        pha
        lda r1H
        pha
        lda #0
        sta tmpHi
        sta tmpLo
        lda hiAddr+1
        beq @noHi
        sta r1H
        lda hiAddr
        sta r1L
        ldy #0
        lda (r1),y
        sta tmpHi
@noHi:  lda loAddr+1
        beq @noLo
        sta r1H
        lda loAddr
        sta r1L
        ldy #0
        lda (r1),y
        sta tmpLo
@noLo:  pla
        sta r1H
        pla
        sta r1L
        lda tmpHi
        ora tmpLo
        beq @end                ; not installed: keep the own number
        lda hiAddr+1
        beq @keepHi
        lda tmpHi
        sta r0H
@keepHi:lda loAddr+1
        beq @end
        lda tmpLo
        sta r0L
@end:   rts

tmpHi:  .byte 0
tmpLo:  .byte 0

ABS_FORM        = $FF           ; IsLoad's A for ld? abs

; IsLoad: A = opcode. LDA/LDX/LDY zp: C clear, X = the matching compare
; with an absolute operand. LDA/LDX/LDY abs: C clear, A =
; ABS_FORM, X = the matching compare with a zero-page operand. Else C set.
IsLoad: ldx #5
@find:  cmp loadOps,x
        beq @hit
        dex
        bpl @find
        sec
        rts
@hit:   cpx #3
        bcs @abs
        lda cmpAbs,x
        tax
        clc
        rts
@abs:   lda cmpZp-3,x
        tax
        lda #ABS_FORM
        clc
        rts

loadOps:.byte $A5, $A6, $A4     ; LDA zp, LDX zp, LDY zp
        .byte $AD, $AE, $AC     ; LDA abs, LDX abs, LDY abs
cmpAbs: .byte $CD, $EC, $CC     ; CMP abs, CPX abs, CPY abs
cmpZp:  .byte $C5, $E4, $C4     ; CMP zp, CPX zp, CPY zp

; IsR0: A = a zero-page operand. r0L or r0H: C clear, A unchanged.
IsR0:   cmp #r0L
        beq @yes
        cmp #r0H
        beq @yes
        sec
        rts
@yes:   clc
        rts

; Found: (r0),y and the next byte = an absolute address holding the byte
; compared with A (r0L: low byte, r0H: high byte). Y unchanged.
Found:  pha
        lda (r0),y
        sta @lo+1
        iny
        lda (r0),y
        dey
        tax
        pla
        cmp #r0H
        beq @hi
@lo:    lda #0
        sta loAddr
        stx loAddr+1
        rts
@hi:    lda @lo+1
        sta hiAddr
        stx hiAddr+1
        rts
