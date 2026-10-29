; File system, writing: WriteFile, SaveFile, SetGDirEntry, BldGDirEntry,
; FreeFile, DeleteFile, FastDelFile, RenameFile. Written from the HG2G2022
; descriptions; behaviour details (SaveFile's block count with the header
; and VLIR index blocks, the cleared info byte, the empty index block,
; the date copied only to the directory block, FreeFile's VLIR record
; chains via fileHeader) follow the reassembled GEOS 2.0 kernal,
; mist64/geos kernal/files/files1b.s, files8.s, files9.s, files10.s, read
; as behaviour reference only. Own code; checked with
; tests/conformance/filewrite.py. GEOS 2.0 writes every file twice (then
; with verify); an REU image needs one pass.

        .include "geos.inc"
        .include "kcalls.inc"

        .export WriteFile, SaveFile, SetGDirEntry, BldGDirEntry, FreeFile
        .export DeleteFile, FastDelFile, RenameFile, FreeChain, CopyDate
        .import FindFile, saveFlag

OFF_FNAME       = 3

        .segment "CODE"

; WriteFile: r6 = track/sector table (ended by track 0), r7 = the data.
; Every block gets the next table entry as its link and 254 bytes from
; r7. X = error. r6 ends at the closing entry, r7 past the data.
; Destroys A, Y, r1, r4.
WriteFile:
        jsr BufPtr
@block: ldy #0
        lda (r6),y
        beq @done
        sta r1L
        iny
        lda (r6),y
        sta r1H
        jsr Add2r6
        ldy #0                  ; link = the next entry
        lda (r6),y
        sta diskBlkBuf
        iny
        lda (r6),y
        sta diskBlkBuf+1
        ldy #254
@copy:  dey
        lda (r7),y
        sta diskBlkBuf+2,y
        tya
        bne @copy
        jsr PutBlock
        txa
        bne @end
        clc
        lda r7L
        adc #254
        sta r7L
        bcc @block
        inc r7H
        bne @block
@done:  tax
@end:   rts

Add2r6: clc
        lda r6L
        adc #2
        sta r6L
        bcc @end
        inc r6H
@end:   rts

BufPtr: lda #<diskBlkBuf
        sta r4L
        lda #>diskBlkBuf
        sta r4H
        rts

; SaveFile: r9 = file header (its first word points to the name), r10L =
; directory page to start at. Allocates the header block, a VLIR index
; block and the data (header load to end address), writes the directory
; entry, BAM, header and data. X = error. Destroys A, Y, r0-r10.
SaveFile:
        ldy #0
@hdr:   lda (r9),y
        sta fileHeader,y
        iny
        bne @hdr
        jsr GetDirHead
        txa
        bne @end
        sec                     ; bytes = end - start, + a block for the
        lda fileHeader + O_GHEND_ADDR       ; header (and the VLIR index)
        sbc fileHeader + O_GHST_ADDR
        sta r2L
        lda fileHeader + O_GHEND_ADDR + 1
        sbc fileHeader + O_GHST_ADDR + 1
        sta r2H
        jsr Add254
        lda fileHeader + O_GHSTR_TYPE
        cmp #VLIR
        bne @alloc
        jsr Add254
@alloc: jsr TabPtr
        lda #$80                ; for the 1581 driver: called from SaveFile
        sta saveFlag
        jsr BlkAlloc
        txa
        bne @end
        jsr TabPtr
        jsr SetGDirEntry
        txa
        bne @end
        jsr PutDirHead
        txa
        bne @end
        sta fileHeader + O_GHINFO_TXT
        lda dirEntryBuf + OFF_GHDR_PTR
        sta r1L
        lda dirEntryBuf + OFF_GHDR_PTR + 1
        sta r1H
        lda #<fileHeader
        sta r4L
        lda #>fileHeader
        sta r4H
        jsr PutBlock
        txa
        bne @end
        lda dirEntryBuf + OFF_GSTRUC_TYPE
        cmp #VLIR
        bne @data
        lda dirEntryBuf + OFF_DE_TR_SC     ; an empty index block
        sta r1L
        lda dirEntryBuf + OFF_DE_TR_SC + 1
        sta r1H
        jsr ClearWrite
        txa
        bne @end
