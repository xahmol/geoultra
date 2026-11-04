; File engine: copies between a GEOS drive and the Ultimate, raw
; (docs/FILE_ENGINE.md, "Copying"; engine.s has the module list): module
; 42 onto the Ultimate, module 43 from it (the source, the new entry's
; fields, the target), module 44 its blocks onto the GEOS drive. Own code.
;
; Raw: a CBM file's data as it is; a GEOS file only with FC_RAW and only
; a sequential one (its data, without the header; GEOS files as a whole
; come with CVT, step E4). Names: a GEOS name on the Ultimate gets its
; type's extension (".seq", ".prg", ".usr"; not with FC_RAW) and "%XX"
; for the characters FAT cannot hold; back on a GEOS drive the extension
; gives the type (else PRG) and goes, "%XX" is decoded, and the name is
; cut to 16 characters.

        .include "geos.inc"
        .include "hw.inc"
        .include "kcalls.inc"
        .include "engine.inc"

        .import OvlCall, SysRAMOp, folderT, folderS, FindFile

CBM_SEQ         = 1             ; CBM types (directory entry +0, bits 0-2)
CBM_PRG         = 2
CBM_USR         = 3
CLOSED          = $80           ; (the type byte of a closed file)
OFF_FNAME       = 3
OFF_DATE        = 23
U_PIECE         = 127           ; data bytes per WRITE_DATA (uCmd: 256)

        .segment "OVL42"
        .scope Mod42

        jmp OvUTo               ; entry 0

        .include "feult.inc"
        .include "fecd.inc"

Data:   jsr OvlCall             ; (module 45: the blocks written)
        .byte 45, 0

; OvUTo (FE_COPY, FE_MOVE onto the Ultimate): the source GEOS file in
; cEntry (on cSrcDrv), the target path resolved (an Ultimate folder: the
; source's name in it; else the path's last part). FC_OVERWRITE replaces
; an existing file. X = 0 or the error.
OvUTo:  ldx #FE_NOT_SUPPORTED   ; a GEOS file: only sequential, only raw
        lda cEntry + OFF_GHDR_PTR
        beq @cbm
        lda argR2
        and #FC_RAW
        beq @end
        lda cEntry + OFF_GSTRUC_TYPE
        cmp #VLIR
        beq @end
@cbm:   lda #0
        sta cDone
        sta cDone+1
        lda feName
        beq @folder             ; the top: a folder
        jsr UCdAll              ; a folder?
        txa
        beq @folder
        jsr UCd                 ; no: the last part is the name
        txa
        bne @end
        jsr Open
        jsr UPutName
        jmp @go
@folder:
        jsr Open
        jsr PutSrc
@go:    jsr UNoData
        jsr UExec
        txa
        bne @end
        jsr Data
        stx feM                 ; (the first error counts)
        lda #U_CLOSE
        jsr UBegin
        jsr UExec
        lda feM
        beq @end
        tax
@end:   rts

; Open: uCmd = OPEN, a new file (FC_OVERWRITE: made or replaced); the
; name follows.
Open:   lda #U_OPEN
        jsr UBegin
        lda argR2
        lsr
        lda #UO_NEW
        bcc :+
        lda #UO_ALWAYS
:       jmp UPut
        .assert FC_OVERWRITE = 1, error, "Open: FC_OVERWRITE in bit 0"

; PutSrc: the source's name (cEntry, $A0-padded) to uCmd, with "%XX" for
; what FAT cannot hold and, without FC_RAW, its type's extension.
PutSrc: ldx #0
@ch:    stx cCurS
        lda cEntry + OFF_FNAME,x
        cmp #$A0
        beq @ext
        jsr Escaped
        bcc @plain
        pha
        lda #'%'
        jsr UPut
        pla
        pha
        lsr
        lsr
        lsr
        lsr
        jsr Hex
        pla
        and #$0F
        jsr Hex
        jmp @more
@plain: jsr UPut
@more:  ldx cCurS
        inx
        cpx #FE_NAME_MAX
        bne @ch
@ext:   lda argR2
        and #FC_RAW
        bne @end
        lda cEntry
        and #$07
        tax
        dex
        cpx #3
        bcs @end                ; (no SEQ, PRG, USR: none)
        lda #'.'
        jsr UPut
        lda Ext1,x
        jsr UPut
        lda Ext2,x
        jsr UPut
        lda Ext3,x
        jmp UPut
@end:   rts

