; VLIR files: OpenRecordFile, CloseRecordFile, UpdateRecordFile,
; NextRecord, PreviousRecord, PointRecord, DeleteRecord, InsertRecord,
; AppendRecord, ReadRecord, WriteRecord. The index block lives in
; fileHeader while the file is open. Written from the HG2G2022
; descriptions; behaviour details (how usedRecords is counted, Y = the
; record's track after PointRecord, the BAM read once before the first
; change, fileSize kept in blocks with an 8-bit adjustment, an emptied
; record as 0/$FF) follow the reassembled GEOS 2.0 kernal, mist64/geos
; kernal/files/files10.s, read as behaviour reference only. Own code;
; checked with tests/conformance/vlir.py.

        .include "geos.inc"
        .include "kcalls.inc"

        .export OpenRecordFile, CloseRecordFile, UpdateRecordFile
        .export NextRecord, PreviousRecord, PointRecord, DeleteRecord
        .export InsertRecord, AppendRecord, ReadRecord, WriteRecord
        .import FindFile, ReadFile, WriteFile, FreeChain, CopyDate

MAX_RECORDS     = 127

        .segment "DATA"

indexTS:        .word 0         ; index block; track 0: no file open
dirTS:          .word 0         ; directory block with the entry
dirOffset:      .word 0         ; the entry in diskBlkBuf

        .segment "IOCODE"

; OpenRecordFile: r0 = name of a VLIR file (USR, structure VLIR). Index
; to fileHeader, usedRecords counted, curRecord 0 ($FF when empty).
; X = 0, FILE_NOT_FOUND or STRUCT_MISMAT. Destroys A, Y, r1, r4-r6.
OpenRecordFile:
        lda r0L
        sta r6L
        lda r0H
        sta r6H
        jsr FindFile
        txa
        bne Closed
        ldx #STRUCT_MISMAT
        ldy #0
        lda (r5),y
        and #$3F
        cmp #USR
        bne Closed
        ldy #OFF_GSTRUC_TYPE
        lda (r5),y
        cmp #VLIR
        bne Closed
        ldy #OFF_DE_TR_SC
        lda (r5),y
        sta indexTS
        iny
        lda (r5),y
        sta indexTS+1
        lda r1L
        sta dirTS
        lda r1H
        sta dirTS+1
        lda r5L
        sta dirOffset
        lda r5H
        sta dirOffset+1
        lda dirEntryBuf + OFF_SIZE
        sta fileSize
        lda dirEntryBuf + OFF_SIZE + 1
        sta fileSize+1
        jsr IndexBlock
        jsr GetBlock
        txa
        bne Closed
        sta usedRecords         ; records up to the first 0/0 entry
        ldy #2
@count: lda fileHeader,y
        ora fileHeader+1,y
        beq @first
        inc usedRecords
        iny
        iny
        bne @count
@first: ldy #0
        lda usedRecords
        bne @cur
        dey
@cur:   sty curRecord
        ldx #0
        stx fileWritten
        rts

; CloseRecordFile: UpdateRecordFile, then the file is closed. X = error.
CloseRecordFile:
        jsr UpdateRecordFile
Closed: lda #0
        sta indexTS
        rts

; UpdateRecordFile: after changes, the index block, the entry's date and
; size, and the BAM to disk. X = error. Destroys A, Y, r1, r4, r5.
UpdateRecordFile:
        ldx #0
        lda fileWritten
        beq @end
        jsr IndexBlock
        txa
        bne @end
        jsr PutBlock
        txa
        bne @end
        lda dirTS
        sta r1L
        lda dirTS+1
        sta r1H
        jsr ReadBuff
        txa
        bne @end
        lda dirOffset
        sta r5L
        lda dirOffset+1
        sta r5H
        jsr CopyDate
        ldy #OFF_SIZE
        lda fileSize
        sta (r5),y
        iny
        lda fileSize+1
        sta (r5),y
        jsr WriteBuff
        txa
        bne @end
        jsr PutDirHead
        lda #0
        sta fileWritten
@end:   rts

; IndexBlock: r1 = the index block, r4 = fileHeader; X = UNOPENED_VLIR
; when no file is open.
IndexBlock:
        ldx #UNOPENED_VLIR
        lda indexTS
        beq @end
        sta r1L
        lda indexTS+1
        sta r1H
        lda #<fileHeader
        sta r4L
        lda #>fileHeader
        sta r4H
        ldx #0
@end:   rts

; NextRecord / PreviousRecord / PointRecord (A = record): make it current.
; Returns A = curRecord, X = 0 or INV_RECORD, Y = the record's first
; track (0: empty), r1 = its first block.
NextRecord:
        lda curRecord
        clc
        adc #1
        jmp PointRecord
PreviousRecord:
        lda curRecord
        sec
        sbc #1
PointRecord:
        tax
        bmi @bad
        cmp usedRecords
        bcs @bad
        sta curRecord
        jsr RecordTS
        ldy r1L
        ldx #0
        beq @end
@bad:   ldx #INV_RECORD
@end:   lda curRecord
        rts

