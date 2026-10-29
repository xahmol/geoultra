; File system, reading: FindFile, ReadFile, ReadByte, FollowChain,
; GetFHdrInfo, FindFTypes. Written from the HG2G2022 descriptions;
; behaviour details (the 30 bytes FindFile copies, ReadFile's buffer
; overflow test and track/sector table, ReadByte's end index, FindFTypes'
; cleared buffer and permanent-name test) follow the reassembled GEOS 2.0
; kernal, mist64/geos kernal/files/*.s, read as behaviour reference only.
; Own code; checked with tests/conformance/files.py.
;
; The routines read through GetBlock, which does its own turbo and I/O
; set-up per block: kernal code at $D000-$FFFF cannot run between
; InitForIO and DoneWithIO (the C64 Kernal ROM is then mapped).

        .include "geos.inc"
        .include "kcalls.inc"

        .import SysFTypes
        .export FindFile, ReadFile, ReadByte, FollowChain, GetFHdrInfo
        .export FindFTypes
        .import ClearRam

OFF_FNAME       = 3
NAME_END        = OFF_FNAME + 16

        .segment "IOCODE"

; FindFile: r6 = NULL-terminated name. The entry to dirEntryBuf; r5 = the
; entry in diskBlkBuf, r1 = that block. X = 0 or FILE_NOT_FOUND.
; Destroys A, Y, r4, r6.
FindFile:
        php
        sei
        sec                     ; r6 - 3: the name lines up with the entry
        lda r6L
        sbc #OFF_FNAME
        sta r6L
        bcs @first
        dec r6H
@first: jsr Get1stDirEntry
        txa
        bne @end
@entry: ldy #0
        lda (r5),y
        beq @next               ; deleted
        ldy #OFF_FNAME
@cmp:   lda (r6),y
        beq @pad
        cmp (r5),y
        bne @next
        iny
        bne @cmp
@pad:   cpy #NAME_END           ; the rest of the name must be padding
        beq @found
        lda (r5),y
        iny
        cmp #$A0
        beq @pad
@next:  jsr GetNxtDirEntry
        txa
        bne @end
        tya
        beq @entry
        ldx #FILE_NOT_FOUND
        bne @end
@found: ldy #29
@copy:  lda (r5),y
        sta dirEntryBuf,y
        dey
        bpl @copy
        ldx #0
@end:   plp
        rts

        .segment "CODE"         ; (not under I/O: GEOS 2.0 allows it with I/O on)

; ReadFile: r1 = first block, r7 = buffer, r2 = its size. Follows the
; chain into the buffer; fileTrScTab+2 on gets the blocks. Returns X = 0
; or BFR_OVERFLOW (r1 = the block that did not fit, its data in
; diskBlkBuf), r7 = end of the data, r2 = bytes left. Destroys Y, r1, r4,
; r5L.
ReadFile:
        lda r1L
        sta fileTrScTab+2
        lda r1H
        sta fileTrScTab+3
        lda #2
        sta r5L                 ; table index
        lda #<diskBlkBuf
        sta r4L
        lda #>diskBlkBuf
        sta r4H
@block: jsr GetBlock
        txa
        bne @end
        ldy #254                ; data bytes in a block
        lda diskBlkBuf
        bne @fit
        ldy diskBlkBuf+1        ; last block: bytes 2 to this index
        dey
        beq @link
@fit:   lda r2H
        bne @copy
        cpy r2L
        beq @copy
        bcc @copy
        ldx #BFR_OVERFLOW
        rts
@copy:  sty r1L
@byte:  lda diskBlkBuf+1,y
        dey
        sta (r7),y
        bne @byte
        lda r1L
        clc
        adc r7L
        sta r7L
        bcc @size
        inc r7H
@size:  lda r2L
        sec
        sbc r1L
        sta r2L
        bcs @link
        dec r2H
@link:  inc r5L
        inc r5L
        ldy r5L
        lda diskBlkBuf+1
        sta r1H
        sta fileTrScTab+1,y
        lda diskBlkBuf
        sta r1L
        sta fileTrScTab,y
        bne @block
        ldx #0
@end:   rts

        .segment "IOCODE"

; ReadByte: the next byte of a chain in A. First call: r1 = first block,
; r4 = a block buffer, r5 = 0. Returns X = 0, or BFR_OVERFLOW after the
; last byte. Keep r1, r4, r5 between calls. Destroys Y.
ReadByte:
        ldy r5H
        cpy r5L
        beq @next
        lda (r4),y
        inc r5H
        ldx #0
        rts
@next:  ldx #BFR_OVERFLOW
        lda r1L
        beq @end                ; no more blocks
        jsr GetBlock
        txa
        bne @end
        ldy #0
        lda (r4),y
        sta r1L
        iny
        lda (r4),y
        sta r1H
        tax                     ; last block: data up to this index
        lda r1L
        beq @last
        ldx #$FF                ; else the whole block (end index 0)
@last:  inx
        stx r5L
        lda #2
        sta r5H
        jmp ReadByte
@end:   rts

; FollowChain: r1 = first block, r3 = table. Writes every block of the
; chain, then 0 and the last block's end index. X = error. Destroys A, Y,
; r1, r4.
FollowChain:
        php
        sei
        lda r3H
        pha
        ldy #0
@entry: lda r1L
        sta (r3),y
        iny
        lda r1H
        sta (r3),y
        iny
        bne @check
        inc r3H
@check: lda r1L
        beq @done
        tya
        pha
        jsr ReadBuff
        pla
        tay
        txa
        bne @end
        lda diskBlkBuf
        sta r1L
        lda diskBlkBuf+1
        sta r1H
        jmp @entry
@done:  ldx #0
@end:   pla
        sta r3H
        plp
        rts

; GetFHdrInfo: r9 = directory entry. Its file header to fileHeader (and
; the header's block to fileTrScTab+0); r1 = the entry's first block, r7 =
; the load address. X = error. Destroys A, Y, r4.
GetFHdrInfo:
        ldy #OFF_GHDR_PTR
        lda (r9),y
        sta r1L
        sta fileTrScTab
        iny
        lda (r9),y
        sta r1H
        sta fileTrScTab+1
        jsr HeaderBuf
        jsr GetBlock
        txa
        bne @end
        ldy #1
        lda (r9),y
        sta r1L
        iny
        lda (r9),y
        sta r1H
        lda fileHeader + O_GHST_ADDR
        sta r7L
        lda fileHeader + O_GHST_ADDR + 1
        sta r7H
@end:   rts

HeaderBuf:
        lda #<fileHeader
        sta r4L
        lda #>fileHeader
        sta r4H
        rts

; FindFTypes: r6 = buffer, r7L = GEOS file type, r7H = most names, r10 =
; permanent name prefix ($0000: any). The names, 17 bytes each (the
; buffer is cleared first); r7H counts down per name. X = error.
; Destroys A, Y, r0-r2L, r4, r6.
FindFTypes:
        php
        sei
        lda r6L
        sta r1L
        lda r6H
        sta r1H
        lda #0                  ; r0 = 17 * r7H
        sta r0H
        lda r7H
        asl
        rol r0H
        asl
        rol r0H
        asl
        rol r0H
        asl
        rol r0H
        adc r7H
        sta r0L
        bcc @clear
        inc r0H
@clear: jsr ClearRam
        sec
        lda r6L
        sbc #OFF_FNAME
        sta r6L
        bcs @first
        dec r6H
@first: jsr Get1stDirEntry
        txa
        bne @end
@entry: ldy #0
        lda (r5),y
        beq @next
        ldy #OFF_GFILE_TYPE
        lda (r5),y
        cmp r7L
        bne @next
        jsr ClassMatch
        txa
        bne @end
        tya
        bne @next
        ldy #OFF_FNAME
@name:  lda (r5),y
        cmp #$A0
        beq @nul
        sta (r6),y
        iny
        cpy #NAME_END
        bne @name
@nul:   lda #0
        sta (r6),y
        clc
        lda r6L
        adc #17
        sta r6L
        bcc @count
        inc r6H
@count: dec r7H
        beq @end
@next:  jsr GetNxtDirEntry
        txa
        bne @end
        tya
        beq @entry
@end:   plp
        jmp SysFTypes           ; drive E's desk accessories added

; ClassMatch: r5 = entry. With r10 set, its header to fileHeader and the
; permanent name compared with r10 (up to r10's NULL). Y = 0 when it
; matches, $FF when not; X = error.
ClassMatch:
        ldx #0
        lda r10L
        ora r10H
        beq @yes
        ldy #OFF_GHDR_PTR
        lda (r5),y
        sta r1L
        iny
        lda (r5),y
        sta r1H
        jsr HeaderBuf
        jsr GetBlock
        txa
        bne @end
        tay
@cmp:   lda (r10),y
        beq @yes
        cmp fileHeader + O_GHFNAME,y
        bne @no
        iny
        bne @cmp
@yes:   ldy #0
        rts
@no:    ldy #$FF
@end:   rts