Ext1:   .byte "spu"
Ext2:   .byte "ers"
Ext3:   .byte "qgr"
        .assert CBM_SEQ = 1 && CBM_PRG = 2 && CBM_USR = 3, error, "PutSrc: the extensions"

; Escaped: C set when A cannot be in a FAT name (a control character,
; above $7E, or / \ : * ? " < > | %). A kept.
Escaped:
        cmp #' '
        bcc @yes
        cmp #$7F
        bcs @yes
        ldy #Bad - Bads - 1
@bad:   cmp Bads,y
        beq @yes
        dey
        bpl @bad
        clc
        rts
@yes:   sec
        rts
Bads:   .byte "/\:*?", '"', "<>|%"
Bad:

; Hex: the hex digit A (0-15) to uCmd.
Hex:    cmp #10
        bcc :+
        adc #'A' - '0' - 10 - 1
:       adc #'0'
        jmp UPut

        .endscope

        .segment "OVL43"
        .scope Mod43

        jmp OvUFrom             ; entry 0

        .include "feult.inc"
        .include "fecd.inc"

Fields: jsr OvlCall             ; (module 46: the new entry's fields)
        .byte 46, 0

Target: jsr OvlCall             ; (module 30: the target, checked)
        .byte 30, 0
Blocks: jsr OvlCall             ; (module 44: the blocks, the entry)
        .byte 44, 0

; OvUFrom (FE_COPY, FE_MOVE from the Ultimate; the source path resolved):
; the file opened, the new entry's fields from its name, size and date,
; the target checked (module 30), the blocks written (module 44), the
; file closed; for FE_MOVE then deleted. X = 0 or the error.
OvUFrom:
        ldx #FE_BAD_PATH
        lda feName
        beq @end                ; (the top)
        jsr UCd
        txa
        bne @end
        lda #U_OPEN
        jsr UBegin
        lda #UO_READ
        jsr UPut
        jsr UPutName
        jsr UNoData
        jsr UExec
        txa
        beq @open
        lda #U_CD               ; not opened: a folder?
        jsr UBegin
        jsr UPutName
        jsr UExec
        cpx #0
        bne @end
        ldx #FE_IS_FOLDER
@end:   rts
@open:  lda #U_INFO
        jsr UBegin
        lda #<diskBlkBuf
        sta r0L
        sta uEnd
        lda #>diskBlkBuf
        sta r0H
        sta uEnd+1
        inc uEnd+1
        jsr UExec
        txa
        bne @close
        jsr Fields
        bcs @close              ; (X: too big)
        jsr Target
        txa
        bne @close
        ldx #FE_NOT_SUPPORTED   ; onto the Ultimate too: not yet
        lda cToU
        bne @close
        lda #<curDirHead        ; room for all its blocks
        sta r5L
        lda #>curDirHead
        sta r5H
        jsr CalcBlksFree
        ldx #INSUFF_SPACE
        lda r4L
        cmp cEntry + OFF_SIZE
        lda r4H
        sbc cEntry + OFF_SIZE + 1
        bcc @close
        jsr Blocks
@close: stx feM                 ; (the first error counts)
        lda #U_CLOSE
        jsr UBegin
        jsr UNoData
        jsr UExec
        lda feM
        beq :+
        tax
:       txa
        bne @ret
        lda cMove
        beq @ret
        lda argR0               ; FE_MOVE: the source deleted
        sta r0L
        lda argR0+1
        sta r0H
        jsr Resolve
        txa
        bne @ret
        jsr UCd
        txa
        bne @ret
        lda #U_DELETE
        jsr UBegin
        jsr UPutName
        jmp UExec
@ret:   rts

Resolve:
        jsr OvlCall
        .byte 23, 0

        .endscope

        .segment "OVL44"
        .scope Mod44

        jmp OvUBlocks           ; entry 0

        .include "feult.inc"

; OvUBlocks: the open Ultimate file's bytes (cLeft of them) onto the
; target drive (current, its BAM in curDirHead), 254 a block, each block
; taken with SetNextFree; then the entry (cEntry, named feTmp) and the
; BAM. X = 0 or the error (FE_ULTIMATE: fewer bytes than its size).
OvUBlocks:
        lda #0
        sta cLastT
        sta cDone
        sta cDone+1
        jsr Alloc               ; the first block
        beq :+
        rts
:       lda cLastT
        sta cEntry + OFF_DE_TR_SC
        sta cCurT
        lda cLastS
        sta cEntry + OFF_DE_TR_SC + 1
        sta cCurS
@block: ldy #254                ; this block's bytes: Y
        lda cLeft+1
        ora cLeft+2
        bne @full
        lda cLeft
        cmp #254
        bcs @full
        tay
@full:  sty cNextT              ; (cNextT, cNextS: the count, here)
        tya
        beq @link               ; (an empty file: no read)
        lda #U_READ
        jsr UBegin
        lda cNextT
        jsr UPut
        lda #0
        jsr UPut
        lda #<(diskBlkBuf + 2)
        sta r0L
        lda #>(diskBlkBuf + 2)
        sta r0H
        lda #<(diskBlkBuf + $100)
        sta uEnd
        lda #>(diskBlkBuf + $100)
        sta uEnd+1
        jsr UExec
        txa
        bne @end
        ldx #FE_ULTIMATE        ; all of them?
        lda r0L
        sec
        sbc #2
        cmp cNextT
        bne @end
        lda cLeft               ; cLeft -= count
        sec
        sbc cNextT
        sta cLeft
        bcs @link
        lda cLeft+1
        bne :+
        dec cLeft+2
:       dec cLeft+1
@link:  lda cLeft               ; the last block: link 0, its last byte
        ora cLeft+1
        ora cLeft+2
        bne @more
        sta diskBlkBuf
        ldx cNextT
        inx
        stx diskBlkBuf+1
        bne @write
@more:  jsr Alloc               ; else the next block
        bne @end
        lda cLastT
        sta diskBlkBuf
        lda cLastS
        sta diskBlkBuf+1
@write: jsr Dest
        lda cCurT
        sta r1L
        lda cCurS
        sta r1H
        jsr WriteBuff
        txa
        bne @end
        jsr Progress
        ldx #FE_CANCELLED
        bcs @end
        lda diskBlkBuf
        beq Done
        sta cCurT
        lda diskBlkBuf+1
        sta cCurS
        jmp @block
@end:   rts
Done:   jmp Entry
        .assert <diskBlkBuf = 0, error, "OvUBlocks: the count from r0L"

        .include "fename.inc"
        .include "feentry.inc"
        .include "feblock.inc"
        .include "feprog.inc"

        .endscope

        .segment "OVL45"
        .scope Mod45

        jmp OvData              ; entry 0

        .include "feult.inc"
        .include "feprog.inc"

; OvData: the source's chain, block by block, written to the open file.
; X = 0 or the error.
OvData:   lda cEntry + OFF_DE_TR_SC
        sta cNextT
        lda cEntry + OFF_DE_TR_SC + 1
        sta cNextS
@block: lda cSrcDrv
        jsr SetDevice
        lda cNextT
        sta r1L
        lda cNextS
        sta r1H
        jsr ReadBuff
        txa
        bne @end
        lda diskBlkBuf          ; its bytes: up to 254, the last block's
        sta cNextT              ; to its link's sector
        lda diskBlkBuf+1
        sta cNextS
        ldy #255                ; cCurT: its last byte (255, or the
        lda cNextT              ; last block's link sector)
        bne :+
        ldy cNextS
:       sty cCurT
        ldx #2
@piece: cpx cCurT               ; a piece from X: at most U_PIECE bytes
        beq :+
        bcs @next               ; (past the last: an empty block)
:       stx cCurS
        lda #U_WRITE
        jsr UBegin
        lda #0
        jsr UPut
        jsr UPut
        ldx cCurS
@byte:  lda diskBlkBuf,x
        jsr UPut
        cpx cCurT
        beq @last
        inx
        lda uLen
        cmp #4 + U_PIECE
        bne @byte
        stx cCurS
        jsr Send
        bne @end
        ldx cCurS
        jmp @piece
@last:  jsr Send
        bne @end
@next:  jsr Progress
        ldx #FE_CANCELLED
        bcs @end
        ldx #0
        lda cNextT
        bne @block
@end:   rts

; Send: uCmd to the Ultimate, no data back. Z set when it worked, else X
; = the error.
Send:   jsr UNoData
        jsr UExec
        txa
        rts

        .endscope

        .segment "OVL46"
        .scope Mod46

        jmp OvFields            ; entry 0

FAT_OUT         = cEntry + OFF_DATE
        .include "fefat.inc"

; OvFields: the new entry in cEntry (and cLeft) from the open file:
; FILE_INFO's reply in diskBlkBuf, the name in the path (also to feTmp,
; zero-ended, as module 29's Source does for a GEOS file). C set and X =
; INSUFF_SPACE for more than 65535 blocks.
OvFields:
        ldx #29
        lda #0
        sta cSrcDrv             ; (no GEOS source: never "the source itself")
@zero:  sta cEntry,x
        dex
        bpl @zero
        lda diskBlkBuf          ; the size
        sta cLeft
        lda diskBlkBuf+1
        sta cLeft+1
        lda diskBlkBuf+2
        sta cLeft+2
        jsr FatDate
        jsr Name
        ldx #0                  ; the name to feTmp too (module 30 names
@tmp:   lda cEntry + OFF_FNAME,x ; the target after the source)
        cmp #$A0
        beq @end
        sta feTmp,x
        inx
        cpx #FE_NAME_MAX
        bne @tmp
@end:   lda #0
        sta feTmp,x
        jsr Count
        ldx #INSUFF_SPACE
        rts

; Name: the last part as a GEOS name in cEntry (type from the extension,
; else PRG; "%XX" decoded; cut to FE_NAME_MAX), $A0-padded.
Name:   ldx fePos               ; the end, and the last "."
        ldy #0
@end:   inx
        lda fePath,x
        beq @found
        cmp #'.'
        bne @end
        txa
        tay
        bne @end
@found: stx cCurT               ; cCurT: where the name ends
        lda #CLOSED | CBM_PRG
        sta cEntry
        lda argR2
        and #FC_RAW
        bne @copy
        tya                     ; ".xyz" at the very end?
        beq @copy
        clc
        adc #4
        cmp cCurT
        bne @copy
        ldx #2                  ; one of ours?
@ext:   lda fePath+1,y
        ora #$20
        cmp Ext1,x
        bne @other
        lda fePath+2,y
        ora #$20
        cmp Ext2,x
        bne @other
        lda fePath+3,y
        ora #$20
        cmp Ext3,x
        beq @type
@other: dex
        bpl @ext
        bmi @copy
@type:  inx
        txa
        ora #CLOSED
        sta cEntry
        sty cCurT               ; (the name ends at the ".")
@copy:  ldx fePos
        ldy #0
@ch:    inx
        cpx cCurT
        bcs @pad
        lda fePath,x
        cmp #'%'                ; "%XX"
        bne @put
        lda fePath+1,x
        jsr Digit
        bcs @lit
        asl
        asl
        asl
        asl
        sta cCurS
        lda fePath+2,x
        jsr Digit
        bcs @lit
        ora cCurS
        inx
        inx
        bne @put
@lit:   lda #'%'
@put:   sta cEntry + OFF_FNAME,y
        iny
        cpy #FE_NAME_MAX
        bne @ch
        rts
@pad:   lda #$A0
@fill:  sta cEntry + OFF_FNAME,y
        iny
        cpy #FE_NAME_MAX
        bne @fill
        rts

Ext1:   .byte "spu"
Ext2:   .byte "ers"
Ext3:   .byte "qgr"

; Digit: a hex digit in A (0-9, A-F, a-f) as 0-15, C clear; else C set.
Digit:  cmp #'0'
        bcc @no
        cmp #'9' + 1
        bcc @num
        ora #$20
        cmp #'a'
        bcc @no
        cmp #'f' + 1
        bcs @no
        sbc #'a' - 10 - 1       ; (C clear: one less)
        clc
        rts
@num:   sbc #'0' - 1            ; (C clear)
        clc
        rts
@no:    sec
        rts

; Count: cEntry's size = cLeft / 254 blocks, rounded up, at least one. C
; set when more than 65535.
Count:  lda cLeft
        sta r5L
        lda cLeft+1
        sta r5H
        lda cLeft+2
        sta r6L
        lda #0                  ; the remainder
        ldx #24
@bit:   asl r5L                 ; (the quotient's bits come in at the bottom)
        rol r5H
        rol r6L
        rol a
        bcs @sub
        cmp #254
        bcc @next
@sub:   sbc #254
        inc r5L
@next:  dex
        bne @bit
        cmp #1                  ; a remainder: one block more
        lda r5L
        adc #0
        sta cEntry + OFF_SIZE
        lda r5H
        adc #0
        sta cEntry + OFF_SIZE + 1
        lda r6L
        adc #0
        cmp #1                  ; (C: more than 65535)
        bcs @end
        lda cEntry + OFF_SIZE   ; none: one empty block
        ora cEntry + OFF_SIZE + 1
        bne @end
        inc cEntry + OFF_SIZE
        clc
@end:   rts

        .endscope
