; gush: shell variables (docs/GUSH.md). A table of
; entries "NAME", 0, "value", 0, one after the other in vars (VARS_SIZE
; bytes; varsEnd: past the last). Names: letters, digits and "_", not
; starting with a digit, at most NAME_MAX characters; values up to
; VALUE_MAX. Commands: set (the variables listed), unset NAME...; an
; assignment NAME=value is done by Run (cmds.s, Assign). Own code.

        .include "geos.inc"
        .include "gush.inc"

        .import FileEngine, Say, ConPut, ConNewLine, Fail, argc
        .import argLo, argHi
        .export VarFind, VarSet, VarDel, VarsInit, varName, IsNameChar
        .export CmdSet, CmdUnset

VARS_SIZE       = 1024
NAME_MAX        = 16
VALUE_MAX       = 250
FE_HOME         = 26
FE_BAD_PATH     = $49

        .segment "ZEROPAGE"

varPtr:         .res 2          ; the entry looked at
varSrc:         .res 2          ; a copy's source (VarDel)

        .segment "CODE"

; VarsInit: the table empty, then HOME (the home folder, without its
; "/" at the end) and PATH ("/e/bin:" HOME "/bin").
VarsInit:
        lda #<vars
        sta varsEnd
        lda #>vars
        sta varsEnd+1
        lda #<homeBuf
        sta r1L
        lda #>homeBuf
        sta r1H
        lda #FE_HOME
        jsr FileEngine
        ldx #$FF                ; its end; the "/" there off
@end:   inx
        lda homeBuf,x
        bne @end
        dex
        bmi @set
        lda homeBuf,x
        cmp #'/'
        bne @set
        lda #0
        sta homeBuf,x
@set:   ldx #HomeName - Names
        jsr NameOf
        lda #<homeBuf
        sta r0L
        lda #>homeBuf
        sta r0H
        jsr VarSet
        ldx #0                  ; PATH: "/e/bin:", the home, "/bin"
@pre:   lda PathPre,x
        sta valBuf,x
        beq @home
        inx
        bne @pre
@home:  ldy #0
@hc:    lda homeBuf,y
        beq @post
        sta valBuf,x
        inx
        iny
        bne @hc
@post:  ldy #0
@pc:    lda PathPost,y
        sta valBuf,x
        beq @path
        inx
        iny
        bne @pc
@path:  ldx #PathName - Names
        jsr NameOf
        lda #<valBuf
        sta r0L
        lda #>valBuf
        sta r0H
        jmp VarSet

; NameOf: varName = the name at Names + X.
NameOf: ldy #0
@ch:    lda Names,x
        sta varName,y
        beq @end
        inx
        iny
        bne @ch
@end:   rts

; VarFind: the variable named varName. C clear: r1 = its value, varPtr
; its entry; C set: none. Destroys A, Y.
VarFind:
        lda #<vars
        sta varPtr
        lda #>vars
        sta varPtr+1
@entry: lda varPtr              ; the table's end?
        cmp varsEnd
        lda varPtr+1
        sbc varsEnd+1
        bcs @none
        ldy #$FF                ; the name the same?
@ch:    iny
        lda (varPtr),y
        cmp varName,y
        bne @skip
        cmp #0
        bne @ch
        iny                     ; yes: the value after it
        tya
        clc
        adc varPtr
        sta r1L
        lda varPtr+1
        adc #0
        sta r1H
        clc
        rts
@skip:  jsr Next
        jmp @entry
@none:  sec
        rts

; Next: varPtr past its entry (two zero-ended parts). Destroys A, Y.
Next:   ldy #0
        jsr @part
@part:  lda (varPtr),y
        inc varPtr
        bne :+
        inc varPtr+1
:       cmp #0
        bne @part
        rts

; VarSet: varName = the value at r0 (zero-ended, VALUE_MAX characters
; at most: cut there). An old value is dropped first. C set when the
; table is full (said). Destroys A, X, Y, r1.
VarSet: jsr VarDel
        lda varsEnd             ; room for the name, the value, two zeros?
        sta varPtr
        lda varsEnd+1
        sta varPtr+1
        ldy #$FF