; RecordTS: r1 = the current record's first block (Y = index offset).
RecordTS:
        lda curRecord
        asl
        tay
        lda fileHeader+2,y
        sta r1L
        lda fileHeader+3,y
        sta r1H
        rts

; SetRecordTS: the current record's first block = r1.
SetRecordTS:
        lda curRecord
        asl
        tay
        lda r1L
        sta fileHeader+2,y
        lda r1H
        sta fileHeader+3,y
        rts

; Changing: the BAM is read once before the first change of an open file.
Changing:
        ldx #0
        lda fileWritten
        bne @end
        jsr GetDirHead
        txa
        bne @end
        lda #$FF
        sta fileWritten
@end:   rts

; DeleteRecord: removes the current record and frees its blocks; the next
; one becomes current (the previous one at the end). X = error.
DeleteRecord:
        ldx #INV_RECORD
        lda curRecord
        bmi @end
        jsr Changing
        txa
        bne @end
        jsr RecordTS
        lda curRecord           ; close the gap in the index
        asl
        tay
        lda #MAX_RECORDS - 1
        sec
        sbc curRecord
        asl
        tax
        beq @last
@move:  lda fileHeader+4,y
        sta fileHeader+2,y
        iny
        dex
        bne @move
@last:  stx fileHeader+$FE
        stx fileHeader+$FF
        dec usedRecords
        lda curRecord
        cmp usedRecords
        bcc @free
        dec curRecord
@free:  ldx #0
        lda r1L
        beq @end
        jsr FreeChain
        txa
        bne @end
        lda fileSize
        sec
        sbc r2L
        sta fileSize
        bcs @end
        dec fileSize+1
@end:   rts

; InsertRecord: a new empty record before the current one (which it
; becomes). AppendRecord: after the current one. X = error.
InsertRecord:
        ldx #INV_RECORD
        lda curRecord
        bmi InsEnd
        jsr Changing
        txa
        bne InsEnd
        lda curRecord
        jmp Open
AppendRecord:
        jsr Changing
        txa
        bne InsEnd
        lda curRecord
        clc
        adc #1
        jsr Open
        txa
        bne InsEnd
        lda r0L
        sta curRecord
InsEnd: rts

; Open: A = record number (r0L): an empty record (0, $FF) there, the rest
; moved up. X = 0, OUT_OF_RECORDS or INV_RECORD.
Open:   sta r0L
        ldx #OUT_OF_RECORDS
        lda usedRecords
        cmp #MAX_RECORDS
        bcs @end
        ldx #INV_RECORD
        lda r0L
        bmi @end
        ldy #$FE
        lda #MAX_RECORDS - 1
        sec
        sbc r0L
        asl
        tax
        beq @new
@move:  lda fileHeader-1,y
        sta fileHeader+1,y
        dey
        dex
        bne @move
@new:   txa
        sta fileHeader,y
        lda #$FF
        sta fileHeader+1,y
        inc usedRecords
@end:   rts

; ReadRecord: the current record into r7 (r2 = buffer size), as ReadFile.
; A = $FF when the record has data, 0 when empty. X = error.
ReadRecord:
        ldx #INV_RECORD
        lda curRecord
        bmi @end
        jsr RecordTS
        lda r1L
        tax
        beq @end
        jsr ReadFile
        lda #$FF
@end:   rts

; WriteRecord: r7 = data, r2 = bytes (0: the record becomes empty).
; Replaces the current record's chain. X = error.
WriteRecord:
        ldx #INV_RECORD
        lda curRecord
        bmi @end
        lda r2L
        pha
        lda r2H
        pha
        jsr Changing
        pla
        sta r2H
        pla
        sta r2L
        txa
        bne @end
        jsr RecordTS
        lda r1L
        bne @old
        ldx #0
        lda r2L
        ora r2H
        beq @end
        bne Chain
@old:   lda r2L                 ; free the old chain first
        pha
        lda r2H
        pha
        lda r7L
        pha
        lda r7H
        pha
        jsr FreeChain
        lda r2L
        sta r0L
        pla
        sta r7H
        pla
        sta r7L
        pla
        sta r2H
        pla
        sta r2L
        txa
        bne @end
        lda fileSize
        sec
        sbc r0L
        sta fileSize
        bcs @size
        dec fileSize+1
@size:  lda r2L
        ora r2H
        bne Chain
        ldy #$FF                ; empty record
        sty r1H
        iny
        sty r1L
        jmp SetRecordTS
@end:   rts

; Chain: r2 bytes from r7 into newly allocated blocks; they become the
; current record.
Chain:  jsr Table
        lda r7L
        pha
        lda r7H
        pha
        jsr BlkAlloc
        pla
        sta r7H
        pla
        sta r7L
        txa
        bne @end
        lda r2L
        pha
        jsr Table
        jsr WriteFile
        pla
        sta r2L
        txa
        bne @end
        lda fileTrScTab
        sta r1L
        lda fileTrScTab+1
        sta r1H
        jsr SetRecordTS
        lda fileSize
        clc
        adc r2L
        sta fileSize
        bcc @end
        inc fileSize+1
@end:   rts

Table:  lda #<fileTrScTab
        sta r6L
        lda #>fileTrScTab
        sta r6H
        rts
