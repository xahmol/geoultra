; File engine: streams on the Ultimate's file system (docs/FILE_ENGINE.md
; "Functions"; engine.s has the module list): module 61 FE_OPEN, module
; 62 FE_READ, module 63 FE_WRITE, module 64 their setup (the handle,
; the file opened at its place, closed); shared: fepath.inc,
; festreamu.inc.
; Own code.
;
; The Ultimate's DOS has one open file, and FE_STAT, copies and listings
; open their own, so no file stays open between calls: FE_OPEN checks
; the file (and makes it, for writing) and keeps its path in the REU
; (FE_UPATHS, one page per handle); every FE_READ and FE_WRITE enters
; its folder, opens it, seeks to the stream's place, moves the bytes and
; closes it. FE_CLOSE only frees the handle. A CVT of a sequential GEOS
; file reads as that file's data (from byte 508); a VLIR one is refused
; (STRUCT_MISMAT), as on GEOS drives.

        .include "geos.inc"
        .include "hw.inc"
        .include "kcalls.inc"
        .include "engine.inc"

        .import OvlCall, SysRAMOp

CVT_DATA        = 2 * 254       ; a sequential CVT's data starts here
SIG_AT          = 30            ; the signature in a CVT's first block
SIG_LEN         = 28
U_PIECE         = 120           ; data bytes per WRITE_DATA (as module 45)

        .segment "OVL61"
        .scope Mod61

        jmp OvUOpen             ; entry 0

        .include "fereu.inc"
        .include "feult.inc"
        .include "fecd.inc"
        .include "fepath.inc"

; OvUOpen (FE_OPEN on an Ultimate path, from module 32: the path
; resolved, feHandle free): the file opened as r2L asks (FO_READ: it
; must be there, a folder is FE_IS_FOLDER; FO_WRITE: made or emptied;
; FO_APPEND: made when not there), its size and start found, closed;
; the handle and its path kept. A = the handle, X = 0 or the error.
OvUOpen:
        ldx #FE_BAD_PATH        ; (a top)
        lda feName
        beq @end
        jsr UCd
        txa
        bne @end
        lda #U_OPEN
        jsr UBegin
        ldx argR2
        lda Attrs,x
        jsr UPut
        jsr UPutName
        jsr UNoData
        jsr UExec
        txa
        beq @open
        lda argR2
        bne @end                ; (writing: its error)
        lda #U_CD               ; reading: a folder?
        jsr UBegin
        jsr UPutName
        jsr UExec
        cpx #0
        bne @end
        ldx #FE_IS_FOLDER
@end:   rts
@open:  lda #0                  ; H_UPOS, H_UEND
        ldx #5
@zero:  sta feH + H_UPOS,x
        dex
        bpl @zero
        lda argR2
        cmp #FO_WRITE
        beq @ok
        jsr Size
        bne @close
        lda argR2
        bne @tail
        jsr Cvt                 ; reading: a CVT's data only
        jmp @close
@tail:  ldx #2                  ; appending: at its end
@pos:   lda feH + H_UEND,x
        sta feH + H_UPOS,x
        dex
        bpl @pos
@ok:    ldx #0
@close: stx feM
        lda #U_CLOSE
        jsr UBegin
        jsr UNoData
        jsr UExec
        ldx feM
        bne @end
        ldy #REU_STASH          ; the path, the handle
        jsr PathOp
        lda fePos
        sta feH + H_UFPOS
        lda #HT_UREAD
        ldx argR2
        beq :+
        lda #HT_UWRITE
:       sta feH + H_TYPE
        ldy #REU_STASH
        jsr HandleOp
        lda feHandle
        ldx #0
        rts

; Attrs: the OPEN attribute per FO_READ, FO_WRITE, FO_APPEND.
Attrs:  .byte UO_READ, UO_ALWAYS, UO_APPEND
        .assert FO_READ = 0 && FO_WRITE = 1 && FO_APPEND = 2, error, "Attrs: FO_*"

