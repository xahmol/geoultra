; A folder walk for copying and deleting folders with everything in
; them: gush's cp -r (src/gush/tree.s) and the desktop's folders
; (src/desktop/tree.s). Shared code, own design: one include since the
; eighth code sweep (2026-11-11), when the two copies had grown apart.
;
; Each folder's listing is read whole into the application's REU (bank
; TREE_BANK, one TREE_SLOT slot per entry: the kind, the name, the size
; in tracks; each level after the one above it) before anything in it
; is touched, so no listing stays open (the engine has few handles) and
; folders can nest TREE_DEPTH deep. One walk for two jobs (op):
; OP_COPY makes each target folder (tDst) first (an existing one is
; used; a 1581 partition as big as its source), then copies its
; entries; OP_DELETE deletes the entries first, then the folder.
;
; The includer (in the segment the walk runs from) defines:
; - constants TREE_BANK, TREE_DEPTH, TREE_SLOT (64), TREE_TOO_MANY (the
;   error for a level of more than 255 entries or a full bank),
;   FILE_EXISTS, FE_BAD_PATH, and StashRAM, FetchRAM, FileEngine;
; - variables op, depth, handle, mkTracks, srcLen, dstLen, lvIndex,
;   lvCount, lvSlotLo, lvSlotHi, lvSrcLen, lvDstLen (TREE_DEPTH bytes
;   each), tinfo (16), entry (TREE_SLOT), tSrc and tDst (256 each: the
;   paths, zero-ended);
; - WalkFile: a file at tSrc (and its target at tDst when copying)
;   copied or deleted; C set: the walk stops;
; - WalkFail: error X about tSrc said; the walk stops (C set);
; - WalkFailDst: the same about tDst (a target folder not made);
; - WalkSkip: error X about the entry at tSrc said (a path too long, a
;   folder too deep); C set: the walk stops, C clear: it goes on.
;
; WalkTop: op = A, tSrc (and tDst) set, mkTracks set (OP_COPY): the
; walk from there down. C set when it stopped.

OP_COPY         = 0
OP_DELETE       = 1
TREE_SLOTS      = $10000 / TREE_SLOT
TREE_PATH_END   = 254           ; a path's last place (with its zero)