@name:  iny
        lda varName,y
        jsr Put
        bcs @full
        lda varName,y
        bne @name
        ldy #0                  ; the value, VALUE_MAX at most, its zero
@val:   cpy #VALUE_MAX
        bcs @zero
        lda (r0),y
        beq @zero
        jsr Put
        bcs @full
        iny
        bne @val
@zero:  lda #0
        jsr Put
        bcs @full
        lda varPtr              ; the new end
        sta varsEnd
        lda varPtr+1
        sta varsEnd+1
        clc
        rts
@full:  lda #<Full
        ldy #>Full
        jsr Say
        sec
        rts

; Put: A to varPtr, varPtr on; C set when past the table. Y kept.
Put:    sty putY
        ldy #0
        sta (varPtr),y
        ldy putY
        inc varPtr
        bne :+
        inc varPtr+1
:       lda varPtr
        cmp #<(vars + VARS_SIZE)
        lda varPtr+1
        sbc #>(vars + VARS_SIZE)
        rts

; VarDel: the variable named varName removed (none: nothing). The
; entries after it move down. Destroys A, Y, r1.
VarDel: jsr VarFind
        bcs @end
        lda varPtr              ; varSrc: the entry after it
        pha
        lda varPtr+1
        pha
        jsr Next
        lda varPtr
        sta varSrc
        lda varPtr+1
        sta varSrc+1
        pla
        sta varPtr+1
        pla
        sta varPtr
        ldy #0
@move:  lda varSrc              ; up to the table's end
        cmp varsEnd
        lda varSrc+1
        sbc varsEnd+1
        bcs @done
        lda (varSrc),y
        sta (varPtr),y
        inc varSrc
        bne :+
        inc varSrc+1
:       inc varPtr
        bne @move
        inc varPtr+1
        bne @move
@done:  lda varPtr
        sta varsEnd
        lda varPtr+1
        sta varsEnd+1
@end:   rts

; IsNameChar: C set when A may be in a name (letters, digits, "_"; the
; caller keeps digits from the first place). A kept.
IsNameChar:
        cmp #'_'
        beq @yes
        cmp #'0'
        bcc @no
        cmp #'9' + 1
        bcc @yes
        cmp #'A'
        bcc @no
        cmp #'Z' + 1
        bcc @yes
        cmp #'a'
        bcc @no
        cmp #'z' + 1
        bcc @yes
@no:    clc
        rts
@yes:   sec
        rts

; set: every variable, "NAME=value".
CmdSet: lda #<vars
        sta varPtr
        lda #>vars
        sta varPtr+1
@entry: lda varPtr
        cmp varsEnd
        lda varPtr+1
        sbc varsEnd+1
        bcs @end
        jsr Show                ; the name
        lda #'='
        jsr ConPut
        jsr Show                ; the value
        jsr ConNewLine
        jmp @entry
@end:   rts

; Show: the zero-ended text at varPtr printed, varPtr past it.
Show:   ldy #0
        lda (varPtr),y
        inc varPtr
        bne :+
        inc varPtr+1
:       cmp #0
        beq @end
        jsr ConPut
        jmp Show
@end:   rts

; unset NAME...: those variables removed.
CmdUnset:
        ldx #1
@word:  cpx argc
        bcs @end
        stx word
        lda argLo,x
        sta r0L
        lda argHi,x
        sta r0H
        ldy #$FF
@ch:    iny
        lda (r0),y
        sta varName,y
        beq @del
        cpy #NAME_MAX
        bcc @ch
        ldx #FE_BAD_PATH        ; (too long for a name)
        ldy word
        jsr Fail
        jmp @next
@del:   jsr VarDel
@next:  ldx word
        inx
        bne @word
@end:   rts

Names:
HomeName:       .byte "HOME", 0
PathName:       .byte "PATH", 0
PathPre:        .byte "/e/bin:", 0
PathPost:       .byte "/bin", 0
Full:           .byte "gush: no room for more variables", 0

        .segment "DATA"

varsEnd:        .word vars
putY:           .byte 0
word:           .byte 0

        .segment "BSS"

varName:        .res NAME_MAX + 1
valBuf:         .res VALUE_MAX + 1
homeBuf:        .res 33
vars:           .res VARS_SIZE