; Size: the open file's size (FILE_INFO) to H_UEND. Z set when it
; worked, else X = the error.
Size:   lda #U_INFO
        jsr UBegin
        jsr Reply
        jsr UExec
        txa
        bne @end
        ldx #2
@size:  lda diskBlkBuf,x
        sta feH + H_UEND,x
        dex
        bpl @size
        ldx #0
@end:   rts

; Cvt: a file of at least CVT_DATA bytes whose signature is a sequential
; CVT's: read from CVT_DATA on; a VLIR CVT's: X = STRUCT_MISMAT.
; Otherwise from its start. X = 0 or the error.
Cvt:    ldx #0
        lda feH + H_UEND+2
        bne @read
        lda feH + H_UEND
        cmp #<CVT_DATA
        lda feH + H_UEND+1
        sbc #>CVT_DATA
        bcc @end
@read:  lda #U_READ             ; the signature
        jsr UBegin
        lda #SIG_AT + SIG_LEN
        jsr UPut
        lda #0
        jsr UPut
        jsr Reply
        jsr UExec
        txa
        bne @end
        ldy #SIG_LEN - 1        ; " formatted GEOS file V1.0"
@rest:  lda diskBlkBuf + SIG_AT,y
        cmp Sig,y
        bne @none
        dey
        cpy #3
        bcs @rest
@kind:  lda diskBlkBuf + SIG_AT,y       ; "SEQ" or "PRG"
        cmp Sig,y
        bne @prg
        dey
        bpl @kind
        lda #<CVT_DATA          ; SEQ: its data
        sta feH + H_UPOS
        lda #>CVT_DATA
        sta feH + H_UPOS+1
@none:  ldx #0
@end:   rts
@prg:   ldy #2
@vlir:  lda diskBlkBuf + SIG_AT,y
        cmp Prg,y
        bne @none
        dey
        bpl @vlir
        ldx #STRUCT_MISMAT
        rts

; Reply: the reply's data to diskBlkBuf (one page at most).
Reply:  lda #<diskBlkBuf
        sta r0L
        sta uEnd
        lda #>diskBlkBuf
        sta r0H
        sta uEnd+1
        inc uEnd+1
        rts

Sig:    .byte "SEQ formatted GEOS file V1.0"
Prg:    .byte "PRG"
        .assert Prg - Sig = SIG_LEN, error, "Sig: SIG_LEN"

        .endscope

        .segment "OVL62"
        .scope Mod62

        jmp OvURead             ; entry 0

        .include "fereu.inc"
        .include "feult.inc"
        .include "festreamu.inc"

; OvURead (FE_READ on an Ultimate stream; Y = the handle, r1 = a buffer,
; r2 = bytes wanted): up to the data's end. r2 = bytes read (fewer: the
; end). X = 0 or the error.
OvURead:
        lda #HT_UREAD
        jsr UStream
        beq :+
        rts
:       sec                     ; at most what is left: r5 = end - place
        lda feH + H_UEND
        sbc feH + H_UPOS
        sta r5L
        lda feH + H_UEND+1
        sbc feH + H_UPOS+1
        sta r5H
        lda feH + H_UEND+2
        sbc feH + H_UPOS+2
        bne @fits               ; (64 KB or more)
        lda r5H
        cmp sLeft+1
        bne :+
        lda r5L
        cmp sLeft
:       bcs @fits
        lda r5L
        sta sLeft
        lda r5H
        sta sLeft+1
@fits:  lda sLeft
        ora sLeft+1
        beq @done
        lda #UO_READ
        jsr OpenAt
        bne @close
@piece: ldy #255                ; feM: this read's bytes
        lda sLeft+1
        bne :+
        ldy sLeft
:       sty feM
        lda #U_READ
        jsr UBegin
        lda feM
        jsr UPut
        lda #0
        jsr UPut
        lda sPtr
        sta r0L
        clc
        adc feM
        sta uEnd
        lda sPtr+1
        sta r0H
        adc #0
        sta uEnd+1
        jsr UExec
        txa
        bne @close
        lda r0L                 ; the bytes that came
        sec
        sbc sPtr
        jsr Moved
        cmp feM
        bcc @last               ; (fewer: the end)
        lda sLeft
        ora sLeft+1
        bne @piece
