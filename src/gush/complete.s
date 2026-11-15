; gush: completion with the <- key (docs/GUSH.md; overlay 3, ovl.s). The
; word before the cursor (back to a space, ";" or
; "|", taken as typed: no quotes) is the start of a name: in the folder
; its path gives (or the current one), and for a statement's first word
; without "/" also of gush's commands. The first <- adds what all the
; names that fit agree on (one name: all of it, then "/" for a folder or
; drive, else a space; spaces in a name with a "\" before them); a <-
; that adds nothing, right after another <-, lists the names that fit
; and shows the line again. Own code.

        .include "geos.inc"
        .include "gush.inc"

        .import FileEngine, ConPut, ConNewLine, conCol, Commands
        .import lineBuf, linePos, prevKey, Show, InsCh
        .export Ov_Complete := Complete

NAME_MAX        = 61            ; FE_READDIR's name buffer
PAT_MAX         = 128

        .segment "ZEROPAGE"

cp:             .res 2          ; the command table

        .segment "OV3"                 ; (overlay 3, ovl.s)

; Complete (KEY_LARROW, from EdKey with the cursor off): see above. Ends
; through Show.
Complete:
        lda #0
        sta found
        sta listing
        lda prevKey             ; a <- right after a <-: list when
        cmp #KEY_LARROW         ; nothing is added
        bne :+
        inc again
        bne @word
:       lda #0
        sta again
@word:  jsr Word
        bcs @end
        jsr Scan
        lda found
        beq @end
        jsr Add                 ; C clear: something added
        bcc @end
        lda again
        beq @end
        inc listing             ; the names listed, the line again
        jsr NewLine
        jsr Scan
        jsr NewLine
        lda #'$'
        jsr ConPut
        lda #' '
        jsr ConPut
@end:   jmp Show

; NewLine: a line ended if anything is on it.
NewLine:
        lda conCol
        beq :+
        jsr ConNewLine
:       rts

; Word: wordAt = the word's start, nameAt = its name part's start (after
; its last "/"); pattern = the word's folder part, the name part and "*".
; first set when the word is a statement's first without "/". C set when
; the word is too long.
Word:   ldx linePos
@back:  txa
        beq @start
        lda lineBuf-1,x
        cmp #' '
        beq @start
        cmp #';'
        beq @start
        cmp #'|'
        beq @start
        dex
        bne @back
@start: stx wordAt
        stx nameAt
        lda #1                  ; first: only spaces, ";" or "|" before
        sta first
@before:
        txa
        beq @slash
        dex
        lda lineBuf,x
        cmp #' '
        beq @before
        cmp #';'
        beq @slash
        cmp #'|'
        beq @slash
        lda #0
        sta first
@slash: ldx wordAt              ; the name part: after the last "/"
@s:     cpx linePos
        beq @pat
        lda lineBuf,x
        inx
        cmp #'/'
        bne @s
        stx nameAt
        lda #0
        sta first
        beq @s
@pat:   lda linePos             ; the pattern: the word and "*"
        sec
        sbc wordAt
        cmp #PAT_MAX - 2
        bcs @long
        ldx wordAt
        ldy #0
@p:     cpx linePos
        beq @star
        lda lineBuf,x
        sta pattern,y
        inx
        iny
        bne @p
@star:  lda #'*'
        sta pattern,y
        lda #0
        sta pattern + 1,y
        clc
        rts
@long:  sec
        rts

; Scan: the commands (for a first word) and the folder's names that fit:
; each through Match.
Scan:   lda first
        beq @dir
        lda #<Commands
        sta cp
        lda #>Commands
        sta cp+1
@cmd:   ldy #0
        lda (cp),y
        beq @dir
@c:     lda (cp),y              ; its name to nameBuf
        sta nameBuf,y
        beq :+
        iny
        bne @c
:       lda #0                  ; (a command: no "/")
        sta kind
        jsr Match
        ldy #$FF                ; past the name and its address
@skip:  iny
        lda (cp),y
        bne @skip
        tya
        sec                     ; (+1 the zero, +2 the address)
        adc #2
        clc
        adc cp
        sta cp
        bcc @cmd
        inc cp+1
        bne @cmd
@dir:   lda #<pattern
        sta r0L
        lda #>pattern
        sta r0H
        lda #FE_OPENDIR
        jsr FileEngine
        sta handle
        txa
        bne @end
@entry: lda #<info
        sta r1L
        lda #>info
        sta r1H
        lda #<nameBuf
        sta r2L
        lda #>nameBuf
        sta r2H
        lda #0
        sta r3L
        sta r3H
        ldy handle
        lda #FE_READDIR
        jsr FileEngine
        txa
        bne @close
        lda info + FI_KIND
        sta kind
        jsr Match
        jmp @entry
@close: ldy handle
        lda #FE_CLOSE
        jsr FileEngine
@end:   rts

; Match: nameBuf when it starts with the typed name part: listed (when
; listing), else the common part (common, commonLen) narrowed to it.
Match:  lda nameAt              ; the typed part fits?
        sta at
        ldy #0
@fit:   ldx at
        cpx linePos
        beq @fits
        lda lineBuf,x
        cmp nameBuf,y
        bne @end
        inc at
        iny
        bne @fit
@fits:  lda listing
        bne List
        lda found
        bne @narrow
        inc found               ; the first: all of it
        ldy #$FF
@cp:    iny
        lda nameBuf,y
        sta common,y
        bne @cp
        sty commonLen
        lda kind
        sta commonKind
        rts
@narrow:
        lda #2                  ; (more than one)
        sta found
        ldy #0
@n:     cpy commonLen
        beq @end
        lda nameBuf,y
        cmp common,y
        bne @cut
        iny
        bne @n
@cut:   sty commonLen
@end:   rts

; List: nameBuf on the screen, two spaces after it; a new line first
; when it does not fit.
List:   ldy #$FF
@len:   iny
        lda nameBuf,y
        bne @len
        tya
        clc
        adc conCol
        cmp #COLS - 1
        bcc :+
        jsr NewLine
:       ldy #0
@put:   lda nameBuf,y
        beq @gap
        sty at
        jsr ConPut
        ldy at
        iny
        bne @put
@gap:   lda conCol
        beq @end
        lda #' '
        jsr ConPut
        lda conCol
        beq @end
        lda #' '
        jsr ConPut
@end:   rts

; Add: the common part's characters past the typed ones into the line
; (one name fitting: then "/" for a folder or drive, else a space). C
; clear when anything was added.
Add:    lda #0
        sta added
        lda linePos             ; typed = linePos - nameAt
        sec
        sbc nameAt
        tay
@ch:    cpy commonLen
        bcs @tail
        lda common,y
        sty at
        cmp #' '                ; (a space: "\" before it)
        bne :+
        lda #'\'
        jsr Put
        bcs @full
        lda #' '
:       jsr Put
        bcs @full
        ldy at
        iny
        bne @ch
@tail:  lda found
        cmp #1
        bne @done
        lda #' '
        ldx commonKind
        cpx #K_DRIVE
        beq @dir
        cpx #K_FOLDER
        beq @dir
        cpx #K_UDIR
        bne :+
@dir:   lda #'/'
:       jsr Put
@done:
@full:  lda added
        beq :+
        clc
        rts
:       sec
        rts

; Put: A into the line at the cursor (InsCh). C set when the line is full.
Put:    jsr InsCh
        bcs :+
        inc added
:       rts

found:          .byte 0         ; names that fit (2: more than one)
listing:        .byte 0
again:          .byte 0
first:          .byte 0
wordAt:         .byte 0
nameAt:         .byte 0
at:             .byte 0
kind:           .byte 0
handle:         .byte 0
added:          .byte 0
commonLen:      .byte 0
commonKind:     .byte 0
info:           .res 16
nameBuf:        .res NAME_MAX + 3
common:         .res NAME_MAX + 3
pattern:        .res PAT_MAX
