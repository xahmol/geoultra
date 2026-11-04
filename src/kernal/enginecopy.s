; File engine: copying and moving on GEOS drives (docs/FILE_ENGINE.md
; "Copying"; engine.s has the module list): module 29 FE_COPY and FE_MOVE
; (the source, the order, a move in one folder as a rename), module 30
; the target and its checks, module 31 the blocks and the new directory
; entry. Own code.
;
; A copy goes block by block through diskBlkBuf: each source block read
; with the source drive selected, its target block taken with
; SetNextFree and written with the target drive selected. SetDevice only
; selects (disk.s), so the target's BAM stays in curDirHead throughout;
; it is written once, after the new entry. A copy that fails leaves no
; entry and no taken blocks (the blocks it wrote are still free; the
; dispatcher reads the BAM anew).

        .include "geos.inc"
        .include "hw.inc"
        .include "kcalls.inc"
        .include "engine.inc"

        .import OvlCall, SysRAMOp, folderT, folderS, FindFile

CBM_REL         = 4             ; CBM type (directory entry +0, bits 0-2)

        .segment "OVL29"
        .scope Mod29

        jmp OvCopy              ; entry 0
        jmp OvMove              ; entry 3

        .include "feresolve.inc"

Target: jsr OvlCall             ; (module 30: the target, checked)
        .byte 30, 0
Blocks: jsr OvlCall             ; (module 31: the blocks, the entry)
        .byte 31, 0
UTo:    jsr OvlCall             ; (module 42: onto the Ultimate)
        .byte 42, 0
UFrom:  jsr OvlCall             ; (module 43: the whole copy from it; a
        .byte 43, 0             ; stub: back to the function's caller)

; FE_COPY: r0 = a file, r1 = a folder or a new name, r2L = FC_* flags,
; r3 = a progress routine or 0 (called after each block with r4 = blocks
; done; C set: stop, FE_CANCELLED). The target's name: r1's last part,
; or the source's when r1 is a folder or a drive. Between a GEOS drive
; and the Ultimate (raw, docs/FILE_ENGINE.md "Copying"): modules 42-44.
OvCopy: lda #0
        beq Go
; FE_MOVE: as FE_COPY; in the same folder a rename, else a copy and the
; source deleted.
OvMove: lda #1
Go:     sta cMove
        lda #1                  ; (Ultimate paths taken)
        sta feUlt
        lsr
        sta cToU
        lda argR0
        sta r0L
        lda argR0+1
        sta r0H
        jsr Resolve
        txa
        bne @end
        lda feKind
        cmp #FE_P_ULTIMATE
        bne @geos
        jmp UFrom
@geos:  jsr Source
        bne @end
        jsr Target
        txa
        bne @end
        lda cToU
        beq @here
        jsr UTo
        jmp @done
@here:  lda cMove
        beq @copy
        lda cSame
        beq @copy
        lda #<feTmp             ; a move in one folder: a rename
        sta r0L
        lda #>feTmp
        sta r0H
        lda #<feName            ; (the source's name, from Target)
        sta r6L
        lda #>feName
        sta r6H
        jmp RenameFile
@copy:  lda #<curDirHead        ; room for all its blocks
        sta r5L
        lda #>curDirHead
        sta r5H
        jsr CalcBlksFree
        ldx #INSUFF_SPACE
        lda r4L
        cmp cEntry + OFF_SIZE
        lda r4H
        sbc cEntry + OFF_SIZE + 1
        bcc @end
        jsr Blocks
@done:  txa
        bne @end
        lda cMove
        beq @end
        jsr SrcPath             ; the source deleted
        bne @end
        lda #<feName
        sta r0L
        lda #>feName
        sta r0H
        jmp DeleteFile
@end:   rts

; Source: the caller's r0 to a file (not a folder; for a move not
; locked): its entry to cEntry, its drive, folder and entry's place to
; cSrc*, its name to feTmp. Z clear and X = the error when it fails.
Source: jsr SrcPath
        bne @end
        ldy #29
@entry: lda dirEntryBuf,y
        sta cEntry,y
        dey
        bpl @entry
        ldx feDrive
        stx cSrcDrv
        lda folderT-8,x
        sta cSrcFT
        lda folderS-8,x
        sta cSrcFS
        lda r1L
        sta cSrcET
        lda r1H
        sta cSrcES
        lda r5L
        sta cSrcEO
        ldx #FE_IS_FOLDER
        jsr IsDir
        bcc @err
        ldx #FE_NOT_SUPPORTED   ; REL: its side sectors are not copied
        lda cEntry
        and #$07
        cmp #CBM_REL
        beq @err
        ldx #WR_PR_ON
        lda cMove
        beq @name
        lda cEntry
        and #$40                ; locked
        bne @err
