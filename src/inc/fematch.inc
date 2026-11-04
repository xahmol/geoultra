; File engine: a name against a listing's pattern, for FE_READDIR on
; GEOS drives (module 28, names in feTmp) and on the Ultimate (module 39).
; The includer defines MATCH_NAME (the name, zero-ended, below 128
; characters) before the include, and for letters in either case
; (the Ultimate: FAT is case-insensitive) MATCH_FOLD, a free byte.

; Match: C clear when the name at MATCH_NAME fits the pattern at H_PAT ("*":
; any run of characters, "?": one). One way back: to the last "*", one
; character further in the name each time.
Match:  ldx #0                  ; X: in the pattern, Y: in the name
        ldy #0
        lda #$FF
        sta feM
@loop:  lda MATCH_NAME,y
        beq @tail
        lda feH + H_PAT,x
        cmp #'*'
        beq @star
        cmp #'?'
        beq @one
        .ifdef MATCH_FOLD
        jsr Fold
        sta MATCH_FOLD
        lda MATCH_NAME,y
        jsr Fold
        cmp MATCH_FOLD
        .else
        cmp MATCH_NAME,y
        .endif
        beq @one
        lda feM                 ; no fit: back to the last "*"
        bmi @no
        tax
        inx
        inc feMN
        ldy feMN                ; (below 128: always)
        bpl @loop
@one:   inx
        iny
        bne @loop
@star:  stx feM
        sty feMN
        inx
        bne @loop
@tail:  lda feH + H_PAT,x       ; the name used up: only "*"s may follow
        cmp #'*'
        bne @fin
        inx
        bne @tail
@fin:   cmp #1                  ; (C clear only for the pattern's end)
        rts
@no:    sec
        rts

        .ifdef MATCH_FOLD
; Fold: A in lower case (A-Z to a-z). Other characters kept.
Fold:   cmp #'A'
        bcc @end
        cmp #'Z' + 1
        bcs @end
        ora #$20
@end:   rts
        .endif
