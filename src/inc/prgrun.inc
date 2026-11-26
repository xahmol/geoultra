; prgrun.inc: running a PRG file of a GeoUltra drive in BASIC, shared by
; the desktop (desktop.s, Ov_RunPrg) and gush (prog.s, RunPrg); the
; user's decision of 2026-11-26. The kernal's ToBASIC loads the file from
; the drive itself when its command is LOAD "name",dev[,1] (tobasic.s,
; modules 128-130), puts it in place after GEOS is gone and types RUN for
; a program at $0801; boot files of other GEOS systems it refuses.
; The includer reserves prgCmd (32 bytes) and has geos.inc's names.

; PrgCommand: the command LOAD "name",dev,1 into prgCmd from the short
; name at r6 (0-ended, 16 characters at most) and curDrive (8-11, the
; file's drive made current by the caller, FE_SELECT); ToBASIC's
; registers set: r0 = prgCmd, r5 = 0 (no entry: the command loads it),
; r7 = $0803 (no BASIC program in memory). Then jmp ToBasic.
; Destroys A, X, Y.
PrgCommand:
        ldx #0
@pre:   lda PrgLoad,x           ; LOAD "
        sta prgCmd,x
        inx
        cpx #6
        bne @pre
        ldy #0
@name:  lda (r6),y
        beq @named
        sta prgCmd,x
        inx
        iny
        cpy #16
        bne @name
@named: lda #'"'
        sta prgCmd,x
        inx
        lda #','
        sta prgCmd,x
        inx
        lda curDrive            ; 8, 9 or 10, 11
        cmp #10
        bcc @digit
        lda #'1'
        sta prgCmd,x
        inx
        lda curDrive
        sbc #10                 ; (C set from the cmp)
@digit: ora #'0'
        sta prgCmd,x
        inx
        ldy #0
@post:  lda PrgAbs,y            ; ,1 and the end
        sta prgCmd,x
        inx
        iny
        cpy #3
        bne @post
        lda #<prgCmd
        sta r0L
        lda #>prgCmd
        sta r0H
        lda #0
        sta r5L
        sta r5H
        lda #<$0803
        sta r7L
        lda #>$0803
        sta r7H
        rts

PrgLoad:        .byte "LOAD ", '"'
PrgAbs:         .byte ",1", 0
