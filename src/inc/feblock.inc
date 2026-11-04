; File engine: blocks of a copy onto a GEOS drive, for modules 31 and 44:
; the next free block. Assembled into each module that needs it. Uses
; cLast, cDstDrv.

; Alloc: a free target block after cLast (the first one: BlkAlloc's
; start for the drive type, its table in fileTrScTab) to cLast. Z set
; when it worked, else X = the error. Destroys r2-r8.
Alloc:  jsr Dest
        lda cLastT
        beq @first
        sta r3L
        lda cLastS
        sta r3H
        jsr SetNextFree
        jmp @got
@first: lda #1                  ; one byte: one block
        sta r2L
        lda #0
        sta r2H
        lda #<fileTrScTab
        sta r6L
        lda #>fileTrScTab
        sta r6H
        jsr BlkAlloc
@got:   txa
        bne @end
        lda r3L
        sta cLastT
        lda r3H
        sta cLastS
        txa
@end:   rts

; Dest: the target's drive selected.
Dest:   lda cDstDrv
        jmp SetDevice
