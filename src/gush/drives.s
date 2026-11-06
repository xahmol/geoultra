; gush: switching drives as on DOS (user, 2026-11-06): a line of just
; "b:" (a-e, usb0, usb1, sd; either case) goes back to the folder gush
; was last in on that drive, its root the first time or when that folder
; is gone. Every successful cd keeps the folder for its drive (Remember);
; the folders live in the application's REU bank 1 after the history
; (DRV_PAGE, a page each). Own code.

        .include "geos.inc"
        .include "gush.inc"

        .import FileEngine, Status, pwdBuf, argc, argLo, argHi, Fail
        .export DriveSwitch, Remember, DrivesInit

StashRAM        = $C2C8         ; GEOS jump table
FetchRAM        = $C2CB
DRV_BANK        = 1             ; (edit.s: the history at $0000-$7FFF)
DRV_PAGE        = $80           ; slot n at page DRV_PAGE + n
SLOTS           = 8

        .segment "ZEROPAGE"

dp:             .res 2          ; the word, a path

        .segment "CODE"

; DrivesInit (gush's start): no folder kept for any drive yet.
DrivesInit:
        lda #0
        sta zero
        ldx #SLOTS - 1
@slot:  stx slot
        lda #<zero
        sta r0L
        lda #>zero
        sta r0H
        lda #1
        jsr Ram
        jsr StashRAM
        ldx slot
        dex
        bpl @slot
        rts

; DriveSwitch: word 0 (the line's only word) a drive's name and ":"? C
; set: no (the line goes on as usual). Else the switch (said when it
; fails), C clear.
DriveSwitch:
        lda argc
        cmp #1
        bne @no
        lda argLo
        sta dp
        lda argHi
        sta dp+1
        jsr Find                ; the name, then ":" and the end
        bcs @no
        lda (dp),y
        cmp #':'
        bne @no
        iny
        lda (dp),y
        bne @no
        stx slot
        lda #<buf               ; the folder kept for it
        sta r0L
        lda #>buf
        sta r0H
        lda #0                  ; (a page)
        jsr Ram
        jsr FetchRAM
        lda buf
        beq @root
        jsr Cd                  ; there, if it is still there
        bcc @done
@root:  ldx slot                ; else its root
        jsr Root
        jsr Cd
        bcc @done
        ldy #0
        jsr Fail                ; (X: the engine's error, about the word)
@done:  clc
        rts
@no:    sec
        rts

; Cd: FE_CD to buf; then Remember. C set when it failed (X the error).
Cd:     lda #<buf
        sta r0L
        lda #>buf
        sta r0H
        lda #FE_CD
        jsr FileEngine
        txa
        beq :+
        sec
        rts
:       jsr Remember
        clc
        rts

; Root: buf = "/" and slot X's name.
Root:   lda #'/'
        sta buf
        ldy NameAt,x
        ldx #1
@ch:    lda Names,y
        sta buf,x
        beq @end
        iny
        inx
        bne @ch
@end:   rts

; Remember (after a successful cd): the current folder (Status brings
; pwdBuf up to date) kept for its drive.
Remember:
        jsr Status
        lda #<(pwdBuf + 1)      ; the top name after its "/"
        sta dp
        lda #>(pwdBuf + 1)
        sta dp+1
        jsr Find
        bcs @end
        lda (dp),y              ; (the name ends there: "/" or the end)
        beq :+
        cmp #'/'
        bne @end
:       stx slot
        lda #<pwdBuf
        sta r0L
        lda #>pwdBuf
        sta r0H
        lda #0
        jsr Ram
        jmp StashRAM
@end:   rts

; Find: the drive name at (dp) (either case): X = its slot, Y = the
; offset past it; C set when it is none.
Find:   ldx #0
@name:  ldy #0
        stx try
        lda NameAt,x
        sta at
@ch:    ldx at
        lda Names,x
        beq @found
        sta want
        lda (dp),y
        ora #$20                ; (either case; digits keep their value)
        cmp want
        bne @next
        inc at
        iny
        bne @ch
@found: ldx try
        clc
        rts
@next:  ldx try
        inx
        cpx #SLOTS
        bcc @name
        rts                     ; (C set: cpx found X >= SLOTS)

; Ram: r1-r3 for slot `slot` in the REU; r2 = A bytes (0: a page).
Ram:    sta r2L
        lda #0
        sta r1L
        sta r2H
        lda r2L
        bne :+
        inc r2H                 ; (0: 256)
:       lda slot
        clc
        adc #DRV_PAGE
        sta r1H
        lda #DRV_BANK
        sta r3L
        rts

Names:  .byte "a", 0, "b", 0, "c", 0, "d", 0, "e", 0
        .byte "usb0", 0, "usb1", 0, "sd", 0
NameAt: .byte 0, 2, 4, 6, 8, 10, 15, 20

        .segment "DATA"

slot:           .byte 0
try:            .byte 0
at:             .byte 0
want:           .byte 0
zero:           .byte 0

        .segment "HIGHBSS"

buf:            .res 256
