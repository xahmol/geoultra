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
; UCdX: into fePath's first X characters (module 36, in pieces when
; they do not fit one command).
UCdX:   jsr OvlCall
        .byte 36, 3
