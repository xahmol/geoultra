; File engine: GEOS files as CVT on the Ultimate (docs/FILE_ENGINE.md,
; "Copying"; engine.s has the module list): a GEOS file onto the open
; Ultimate file as CVT (module 56; VLIR files' records module 58), a CVT
; recognised by its signature block (module 60, from module 46) and
; converted back onto a GEOS drive (module 57; VLIR module 59). Shared:
; fecvtout.inc, fecvtread.inc, fecvtwrite.inc.
; Own code; the format as docs/GEOS_REFERENCE.md "CVT" describes it
; (Convert 2.5 and VICE c1541 -geoswrite/-geosread write and read it).
;
; A CVT: blocks of 254 bytes (a sector without its link). The signature
; block (the 30-byte directory entry, "SEQ formatted GEOS file V1.0" or
; "PRG ..." for VLIR, zeros), the header block (the header from its
; byte 2); then a sequential file's data, or for VLIR a record table
; (per record: its blocks and the last byte's index in its last block,
; "00 FF" an empty record, "00 00" none more) and every record's blocks,
; each padded to 254 bytes but the last one of the file.

        .include "geos.inc"
        .include "hw.inc"
        .include "kcalls.inc"
        .include "engine.inc"

        .import OvlCall

U_PIECE         = 120           ; data bytes per WRITE_DATA (as module 45)
SIG             = diskBlkBuf + 2 + 30   ; the signature in the first block
SIG_LEN         = 28
OFF_FNAME       = 3             ; (directory entry, as enginexfer.s)
OFF_DATE        = 23
CVT_HEAD        = 2 * 254       ; the signature and header blocks

        .segment "OVL56"
        .scope Mod56

        jmp OvCvtOut            ; entry 0

        .include "feult.inc"
        .include "feprog.inc"
        .include "fecvtout.inc"

Data:   jsr OvlCall             ; (module 45: a chain written as it is)
        .byte 45, 0
VlirOut:
        jsr OvlCall             ; (module 58: a VLIR file's table, records)
        .byte 58, 0

; OvCvtOut: the GEOS file in cEntry (on cSrcDrv) onto the open Ultimate
; file as CVT. A VLIR file's record table is counted from its chains
; first (no buffer: the pairs go out as they are counted), then the
; records follow. X = 0 or the error (FE_NOT_SUPPORTED: a record of more
; than 255 blocks).
OvCvtOut:
        ldx #29                 ; the signature block
@entry: lda cEntry,x
        sta diskBlkBuf+2,x
        dex
        bpl @entry
        ldx #0
@sig:   lda Sig,x
        sta SIG,x
        inx
        cpx #SIG_LEN
        bne @sig
        lda #0
@zero:  sta SIG,x
        inx
        cpx #<($100 - (SIG - diskBlkBuf))
        bne @zero
        jsr IsVlir
        bne :+
        ldx #2                  ; ("PRG formatted")
@prg:   lda Prg,x
        sta SIG,x
        dex
        bpl @prg
:       jsr SendFull
        bne @end
        lda cEntry + OFF_GHDR_PTR       ; the header block
        sta cNextT
        lda cEntry + OFF_GHDR_PTR + 1
        sta cNextS
        jsr ReadSrc
        bne @end
        jsr SendFull
        bne @end
        jsr Progress
        ldx #FE_CANCELLED
        bcs @end
        jsr IsVlir
        beq Vlir
        jmp Data                ; sequential: the data as it is
@end:   rts
Vlir:   jmp VlirOut

; IsVlir: Z set when cEntry is a VLIR file.
IsVlir: lda cEntry + OFF_GSTRUC_TYPE
        cmp #VLIR
        rts

Sig:    .byte "SEQ formatted GEOS file V1.0"
Prg:    .byte "PRG"
        .assert * - Sig = SIG_LEN + 3, error, "Sig: SIG_LEN"

        .endscope

        .segment "OVL58"
        .scope Mod58

        jmp OvVlirOut           ; entry 0

        .include "feult.inc"
        .include "feprog.inc"
        .include "fecvtout.inc"

; OvVlirOut (from module 56, the header sent): a VLIR file's index to
; fileHeader; the record table, then the records. X = 0 or the error.
OvVlirOut:   jsr Source
        lda cEntry + OFF_DE_TR_SC
        sta r1L
        lda cEntry + OFF_DE_TR_SC + 1
        sta r1H
        lda #<fileHeader
        sta r4L
        lda #>fileHeader
        sta r4H
        jsr GetBlock
        txa
        bne @end
        lda #0                  ; cLastT: the last record with blocks (its
        sta cLastT              ; offset in the index; 0: none)
        ldy #2
@last:  lda fileHeader,y
        beq :+
        sty cLastT
:       iny
        iny
        bne @last
        jsr Table
        bne @end
        jmp Records
@end:   rts

; Table: the record table: per index entry its pair (a chain counted;
; else the entry itself, 00 FF or 00 00). Z set when it worked, else X.
Table:  jsr Begin
        lda #2
        sta cRec
@rec:   ldy cRec
        lda fileHeader,y
        bne @count
        jsr UPut                ; (0, then FF or 0)
        ldy cRec
        lda fileHeader+1,y
        jsr UPut
        jmp @put
@count: sta cNextT
        lda fileHeader+1,y
        sta cNextS
        lda #0                  ; cLastS: its blocks
        sta cLastS
@walk:  inc cLastS
        bne :+
        ldx #FE_NOT_SUPPORTED   ; (more than 255)
        rts
:       jsr ReadSrc
        bne @end
        lda diskBlkBuf+1
        ldx diskBlkBuf
        beq @pair
        stx cNextT
        sta cNextS
        jmp @walk
@pair:  pha                     ; its blocks, its last byte
        lda cLastS
        jsr UPut
        pla
        jsr UPut
@put:   lda uLen                ; a full piece: sent
        cmp #4 + U_PIECE
        bcc @next
        jsr Exec
        bne @end
        jsr Begin
@next:  inc cRec
        inc cRec
        bne @rec
        lda uLen                ; the rest
        cmp #4 + 1
        bcc @done
        jmp Exec
@done:  ldx #0
@end:   rts
        .assert U_PIECE .mod 2 = 0, error, "Table: whole pairs in a piece"

; Records: each record's blocks, 254 bytes each but the file's last
; block, which ends at its last byte. X = 0 or the error.
Records:
        lda #2
        sta cRec
@rec:   ldy cRec
        lda fileHeader,y
        beq @skip
        sta cNextT
        lda fileHeader+1,y
        sta cNextS
@block: jsr ReadSrc
        bne @end
        lda diskBlkBuf          ; the next one
        sta cNextT
        lda diskBlkBuf+1
        sta cNextS
        lda #255                ; cCurT: the last byte sent
        sta cCurT
        lda cNextT
        bne @send               ; (not a record's last block)
        lda cRec
        cmp cLastT
        bne @send               ; (a record's last block: padded)
        lda cNextS              ; the file's last block: to its last byte
        sta cCurT
        cmp #2
        bcc @done
@send:  ldx #2
        jsr Send
        bne @end
@done:  jsr Progress
        ldx #FE_CANCELLED
        bcs @end
        lda cNextT
        bne @block
@skip:  inc cRec
        inc cRec
        bne @rec
        ldx #0
@end:   rts

        .endscope

        .segment "OVL57"
        .scope Mod57

        jmp OvCvtIn             ; entry 0

        .include "feult.inc"
        .include "feblock.inc"
        .include "feprog.inc"
        .include "fecvtread.inc"
        .include "fecvtwrite.inc"

Raw:    jsr OvlCall             ; (module 44: the bytes as they are)
        .byte 44, 0
Count:  jsr OvlCall             ; (module 46: cEntry's size from cLeft)
        .byte 46, 3
VlirIn: jsr OvlCall             ; (module 59: a VLIR file's records)
        .byte 59, 0
Entry:  jsr OvlCall             ; (module 52: the new entry, its long name)
        .byte 52, 0

; OvCvtIn (from module 43; the target checked and current, its BAM in
; curDirHead): a CVT's header block and data or records written (a
; sequential file's data through module 44), then the entry (module 52)
; with the blocks written as its size. Not a CVT: module 44 copies the
; bytes. X = 0 or the error (FE_ULTIMATE: the file shorter than its
; table says).
OvCvtIn:
        lda cCvt
        bne :+
        jmp Raw
:       lda #0
        sta cLastT
        sta cDone
        sta cDone+1
        ldx #>diskBlkBuf        ; the header block
        jsr Read
        bne @end
        lda #0
        sta diskBlkBuf
        lda #$FF
        sta diskBlkBuf+1
        jsr Alloc
        bne @end
        lda cLastT
        sta cEntry + OFF_GHDR_PTR
        sta cCurT
        lda cLastS
        sta cEntry + OFF_GHDR_PTR + 1
        sta cCurS
        jsr Write
        bne @end
        lda cEntry + OFF_GSTRUC_TYPE
        cmp #VLIR
        beq Vlir
        jsr Count               ; sequential: its size, and one for the
        inc cEntry + OFF_SIZE   ; header; the data and the entry
        bne :+
        inc cEntry + OFF_SIZE + 1
:       jmp Raw
@end:   rts

; Vlir: the records (module 59), the index, then the entry with the
; blocks written as its size.
Vlir:   jsr VlirIn
        txa
        bne @end
        jsr Index
        bne @end
        lda cDone
        sta cEntry + OFF_SIZE
        lda cDone+1
        sta cEntry + OFF_SIZE + 1
        jmp Entry
@end:   rts

; Index: the index (fileHeader) into a new block, cEntry's first block.
; Z set when it worked, else X = the error.
Index:  jsr Alloc
        bne @end
        lda #0
        sta fileHeader
        lda #$FF
        sta fileHeader+1
        lda cLastT
        sta cEntry + OFF_DE_TR_SC
        sta r1L
        lda cLastS
        sta cEntry + OFF_DE_TR_SC + 1
        sta r1H
        lda #<fileHeader
        sta r4L
        lda #>fileHeader
        sta r4H
        jsr Dest
        jsr PutBlock
        txa
        bne @end
        jsr Progress
        ldx #FE_CANCELLED
        bcs @end
        ldx #0
@end:   rts

        .endscope

        .segment "OVL59"
        .scope Mod59

        jmp OvVlirIn            ; entry 0

        .include "feult.inc"
        .include "feblock.inc"
        .include "feprog.inc"
        .include "fecvtread.inc"
        .include "fecvtwrite.inc"

; OvVlirIn (from module 57, the header block written): the record table
; to fileHeader, each pair made the record's first block as its chain is
; written (module 57 writes the index). X = 0 or the error.
OvVlirIn:   ldx #>fileHeader
        jsr Read
        bne @end
        lda #2
        sta cRec
@rec:   ldy cRec
        lda fileHeader,y
        beq @skip               ; (00 FF, 00 00: as they are)
        jsr Chain
        bne @end
@skip:  inc cRec
        inc cRec
        bne @rec
        ldx #0
@end:   rts

; Chain: record cRec's blocks (its pair in fileHeader: their number, the
; last one's last byte) read and written as a chain; the pair made its
; first block. Z set when it worked, else X = the error.
Chain:  sta cNextT              ; cNextT: blocks to go, cNextS: the last
        lda fileHeader+1,y      ; one's last byte
        sta cNextS
        jsr Alloc
        bne @end
        ldy cRec
        lda cLastT
        sta fileHeader,y
        sta cCurT
        lda cLastS
        sta fileHeader+1,y
        sta cCurS
@block: ldx #>diskBlkBuf
        jsr Read
        bne @end
        ldx #FE_ULTIMATE        ; (nothing left: shorter than its table)
        lda cCount
        beq @end
        dec cNextT
        beq @last
        jsr Alloc
        bne @end
        lda cLastT
        sta diskBlkBuf
        lda cLastS
        sta diskBlkBuf+1
        jsr Write
        bne @end
        lda diskBlkBuf
        sta cCurT
        lda diskBlkBuf+1
        sta cCurS
        jmp @block
@last:  lda #0
        sta diskBlkBuf
        lda cNextS
        sta diskBlkBuf+1
        jmp Write
@end:   rts

        .endscope

        .segment "OVL60"
        .scope Mod60

        jmp OvHead              ; entry 0

        .include "feult.inc"
        .include "fecvtread.inc"

; OvHead (from module 46, the entry's fields made from the open file):
; without FC_RAW, a file of at least two blocks whose first block has a
; CVT's signature is one (cCvt set): its type, structure, GEOS type and
; date to cEntry; ".cvt" off the name in feTmp, and the CVT's own name
; there instead when they differ only in case; cLeft without the
; signature block. Otherwise the file is read again from its start.
; Destroys A, X, Y.
OvHead: lda #0
        sta cCvt
        lda argR2
        and #FC_RAW
        bne @end
        lda cLeft+2             ; at least the two first blocks
        bne @read
        lda cLeft
        cmp #<CVT_HEAD
        lda cLeft+1
        sbc #>CVT_HEAD
        bcc @end
@read:  ldx #>diskBlkBuf
        jsr Read
        bne @seek
        ldx #SIG_LEN - 1        ; "SEQ" or "PRG", then the rest as ours
@sig:   lda SIG,x
        cpx #3
        bcs @same
        cmp Seq,x
        beq @next
        cmp Prg,x
        bne @back
        beq @next
@same:  cmp Seq,x
        bne @back
@next:  dex
        bpl @sig
        inc cCvt
        lda diskBlkBuf+2        ; the entry's fields
        sta cEntry
        ldx #OFF_GSTRUC_TYPE
@field: lda diskBlkBuf+2,x
        sta cEntry,x
        inx
        cpx #OFF_DATE + 5
        bne @field
        jmp Named
@back:  lda cLeft                ; not a CVT: its size as it was, and
        clc                     ; from its start again
        adc cCount
        sta cLeft
        bcc @seek
        inc cLeft+1
        bne @seek
        inc cLeft+2
@seek:  lda #U_SEEK
        jsr UBegin
        lda #0
        ldx #4
@pos:   jsr UPut
        dex
        bne @pos
        jsr UNoData
        jsr UExec               ; (its error: the copy's read finds it)
@end:   rts

; Named: ".cvt" off feTmp's end; then the CVT's name (OFF_FNAME, 16
; bytes padded with $A0) instead when feTmp is the same but for case.
Named:  ldx #$FF                ; feTmp's end
@len:   inx
        lda feTmp,x
        bne @len
        cpx #4 + 1
        bcc @cmp
        ldy #3
@ext:   lda feTmp-1,x
        ora #$20
        cmp Ext,y
        bne @cmp
        dex
        dey
        bpl @ext
        lda #0                  ; (X: at the ".")
        sta feTmp,x
@cmp:   ldx #0
@ch:    lda diskBlkBuf+2+OFF_FNAME,x
        cmp #$A0
        beq @end16
        eor feTmp,x
        beq @eq
        cmp #$20                ; (letters: only their case differs)
        bne @no
        lda feTmp,x
        ora #$20
        cmp #'a'
        bcc @no
        cmp #'z' + 1
        bcs @no
@eq:    inx
        cpx #16
        bne @ch
@end16: lda feTmp,x             ; the same length too?
        bne @no
@copy:  dex                     ; then the CVT's own name
        bmi @no
        lda diskBlkBuf+2+OFF_FNAME,x
        sta feTmp,x
        jmp @copy
@no:    rts

Ext:    .byte ".cvt"
Seq:    .byte "SEQ formatted GEOS file V1.0"
Prg:    .byte "PRG"

        .endscope
