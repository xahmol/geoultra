; File engine: the Ultimate's file system, for the modules that use it
; (engineult.s, enginexfer.s; the exchange itself is module 36): building
; a command. Assembled into each module that needs it; fecd.inc adds the
; folder changes.

UExec:  jsr OvlCall             ; uCmd sent, the reply's data to (r0) up
        .byte 36, 0             ; to uEnd; X = 0 or the error

; UBegin: uCmd = target, DOS command A. Destroys A.
UBegin: sta uCmd+1
        lda #U_TARGET
        sta uCmd
        lda #2
        sta uLen
        rts

; UPut: one byte more to uCmd. Destroys Y.
UPut:   ldy uLen
        sta uCmd,y
        inc uLen
        rts

; UPutName: the path's last part (after fePos) to uCmd. Destroys A, X, Y.
UPutName:
        ldx fePos
@ch:    inx
        lda fePath,x
        beq @end
        jsr UPut
        jmp @ch
@end:   rts

; UNoData: no reply data wanted (uEnd 0). Destroys A.
UNoData:
        lda #0
        sta uEnd
        sta uEnd+1
        rts
