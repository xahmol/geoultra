; File engine: streams on GEOS drives (docs/design/FILE_ENGINE.md "Functions";
; engine.s has the module list): module 32 FE_OPEN, module 33 a new
; file for it, module 34 FE_READ, module 35 FE_WRITE (FE_CLOSE is in
; module 22). Shared: festream.inc. On the Ultimate the three go on in
; modules 61 and 62 (enginestreamu.s). Own code.
;
; A stream is one chain: a CBM file, or a sequential GEOS file's data
; (not its header); VLIR files are refused (STRUCT_MISMAT). A file made
; by FE_OPEN is a CBM SEQ file with today's date. FE_WRITE writes its
; blocks, the BAM and the entry's block count before it returns, so the
; file is whole after every call; FE_CLOSE only frees the handle.
; Bytes past a block's end: H_OFF = 0.

        .include "geos.inc"
        .include "hw.inc"
        .include "kcalls.inc"
        .include "engine.inc"

        .import OvlCall, SysRAMOp, folderT, folderS, FindFile

CBM_SEQ         = $81           ; a closed SEQ file

        .segment "OVL32"
        .scope Mod32

        jmp OvOpen              ; entry 0

        .include "fereu.inc"
        .include "fehandle.inc"
        .include "feresolve.inc"

New:    jsr OvlCall             ; (module 33: a new file)
        .byte 33, 0