; WalkStop: C set (stopped; already said). First, near the branches to
; it (the includer's code before the include must not run into it).
WalkStop:
        sec
        rts

WalkTop:
        sta op
        lda #0
        sta depth
        sta lvSlotLo
        sta lvSlotHi
; Walk: one level: tDst made (copying), tSrc's listing read, each entry
; done (folders one level deeper), tSrc removed afterwards (deleting).
Walk:   lda op
        bne :+
        jsr WalkMake
        bcs WalkStop
:       jsr WalkList
        bcs WalkStop
        ldx depth
        lda #0
        sta lvIndex,x
@entry: ldx depth
        lda lvIndex,x
        cmp lvCount,x
        bcc :+
        jmp @end
:       jsr WalkFetch
        ldx depth
        lda srcLen
        sta lvSrcLen,x
        lda dstLen
        sta lvDstLen,x
        jsr WalkExtend          ; the paths one part longer
        bcc :+
        ldx #FE_BAD_PATH        ; (too long: said; on, or stop)
        jsr WalkSkip
        bcs WalkStop
        jmp @next
:       lda entry
        cmp #K_FOLDER
        beq @sub
        cmp #K_UDIR
        beq @sub
        jsr WalkFile
        bcs WalkStop
        jmp @next
@sub:   ldx depth
        cpx #TREE_DEPTH - 1
        bcc :+
        ldx #FE_BAD_PATH        ; (deeper than the walk goes: said)
        jsr WalkSkip
        bcs WalkStop
        jmp @next
:       lda lvSlotLo,x          ; the next level's slots after this one's
        clc
        adc lvCount,x
        sta lvSlotLo + 1,x
        lda lvSlotHi,x
        adc #0
        sta lvSlotHi + 1,x
        lda entry + TREE_SLOT - 1
        sta mkTracks
        inc depth
        jsr Walk
        php
        dec depth
        plp
        bcc @next
        rts                     ; (C set: stopped)
@next:  ldx depth               ; the paths as they were, the next entry
        ldy lvSrcLen,x
        sty srcLen
        lda #0
        sta tSrc,y
        ldy lvDstLen,x
        sty dstLen
        sta tDst,y
        inc lvIndex,x
        jmp @entry
@end:   lda op                  ; deleting: the folder itself, now empty
        beq @ok
        lda #<tSrc
        sta r0L
        lda #>tSrc
        sta r0H
        lda #FE_RMDIR
        jsr FileEngine
        txa
        beq @ok
        jmp WalkFail
@ok:    clc
        rts

; WalkMake: tDst made (FE_MKDIR, mkTracks; there already: used). C set:
; stop (said).
WalkMake:
        lda #<tDst
        sta r0L
        lda #>tDst
        sta r0H
        lda mkTracks            ; (a 1581 partition: the source's size)
        sta r2L
        lda #FE_MKDIR
        jsr FileEngine
        txa
        beq @ok
        cpx #FILE_EXISTS
        beq @ok
        jmp WalkFailDst         ; (about tDst: the folder not made)
@ok:    clc
        rts

; WalkList: tSrc's entries (kind, name, tracks) into this level's slots;
; lvCount their number. C set: stop (said).
WalkList:
        lda #<tSrc
        sta r0L
        lda #>tSrc
        sta r0H
        lda #FE_OPENDIR
        jsr FileEngine
        sta handle              ; (A: the handle; txa would lose it)
        txa
        beq :+
        jmp WalkFail
:       ldx depth
        sta lvCount,x
@read:  lda #<tinfo
        sta r1L
        lda #>tinfo
        sta r1H
        lda #<(entry + 1)
        sta r2L
        lda #>(entry + 1)
        sta r2H
        lda #0
        sta r3L
        sta r3H
        ldy handle
        lda #FE_READDIR
        jsr FileEngine
        txa
        bne @close
        ldx depth               ; room: 255 here, the bank's slots in all
        lda lvCount,x
        cmp #255
        bcs @full
        clc
        adc lvSlotLo,x
        lda lvSlotHi,x
        adc #0
        cmp #>TREE_SLOTS
        bcs @full
        lda tinfo + FI_KIND
        sta entry
        jsr WalkTracks
        sta entry + TREE_SLOT - 1
        ldx depth
        lda lvCount,x
        jsr WalkSlot
        jsr StashRAM
        ldx depth
        inc lvCount,x
        jmp @read
@close: ldy handle
        lda #FE_CLOSE
        jsr FileEngine
        clc
        rts
@full:  ldy handle              ; (too many entries: the walk stops)
        lda #FE_CLOSE
        jsr FileEngine
        ldx #TREE_TOO_MANY
        jmp WalkFail

; WalkFetch: this level's entry lvIndex into entry.
WalkFetch:
        ldx depth
        lda lvIndex,x
        jsr WalkSlot
        jmp FetchRAM

; WalkSlot: r0-r3L for slot A of this level (lvSlotLo/Hi + A) <-> entry
; (slot * 64: the slot number's bytes shifted right by two).
WalkSlot:
        ldx depth
        clc
        adc lvSlotLo,x
        sta r1H
        lda lvSlotHi,x
        adc #0
        sta r2L
        lda #0
        lsr r2L
        ror r1H
        ror a
        lsr r2L
        ror r1H
        ror a
        sta r1L
        lda #<entry
        sta r0L
        lda #>entry
        sta r0H
        lda #TREE_SLOT
        sta r2L
        lda #0
        sta r2H
        lda #TREE_BANK
        sta r3L
        rts
        .assert TREE_SLOT = 64, error, "WalkSlot: 64 bytes a slot"

; WalkTracks: A = tinfo's size in blocks / 40 (a 1581 partition's
; tracks; at most 255). Destroys X, Y.
WalkTracks:
        lda tinfo + FI_SIZE
        sta r2L
        lda tinfo + FI_SIZE + 1
        sta r2H
        ldx #0
@sub:   lda r2L
        sec
        sbc #40
        tay
        lda r2H
        sbc #0
        bcc @end
        sta r2H
        sty r2L
        inx
        bne @sub
        dex
@end:   txa
        rts

; WalkExtend: "/" (unless the path ends in one) and entry's name after
; tSrc and (copying) tDst, srcLen and dstLen kept. C set: too long.
WalkExtend:
        ldx srcLen
        lda #<tSrc
        ldy #>tSrc
        jsr WalkAdd
        bcs @end
        stx srcLen
        lda op
        bne @ok                 ; (deleting: no target)
        ldx dstLen
        lda #<tDst
        ldy #>tDst
        jsr WalkAdd
        bcs @end
        stx dstLen
@ok:    clc
@end:   rts

; WalkAdd: "/" and entry's name after the path at A/Y (X its length);
; X = the new length. C set: too long (the path's end then cut back by
; the walk at its next entry).
WalkAdd:
        sta r4L
        sty r4H
        txa
        tay
        dey
        lda (r4),y              ; ("/" unless it ends in one)
        iny
        cmp #'/'
        beq :+
        lda #'/'
        sta (r4),y
        iny
:       ldx #0
@ch:    lda entry + 1,x
        sta (r4),y
        beq @done
        inx
        iny
        cpy #TREE_PATH_END
        bcc @ch
        sec
        rts
@done:  tya
        tax
        clc
        rts
