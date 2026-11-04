; File engine: the Ultimate's folders, for the modules that start there
; (feult.inc first). Assembled into each module that needs it.

; UCd: into the folder holding the path's last part (fePath up to
; fePos); the top itself (feName 0): into it. UCdAll: into the whole
; path. X = 0 or the error (UExec).
UCd:    ldx fePos
        lda feName
        bne UCdX
UCdAll: ldx #$FF
@end:   inx
        lda fePath,x
        bne @end
; UCdX: into fePath's first X characters.
UCdX:   stx uLen                ; (the count, then the command's length)
        lda #U_TARGET
        sta uCmd
        lda #U_CD
        sta uCmd+1
        ldy #0
@copy:  cpy uLen
        beq @sent
        lda fePath,y
        sta uCmd+2,y
        iny
        bne @copy
@sent:  iny
        iny
        sty uLen
        jsr UNoData
        jmp UExec