UOpen:  jsr OvlCall             ; (module 61: on the Ultimate; a stub:
        .byte 61, 0             ; back to the function's caller)
Drop:   jsr OvlCall             ; (module 51: a deleted file's record)
        .byte 51, 3
HMark:  jsr OvlCall             ; (module 81: the handle's drive byte)
        .byte 81, 21

; FE_OPEN: r0 = a file, r2L = FO_READ, FO_WRITE (a new file; an existing
; one is replaced) or FO_APPEND (at its end; made when not there).
; A = the handle.
OvOpen: jsr NewHandle
        bcc :+
        rts
:       lda argR0
        sta r0L
        lda argR0+1
        sta r0H
        lda #1                  ; (Ultimate paths too: module 61)
        sta feUlt
        jsr Resolve
        txa
        beq :+
        rts
:       lda feKind
        cmp #FE_P_ULTIMATE
        bne :+
        jmp UOpen
:       ldx #FE_BAD_PATH        ; "/" or a drive
        lda feName
        beq @ret
        ldx feDrive             ; the folder holding it
        txa
        jsr HMark               ; (drive E or a disk image shown there:
        sta feH + H_DRIVE       ; marked, HDrive)
        lda folderT-8,x
        sta feH + H_FOLDT
        lda folderS-8,x
        sta feH + H_FOLDS
        jsr FindName
        txa
        beq @found
        cpx #FILE_NOT_FOUND
        bne @ret
        lda argR2
        beq @ret                ; (reading: not found)
        bne @made
@found: ldx #FE_IS_FOLDER
        jsr IsDir
        bcc @ret
        ldx #STRUCT_MISMAT      ; a VLIR file: no stream
        lda dirEntryBuf + OFF_GHDR_PTR
        beq @seq
        lda dirEntryBuf + OFF_GSTRUC_TYPE
        cmp #VLIR
        beq @ret
@seq:   lda argR2
        beq Read
        jsr Locked              ; (task.s: write-protected, or open in
                                ; another task)
        bne @ret
        lda argR2
        cmp #FO_APPEND
        beq Append
        lda r1L                 ; FO_WRITE: the old one deleted (its key:
        sta lnKeyT              ; its long name's record dropped after)
        lda r1H
        sta lnKeyS
        lda r5L
        sta lnKeyO
        lda #<feShort
        sta r0L
        lda #>feShort
        sta r0H
        jsr DeleteFile
        txa
        bne @ret
        jsr Drop
@made:  jsr New
        txa
        beq Write
@ret:   rts

; Read: from the first block's first byte.
Read:   lda dirEntryBuf + OFF_DE_TR_SC
        sta feH + H_BLKT
        lda dirEntryBuf + OFF_DE_TR_SC + 1
        sta feH + H_BLKS
        lda #2
        sta feH + H_OFF
        lda #HT_READ
        jmp Save

; Append: after the last byte of the last block. The entry's place and
; size from FindFile (r1, r5, dirEntryBuf).
Append: lda r1L
        sta feH + H_DIRT
        lda r1H
        sta feH + H_DIRS
        lda r5L
        sta feH + H_DIRO
        lda dirEntryBuf + OFF_SIZE
        sta feH + H_SIZE
        lda dirEntryBuf + OFF_SIZE + 1
        sta feH + H_SIZE + 1
        lda dirEntryBuf + OFF_DE_TR_SC
        sta r1L
        lda dirEntryBuf + OFF_DE_TR_SC + 1
        sta r1H
@walk:  jsr ReadBuff
        txa
        bne @ret
        lda diskBlkBuf
        beq @last
        sta r1L
        lda diskBlkBuf+1
        sta r1H
        jmp @walk
@last:  ldx diskBlkBuf+1        ; (255: full, H_OFF 0)
        inx
        stx feH + H_OFF
        jmp Write
@ret:   rts

Write:  lda #HT_WRITE
Save:   sta feH + H_TYPE
        ldy #REU_STASH
        jsr HandleOp
        lda feHandle
        ldx #0
        rts


; Locked (task.s, module 98): X = WR_PR_ON (dirEntryBuf's file
; write-protected), FE_IN_TASK (open in another task) or 0; Z as X.
; (A stub: OvlCall returns to its caller.)
Locked: jsr OvlCall
        .byte 98, 12

        .endscope

        .segment "OVL33"
        .scope Mod33

        jmp OvCreate            ; entry 0

        .include "fename.inc"
        .include "felen.inc"

Short:  jsr OvlCall             ; (module 50: a short name made)
        .byte 50, 0
LnSet:  jsr OvlCall             ; (module 49: its long name's record)
        .byte 49, 0

; OvCreate: a new CBM SEQ file, feName (a long name: with a short name
; made and its record), of one empty block, in the current folder; its
; entry and the BAM written. The handle's H_BLK*,
; H_OFF, H_DIR*, H_SIZE set. X = 0 or an error.
OvCreate:
        ldx #FE_LONG_MAX        ; its name: feName; a long one gets a
@name:  lda feName,x            ; short name made (module 50; a short one:
        sta feTmp,x             ; feShort from the walk)
        dex
        bpl @name
        jsr IsLongT
        beq @block
        jsr Short
        txa
        beq @block
        rts
@block: lda #1                  ; one byte: one block
        sta r2L
        lda #0
        sta r2H
        lda #<dirEntryBuf
        sta r6L
        lda #>dirEntryBuf
        sta r6H
        jsr BlkAlloc
        txa
        bne Fail
        tay                     ; the block: empty (last byte at 1)
@clear: sta diskBlkBuf,y
        iny
        bne @clear
        lda #1
        sta diskBlkBuf+1
        lda r3L
        sta feH + H_BLKT
        sta r1L
        lda r3H
        sta feH + H_BLKS
        sta r1H
        jsr WriteBuff
        txa
        bne Fail
        sta r10L                ; a free entry in the folder
        jsr GetFreeDirBlk       ; (diskBlkBuf, r1; Y its offset)
        txa
        bne Fail
        lda r1L                 ; the entry's place
        sta feH + H_DIRT
        lda r1H
        sta feH + H_DIRS
        sty feH + H_DIRO
        jsr NewEntry
        jsr WriteBuff
        txa
        bne Fail
        jsr PutDirHead
        txa
        bne Fail
        jsr IsLongT             ; a long name: its record (best effort)
        beq @size
        lda feH + H_DIRT
        sta lnKeyT
        lda feH + H_DIRS
        sta lnKeyS
        lda feH + H_DIRO
        sta lnKeyO
        jsr LnSet
@size:  lda #1
        sta feH + H_SIZE
        lda #0
        sta feH + H_SIZE + 1
        lda #2
        sta feH + H_OFF
        ldx #0
Fail:   rts

; NewEntry: the entry at H_DIRO in diskBlkBuf: SEQ, the first block, the
; name, no GEOS fields, today's date, one block.
NewEntry:
        ldy feH + H_DIRO
        ldx #30
        lda #0
@zero:  sta diskBlkBuf,y
        iny
        dex
        bne @zero
        ldy feH + H_DIRO
        lda #CBM_SEQ
        sta diskBlkBuf,y
        lda feH + H_BLKT
        sta diskBlkBuf + OFF_DE_TR_SC,y
        lda feH + H_BLKS
        sta diskBlkBuf + OFF_DE_TR_SC + 1,y
        lda #1
        sta diskBlkBuf + OFF_SIZE,y
@date:  lda year,x              ; (X = 0 from @zero)
        sta diskBlkBuf + OFF_DATE,y
        iny
        inx
        cpx #5
        bne @date
        lda feH + H_DIRO        ; the name: feShort
        clc
        adc #OFF_FNAME
        tay
        jmp PutName

OFF_FNAME       = 3
OFF_DATE        = 23

        .endscope

        .segment "OVL34"
        .scope Mod34

        jmp OvRead              ; entry 0

        .include "fereu.inc"
        .include "festream.inc"
URead:  jsr OvlCall             ; (module 62: an Ultimate stream; a stub)
        .byte 62, 0

; FE_READ: Y = a handle (FO_READ), r1 = a buffer, r2 = bytes wanted.
; r2 = bytes read (fewer: the end of the file).
OvRead: lda #HT_READ
        jsr Stream
        beq :+
        lda feH + H_TYPE        ; an Ultimate stream: module 62 (it checks
        cmp #HT_UREAD           ; the handle itself)
        bne @ret
        jmp URead
:
        jsr ReadCur
        bne @ret
@loop:  lda sLeft
        ora sLeft+1
        beq @done
        ldx feH + H_OFF
        beq @next               ; past a full block
        lda diskBlkBuf
        bne @byte               ; not the last block
        lda diskBlkBuf+1        ; the last: up to its last byte
        cmp feH + H_OFF
        bcc @done
@byte:  lda sPtr                ; (the address into the code at every
        sta @st+1               ; byte: overlay.s, as in FE_WRITE)
        lda sPtr+1
        sta @st+2
        lda diskBlkBuf,x
@st:    sta $FFFF
        inc sPtr
        bne :+
        inc sPtr+1
:       inc feH + H_OFF
        jsr Count
        inc sGot
        bne :+
        inc sGot+1
:       jmp @loop
@next:  lda diskBlkBuf          ; the next block, if any
        beq @done
        sta feH + H_BLKT
        lda diskBlkBuf+1
        sta feH + H_BLKS
        lda #2
        sta feH + H_OFF
        jsr ReadCur
        beq @loop
@ret:   rts
@done:  lda sGot
        sta argR2
        lda sGot+1
        sta argR2+1
        jmp Keep

        .endscope

        .segment "OVL35"
        .scope Mod35

        jmp OvWrite             ; entry 0

        .include "fereu.inc"
        .include "festream.inc"
UWrite: jsr OvlCall             ; (module 63: an Ultimate stream; a stub)
        .byte 63, 0

; FE_WRITE: Y = a handle (FO_WRITE, FO_APPEND), r1 = the bytes, r2 their
; number.
OvWrite:
        lda #HT_WRITE
        jsr Stream
        beq :+
        lda feH + H_TYPE        ; an Ultimate stream: module 63 (it checks
        cmp #HT_UWRITE          ; the handle itself)
        bne @no
        jmp UWrite
@no:    rts
:
        lda feH + H_DRIVE       ; its folder's BAM
        jsr HDrive
        ldx curDrive
        lda feH + H_FOLDT
        sta folderT-8,x
        lda feH + H_FOLDS
        sta folderS-8,x
        jsr GetDirHead
        txa
        bne @ret
        sta sNew
        jsr ReadCur
        bne @ret
@loop:  lda sLeft
        ora sLeft+1
        beq @last
        ldx feH + H_OFF
        bne @byte
        jsr NewBlock            ; the block is full: a new one
        bne @end
        ldx #2
@byte:  lda sPtr                ; (the address into the code at every
        sta @ld+1               ; byte: a nested overlay call, as a native
        lda sPtr+1              ; drive's BAM work makes, fetches this
        sta @ld+2               ; module anew; overlay.s)
@ld:    lda $FFFF
        sta diskBlkBuf,x
        inc sPtr
        bne :+
        inc sPtr+1
:       inc feH + H_OFF
        jsr Count
        jmp @loop
@last:  lda #0                  ; the last block: its last byte
        sta diskBlkBuf
        ldx feH + H_OFF
        dex
        stx diskBlkBuf+1
        jsr WriteCur
@end:   stx sGot                ; (the first error counts)
        lda sNew
        beq @keep
        jsr PutDirHead          ; blocks added: the BAM and the entry
        txa
        bne @bam
        jsr Size
@bam:   lda sGot
        bne @keep
        stx sGot
@keep:  ldx sGot
        bne @ret
        jmp Keep
@ret:   rts

; NewBlock: the next block taken and linked from the current one, which
; is written; the new one empty in diskBlkBuf and current. Z set when it
; worked, else X = the error.
NewBlock:
        lda feH + H_BLKT
        sta r3L
        lda feH + H_BLKS
        sta r3H
        jsr SetNextFree
        txa
        bne @end
        lda r3L
        sta diskBlkBuf
        lda r3H
        sta diskBlkBuf+1
        jsr WriteCur
        bne @end
        lda diskBlkBuf
        sta feH + H_BLKT
        lda diskBlkBuf+1
        sta feH + H_BLKS
        lda #0
        tay
@clear: sta diskBlkBuf,y
        iny
        bne @clear
        lda #2
        sta feH + H_OFF
        inc feH + H_SIZE
        bne :+
        inc feH + H_SIZE + 1
:       sta sNew
        ldx #0
@end:   rts

; Size: the entry's block count from H_SIZE (its directory block read,
; changed, written). X = 0 or an error.
Size:   lda feH + H_DIRT
        sta r1L
        lda feH + H_DIRS
        sta r1H
        jsr ReadBuff
        txa
        bne @end
        lda feH + H_DIRO
        clc
        adc #OFF_SIZE
        tay
        lda feH + H_SIZE
        sta diskBlkBuf,y
        lda feH + H_SIZE + 1
        sta diskBlkBuf+1,y
        jmp WriteBuff
@end:   rts

        .endscope
