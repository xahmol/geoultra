; The scrap store's routines (scrap.s); each module assembles the parts
; it uses (an overlay module cannot call another's code). Shared state in
; the overlay scratch at $9F70 (scrap.s).

; IsScrap: A/X = a name -> r6; C clear when it is a scrap's: 11
; characters, the last six " Scrap".
IsScrap:
        sta r6L
        stx r6H
        ldy #11
        lda (r6),y
        bne @no
        dey
@c:     lda (r6),y
        cmp ScrapWord - 5,y
        bne @no
        dey
        cpy #5
        bcs @c
@n:     lda (r6),y              ; the type: five characters, none 0
        beq @no
        dey
        bpl @n
        clc
        rts
@no:    sec
        rts
ScrapWord:      .byte " Scrap"