@name:  ldx #FE_NAME_MAX
@copy:  lda feName,x
        sta feTmp,x
        dex
        bpl @copy
        ldx #0
@end:   rts
@err:   txa
        rts

; SrcPath: the caller's r0 resolved and its file found (dirEntryBuf, r1,
; r5). Z clear and X = the error when it fails.
SrcPath:
        lda argR0
        sta r0L
        lda argR0+1
        sta r0H
        jsr Named
        bne Ret
        jsr FindName
        txa
Ret:    rts

; Named: r0 resolved to a name in a folder of a GEOS drive. Z clear and
; X = the error (FE_BAD_PATH for "/" or a drive) when not.
Named:  jsr Resolve
        txa
        bne Ret
        ldx #FE_BAD_PATH
        lda feName
        beq @no
        ldx #0
        rts
@no:    txa
        rts

        .endscope

        .segment "OVL30"
        .scope Mod30

        jmp OvTarget            ; entry 0

        .include "feresolve.inc"

; OvTarget: the caller's r1 resolved; its folder entered when it names
; one. The target's name in feTmp, the source's in feName (for a rename);
; cSame nonzero when it is the source's folder. An existing file of that
; name: FILE_EXISTS, or with FC_OVERWRITE deleted (not the source itself,
; not locked). On the Ultimate: cToU set, X = 0 (module 42 or 43 goes
; on). X = 0 or the error.
OvTarget:
        lda argR1
        sta r0L
        lda argR1+1
        sta r0H
        jsr Resolve
        txa
        bne @fail
        lda feKind              ; the Ultimate: cToU (X = 0)
        cmp #FE_P_ULTIMATE
        bne :+
        sta cToU
        rts
:       ldx #FE_BAD_PATH
        lda feKind              ; ("/": no drive)
        beq @fail
        lda feName
        beq @there              ; a drive: the source's name
        jsr FindName
        txa
        beq @found
        cpx #FILE_NOT_FOUND
        bne @fail
@new:   ldx #FE_NAME_MAX        ; a new name
@copy:  lda feName,x
        sta feTmp,x
        dex
        bpl @copy
        bmi @there
@found: jsr IsDir
        bcs @new
        jsr EnterName           ; a folder: into it, the source's name
        txa
        bne @fail
@there: lda feDrive
        sta cDstDrv
        jsr SameFolder          ; (destroys X)
        lda #0
        bcs :+
        lda #1
:       sta cSame
        jsr SrcName
        jmp Exists
@fail:  rts

; Exists: an existing target file feTmp (in the target folder, current)
; replaced when FC_OVERWRITE allows. X = 0 or the error (OvTarget's
; end).
Exists: lda #<feTmp
        sta r6L
        lda #>feTmp
        sta r6H
        jsr FindFile
        txa
        beq @exists
        cpx #FILE_NOT_FOUND
        bne @fail
        ldx #0                  ; free
        rts
@exists:
        ldx #FE_IS_FOLDER
        jsr IsDir
        bcc @fail
        ldx #FILE_EXISTS
        lda cSame               ; the source itself
        beq @other
        lda r1L
        cmp cSrcET
        bne @other
        lda r1H
        cmp cSrcES
        bne @other
        lda r5L
        cmp cSrcEO
        beq @fail
@other: lda argR2
        and #FC_OVERWRITE
        beq @fail
        ldx #WR_PR_ON
        lda dirEntryBuf
        and #$40                ; locked
        bne @fail
        lda #<feTmp
        sta r0L
        lda #>feTmp
        sta r0H
        jmp DeleteFile
@fail:  rts

; SameFolder: C clear when the target (cDstDrv, its current folder) is
; the source's folder. Destroys A, X.
SameFolder:
        ldx cDstDrv
        cpx cSrcDrv
        bne @no
        lda folderT-8,x
        cmp cSrcFT
        bne @no
        lda folderS-8,x
        cmp cSrcFS
        bne @no
        clc
        rts
@no:    sec
        rts

; SrcName: the source's name from cEntry ($A0-padded) to feName,
; zero-ended. Destroys A, X.
SrcName:
        ldx #0
