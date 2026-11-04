; File engine: is a name long (more than FE_NAME_MAX characters, so it
; needs a short name and a GU.LONGNAMES record)? By its length: the bytes
; after a name's zero are left from earlier names. Assembled into each
; module that needs it.

; IsLongT, IsLongN: Z clear when feTmp, feName is long. Destroys A, X.
IsLongT:
        ldx #$FF
@len:   inx
        lda feTmp,x
        bne @len
        beq Long
IsLongN:
        ldx #$FF
@len:   inx
        lda feName,x
        bne @len
Long:   cpx #FE_NAME_MAX + 1    ; (C set: long)
        lda #0
        rol a
        rts
