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
        .export FindFTypes, DirName

OFF_FNAME       = 3

        .segment "IOCODE"

; FindFile: r6 = NULL-terminated name. The entry to dirEntryBuf; r5 = the
; entry in diskBlkBuf, r1 = that block. X = 0 or FILE_NOT_FOUND.
; Destroys A, Y, r4, r6.
; Own design (clean-room rewrite, 2026-11-20): the comparison in
; SameName, through r4 pointing at the entry's name.
FindFile:
        php
        sei
        jsr Get1stDirEntry
        txa
        bne @end
@entry: jsr SameName
        bcc @found
        jsr GetNxtDirEntry
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

; SameName: C clear when the entry at r5 is in use and its name is the
; one at r6 (zero-ended; the entry's 16 characters padded with $A0).
; Destroys A, Y, r4 (the entry's name). Keeps X.
SameName:
        ldy #0
        lda (r5),y
        beq @no                 ; (a deleted entry)
        jsr DirName
        ldy #0
@char:  lda (r6),y              ; the name's characters
        beq @rest
        cmp (r4),y
        bne @no
        iny
        cpy #16
        bne @char
        clc
        rts
@rest:  lda (r4),y              ; after its end only padding
        cmp #$A0
        bne @no
        iny
        cpy #16
        bne @rest
        clc
        rts
@no:    sec
        rts

; DirName: r4 = the name in the directory entry at r5. Keeps X, Y.
DirName:
        lda r5L
        clc
        adc #OFF_FNAME
        sta r4L
        lda r5H
        adc #0
        sta r4H
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
@copy:  sty r1L                 ; (own design, clean-room rewrite
        ldy #0                  ; 2026-11-20: forwards, counted)
@byte:  lda diskBlkBuf+2,y
        sta (r7),y
        iny
        cpy r1L
        bne @byte
        sec                     ; bytes left, then the buffer moved on
        lda r2L
        sbc r1L
        sta r2L
        bcs @move
        dec r2H
@move:  tya
        clc
        adc r7L
        sta r7L
        bcc @link
        inc r7H
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
        ldy #1                  ; its link (own design, clean-room
        lda (r4),y              ; rewrite 2026-11-20)
        sta r1H
        dey
        lda (r4),y
        sta r1L
        sty r5L                 ; a full block: up to its end (index 0)
        bne @start
        ldx r1H                 ; the last block: up to the index in its
        inx                     ; link's second byte
        stx r5L
@start: lda #2
        sta r5H
        jmp ReadByte
@end:   rts

; FollowChain: r1 = first block, r3 = table. Writes every block of the
; chain, then 0 and the last block's end index. X = error. Destroys A, Y,
; r1, r4.
; Own design (clean-room rewrite, 2026-11-20): r3 walks the table and is
; put back from the stack.
FollowChain:
        php
        sei
        lda r3L
        pha
        lda r3H
        pha
@entry: ldy #1                  ; this block into the table
        lda r1H
        sta (r3),y
        dey
        lda r1L
        sta (r3),y
        beq @done               ; (track 0: r1H was the end index)
        clc
        lda r3L
        adc #2
        sta r3L
        bcc @read
        inc r3H
@read:  jsr ReadBuff
        txa
        bne @end
        lda diskBlkBuf+1        ; its link: the next block
        sta r1H
        lda diskBlkBuf
        sta r1L
        jmp @entry
@done:  ldx #0
@end:   pla
        sta r3H
        pla
        sta r3L
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
; Destroys A, Y, r0-r2L, r4, r6 (left at the next free name's slot: the
; system fonts and drive E's names go on from there, sysdrive.s OvFTypes
; and module 123, rootmerge.s; until 2026-11-25 it was 3 bytes lower and
; they added the name's offset back).
; Own design (clean-room rewrite, 2026-11-20): the buffer cleared a
; name's slot at a time, names copied through DirName.
FindFTypes:
        php
        sei
        lda r6L                 ; r1 walks the buffer: r7H slots of 17
        sta r1L                 ; bytes cleared
        lda r6H
        sta r1H
        ldx r7H
        beq @first
@slot:  lda #0
        ldy #16
@zero:  sta (r1),y
        dey
        bpl @zero
        lda r1L
        clc
        adc #17
        sta r1L
        bcc @more
        inc r1H
@more:  dex
        bne @slot
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
        jsr DirName           ; (after ClassMatch: it uses r4)
        ldy #0
@name:  lda (r4),y
        cmp #$A0
        beq @nul
        sta (r6),y
        iny
        cpy #16
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
        ldy #OFF_GHDR_PTR + 1   ; its header block (own design, clean-room
        lda (r5),y              ; rewrite 2026-11-20)
        sta r1H
        dey
        lda (r5),y
        sta r1L
        jsr HeaderBuf
        jsr GetBlock
        txa
        bne @end
        ldy #$FF                ; the permanent name against r10, up to
@cmp:   iny                     ; r10's end
        lda (r10),y
        beq @yes
        cmp fileHeader + O_GHFNAME,y
        beq @cmp
        ldy #$FF                ; (not the class)
        rts
@yes:   ldy #0
@end:   rts