@ch:    lda cEntry + 3,x
        cmp #$A0
        beq @end
        sta feName,x
        inx
        cpx #FE_NAME_MAX
        bne @ch
@end:   lda #0
        sta feName,x
        rts

        .endscope

        .segment "OVL31"
        .scope Mod31

        jmp OvBlocks            ; entry 0

; OvBlocks: the file in cEntry (on cSrcDrv) copied to the target drive
; (current, its BAM in curDirHead): the header block, then the data (a
; chain, or each VLIR record's chain and the index, kept in fileHeader
; meanwhile); then the entry, named feTmp, and the BAM. X = 0 or an
; error.
OvBlocks:
        lda #0
        sta cLastT
        sta cDone
        sta cDone+1
        ldy #OFF_GHDR_PTR       ; the header (a one-block chain); none: a
        lda cEntry,y            ; CBM file, one chain
        beq @seq
        jsr ChainY
        bne @end
        lda cEntry + OFF_GSTRUC_TYPE
        cmp #VLIR
        beq @vlir
@seq:   ldy #OFF_DE_TR_SC
        jsr ChainY
        bne @end
        beq Entry
@vlir:  jsr Source              ; the index, to fileHeader
        lda cEntry + OFF_DE_TR_SC
        sta r1L
        lda cEntry + OFF_DE_TR_SC + 1
        sta r1H
        jsr IndexRegs
        jsr GetBlock
        txa
        bne @end
        lda #2
        sta cRec
@rec:   ldy cRec                ; each record that has a chain
        lda fileHeader,y
        beq @skip
        sta cNextT
        lda fileHeader+1,y
        sta cNextS
        jsr Chain
        bne @end
        ldy cRec
        lda cCurT               ; (Chain: the first block in cCur)
        sta fileHeader,y
        lda cCurS
        sta fileHeader+1,y
@skip:  inc cRec
        inc cRec
        bne @rec
        jsr Alloc               ; the index itself
        bne @end
        lda cLastT
        sta cEntry + OFF_DE_TR_SC
        sta r1L
        lda cLastS
        sta cEntry + OFF_DE_TR_SC + 1
        sta r1H
        jsr IndexRegs
        jsr PutBlock
        txa
        bne @end
        jsr Progress            ; (the index counts as a block done)
        bcc Entry
        ldx #FE_CANCELLED
@end:   rts


        .include "feentry.inc"  ; (Entry: right after OvBlocks's branches)

; ChainY: the chain starting at cEntry+Y copied; its first target block
; back to cEntry+Y. Z set when it worked, else X = the error.
ChainY: lda cEntry,y
        sta cNextT
        lda cEntry+1,y
        sta cNextS
        tya
        pha
        jsr Chain
        pla
        tay
        txa
        bne @end
        lda cCurT
        sta cEntry,y
        lda cCurS
        sta cEntry+1,y
        txa
@end:   rts

; Chain: the chain from cNextT/S copied, block by block; cCur its first
; target block at the end. Z set when it worked, else X = the error.
Chain:  jsr Alloc               ; the first target block
        bne @end
        lda cLastT
        sta cCurT
        pha
        lda cLastS
        sta cCurS
        pha
        jsr @blocks
        pla
        sta cCurS
        pla
        sta cCurT
        txa
@end:   rts
@blocks:
        jsr Source              ; a source block
        lda cNextT
        sta r1L
        lda cNextS
        sta r1H
        jsr ReadBuff
        txa
        bne @ret
        lda diskBlkBuf          ; its link: the next to read
        sta cNextT
        lda diskBlkBuf+1
        sta cNextS
        lda cNextT
        beq @write              ; (the last: its link stays)
        jsr Alloc               ; else linked to a new target block
        bne @ret
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
        bne @ret
        jsr Progress
        bcs @cancel
        lda cNextT
        beq @ret                ; (X = 0)
        lda diskBlkBuf
        sta cCurT
        lda diskBlkBuf+1
        sta cCurS
        jmp @blocks
@cancel:
        ldx #FE_CANCELLED
@ret:   rts

; Source: the source's drive selected.
Source: lda cSrcDrv
        jmp SetDevice

; IndexRegs: r4 = fileHeader (the VLIR index).
IndexRegs:
        lda #<fileHeader
        sta r4L
        lda #>fileHeader
        sta r4H
        rts

        .include "fename.inc"
        .include "feblock.inc"
        .include "feprog.inc"

        .endscope