@last:  ldx #0
@close: jsr Close
        bne @ret
@done:  lda sGot
        sta argR2
        lda sGot+1
        sta argR2+1
        jmp Keep
@ret:   rts

        .endscope

        .segment "OVL63"
        .scope Mod63

        jmp OvUWrite            ; entry 0

        .include "fereu.inc"
        .include "feult.inc"
        .include "festreamu.inc"

; OvUWrite (FE_WRITE on an Ultimate stream; Y = the handle, r1 = the
; bytes, r2 their number): written at the stream's place. X = 0 or the
; error.
OvUWrite:
        lda #HT_UWRITE
        jsr UStream
        bne @ret
        lda sLeft
        ora sLeft+1
        beq @keep
        lda #UO_WRITE
        jsr OpenAt
        bne @close
@piece: lda #U_WRITE            ; a piece of U_PIECE bytes at most
        jsr UBegin
        lda #0
        jsr UPut
        jsr UPut
        lda sPtr
        sta r0L
        lda sPtr+1
        sta r0H
@byte:  ldy #0
        lda (r0),y
        jsr UPut
        inc r0L
        bne :+
        inc r0H
:       lda #1
        jsr Moved
        lda sLeft
        ora sLeft+1
        beq @send
        lda uLen
        cmp #4 + U_PIECE
        bne @byte
@send:  jsr UNoData
        jsr UExec
        txa
        bne @close
        lda sLeft
        ora sLeft+1
        bne @piece
@close: jsr Close
        bne @ret
@keep:  jmp Keep
@ret:   rts

        .endscope

        .segment "OVL64"
        .scope Mod64

        jmp UStream             ; entry 0
        jmp OpenAt              ; entry 3
        jmp Close               ; entry 6

        .include "fereu.inc"
        .include "feult.inc"
        .include "fecd.inc"
        .include "fepath.inc"

; UStream: handle feY of type A to feH, its path to fePath and fePos;
; sPtr, sLeft from r1, r2, sGot 0. Z set when it worked, else X =
; FE_BAD_HANDLE.
UStream:
        sta feM
        ldx #FE_BAD_HANDLE
        ldy feY
        cpy #FE_HANDLES_N
        bcs @end
        sty feHandle
        ldy #REU_FETCH
        jsr HandleOp
        ldx #FE_BAD_HANDLE
        lda feH + H_TYPE
        cmp feM
        bne @end
        ldx #3
@args:  lda argR1,x             ; (sPtr, sLeft: r1, r2)
        sta sPtr,x
        dex
        bpl @args
        lda #0
        sta sGot
        sta sGot+1
        ldy #REU_FETCH
        jsr PathOp
        lda feH + H_UFPOS
        sta fePos
        ldx #0
@end:   rts
        .assert sLeft = sPtr + 2, error, "UStream: sPtr, sLeft from r1, r2"

; OpenAt: the stream's folder entered, its file opened with attribute A
; and the place set (H_UPOS). Z set when it worked, else X = the error.
OpenAt: pha
        ldx fePos
        jsr UCdX
        pla
        cpx #0
        bne @end
        pha
        lda #U_OPEN
        jsr UBegin
        pla
        jsr UPut
        jsr UPutName
        jsr UNoData
        jsr UExec
        txa
        bne @end
        lda #U_SEEK
        jsr UBegin
        lda feH + H_UPOS
        jsr UPut
        lda feH + H_UPOS+1
        jsr UPut
        lda feH + H_UPOS+2
        jsr UPut
        lda #0
        jsr UPut
        jsr UNoData
        jsr UExec
        txa
@end:   rts

; Close: the file closed; X = the first error (X at the call, else the
; close's). Z set when there was none.
Close:  stx feMN
        lda #U_CLOSE
        jsr UBegin
        jsr UNoData
        jsr UExec
        lda feMN
        beq :+
        tax
:       txa
        rts

        .endscope