@data:  lda fileHeader + O_GHST_ADDR
        sta r7L
        lda fileHeader + O_GHST_ADDR + 1
        sta r7H
        jmp WriteFile
@end:   rts

Add254: clc
        lda r2L
        adc #254
        sta r2L
        bcc @end
        inc r2H
@end:   rts

TabPtr: lda #<fileTrScTab
        sta r6L
        lda #>fileTrScTab
        sta r6H
        rts

; ClearWrite: an empty block (link 0, $FF) from diskBlkBuf to r1.
ClearWrite:
        lda #0
        tay
@clear: sta diskBlkBuf,y
        iny
        bne @clear
        dey
        sty diskBlkBuf+1
        jmp WriteBuff

; SetGDirEntry: BldGDirEntry, then the entry (with today's date) into the
; first free directory slot from page r10L, written to disk. X = error;
; r5 = the entry in diskBlkBuf.
SetGDirEntry:
        jsr BldGDirEntry
        jsr GetFreeDirBlk
        txa
        bne @end
        tya
        clc
        adc #<diskBlkBuf
        sta r5L
        lda #>diskBlkBuf
        adc #0
        sta r5H
        ldy #29
@copy:  lda dirEntryBuf,y
        sta (r5),y
        dey
        bpl @copy
        jsr CopyDate
        jmp WriteBuff
@end:   rts

; CopyDate: date and time (year, month, day, hour, minute) into the
; directory entry at r5.
CopyDate:
        ldy #23
@date:  lda year - 23,y
        sta (r5),y
        iny
        cpy #28
        bne @date
        rts

; BldGDirEntry: r9 = file header, r6 = its blocks (header, VLIR index,
; data), r2 = size in blocks. Builds the entry in dirEntryBuf (no date);
; fileHeader gets the header block's link (0, $FF). r6 moves past the
; entries used. Destroys A, Y, r3.
BldGDirEntry:
        ldy #29
        lda #0
@clear: sta dirEntryBuf,y
        dey
        bpl @clear
        ldy #0                  ; r3 = the name
        lda (r9),y
        sta r3L
        iny
        lda (r9),y
        sta r3H
        ldy #0
@name:  lda (r3),y
        beq @pad
        sta dirEntryBuf + OFF_FNAME,y
        iny
        cpy #16
        bne @name
        beq @type
@pad:   lda #$A0
@fill:  sta dirEntryBuf + OFF_FNAME,y
        iny
        cpy #16
        bne @fill
@type:  ldy #O_GHCMDR_TYPE
        lda (r9),y
        sta dirEntryBuf
        ldy #O_GHSTR_TYPE
        lda (r9),y
        sta dirEntryBuf + OFF_GSTRUC_TYPE
        ldy #0
        sty fileHeader
        dey
        sty fileHeader+1
        ldy #0                  ; header block
        lda (r6),y
        sta dirEntryBuf + OFF_GHDR_PTR
        iny
        lda (r6),y
        sta dirEntryBuf + OFF_GHDR_PTR + 1
        jsr Add2r6
        ldy #0                  ; data (or index) block
        lda (r6),y
        sta dirEntryBuf + OFF_DE_TR_SC
        iny
        lda (r6),y
        sta dirEntryBuf + OFF_DE_TR_SC + 1
        lda dirEntryBuf + OFF_GSTRUC_TYPE
        cmp #VLIR
        bne @geos
        jsr Add2r6
@geos:  ldy #O_GHGEOS_TYPE
        lda (r9),y
        sta dirEntryBuf + OFF_GFILE_TYPE
        lda r2L
        sta dirEntryBuf + 28
        lda r2H
        sta dirEntryBuf + 29
        rts

; DeleteFile: r0 = name. Removes the entry and frees the file's blocks.
; X = error. Destroys A, Y, r1-r9.
DeleteFile:
        jsr FindRemove
        txa
        bne FreeEnd
        lda #<dirEntryBuf
        sta r9L
        lda #>dirEntryBuf
        sta r9H

; FreeFile: r9 = directory entry. Frees header, data and (VLIR) record
; chains in the BAM and writes it. X = error. Destroys A, Y, r1, r2,
; r4-r8.
FreeFile:
        php
        sei
        jsr GetDirHead
        txa
        bne @end
        ldy #OFF_GHDR_PTR
        lda (r9),y
        beq @data
        sta r1L
        iny
        lda (r9),y
        sta r1H
        jsr FreeChain
        txa
        bne @end
@data:  ldy #OFF_DE_TR_SC
        lda (r9),y
        sta r1L
        iny
        lda (r9),y
        sta r1H
        jsr FreeChain
        txa
        bne @end
        ldy #OFF_GSTRUC_TYPE
        lda (r9),y
        cmp #VLIR
        bne @bam
        ldy #0                  ; the index block (last read) to fileHeader
@index: lda diskBlkBuf,y
        sta fileHeader,y
        iny
        bne @index
        ldy #2
@record:
        lda fileHeader,y
        sta r1L
        iny
        lda fileHeader,y
        sta r1H
        iny
        lda r1L
        beq @more
        tya
        pha
        jsr FreeChain
        pla
        tay
        txa
        bne @end
@more:  tya
        bne @record
@bam:   jsr PutDirHead
@end:   plp
FreeEnd:
        rts

; FreeChain: frees the chain from r1 in the BAM. X = error; r2 = blocks.
FreeChain:
        lda r1L
        sta r6L
        lda r1H
        sta r6H
        lda #0
        sta r2L
        sta r2H
@block: jsr FreeBlock
        txa
        bne @end
        inc r2L
        bne @read
        inc r2H
@read:  lda r6L
        sta r1L
        lda r6H
        sta r1H
        jsr ReadBuff
        txa
        bne @end
        lda diskBlkBuf
        beq @end
        sta r6L
        lda diskBlkBuf+1
        sta r6H
        jmp @block
@end:   rts

; FindRemove: r0 = name. Finds the file and clears its entry on disk.
FindRemove:
        lda r0L
        sta r6L
        lda r0H
        sta r6H
        jsr FindFile
        txa
        bne @end
        tay
        sta (r5),y
        jsr WriteBuff
@end:   rts

; FastDelFile: r0 = name, r3 = its track/sector table. Removes the entry
; and frees the listed blocks. X = error. Destroys A, Y, r1, r3-r8.
FastDelFile:
        lda r3L
        pha
        lda r3H
        pha
        jsr FindRemove
        pla
        sta r3H
        pla
        sta r3L
        txa
        bne @end
        lda r3L
        pha
        lda r3H
        pha
        jsr GetDirHead
        pla
        sta r3H
        pla
        sta r3L
@block: ldy #0
        lda (r3),y
        beq @bam
        sta r6L
        iny
        lda (r3),y
        sta r6H
        jsr FreeBlock
        txa
        bne @end
        clc
        lda r3L
        adc #2
        sta r3L
        bcc @block
        inc r3H
        bne @block
@bam:   jmp PutDirHead
@end:   rts

; RenameFile: r6 = old name, r0 = new name (at most 16 characters).
; X = error. Destroys A, Y, r4-r6.
RenameFile:
        lda r0L
        pha
        lda r0H
        pha
        jsr FindFile
        pla
        sta r0H
        pla
        sta r0L
        txa
        bne @end
        clc
        lda r5L
        adc #OFF_FNAME
        sta r5L
        bcc @copy
        inc r5H
@copy:  ldy #0
@name:  lda (r0),y
        beq @pad
        sta (r5),y
        iny
        cpy #16
        bcc @name
        bcs @write
@pad:   lda #$A0
@fill:  sta (r5),y
        iny
        cpy #16
        bcc @fill
@write: jmp WriteBuff
@end:   rts
