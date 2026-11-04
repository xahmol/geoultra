; File engine: looking at files (docs/FILE_ENGINE.md "Functions"; engine.s
; has the module list): module 25 FE_STAT and FE_DF, module 26
; FE_OPENDIR, module 28 FE_READDIR (FE_CLOSE is in module 22). Own code.

        .include "geos.inc"
        .include "hw.inc"
        .include "kcalls.inc"
        .include "engine.inc"

        .import OvlCall, SysRAMOp, folderT, folderS

        .segment "OVL25"
        .scope Mod25

        jmp OvStat              ; entry 0
        jmp OvDf                ; entry 3

        .include "feresolve.inc"
        .include "feinfo.inc"

; FE_STAT: r0 = a path, r1 = an info block. A GEOS file's header is left
; in fileHeader.
OvStat: jsr Path
        bne @end
        lda feKind              ; "/": the root
        beq @kind
        lda #FE_K_DRIVE         ; "/a": the drive
        ldx feName
        beq @kind
        jsr FindName
        txa
        bne @end
        lda #<dirEntryBuf
        sta r5L
        sta r9L
        lda #>dirEntryBuf
        sta r5H
        sta r9H
        jsr FillInfo
        jsr PutInfo
        lda feInfo + FI_KIND
        cmp #FE_K_GEOS
        bne @end
        jmp GetFHdrInfo         ; (r9: the entry; X its error)
@kind:  jsr InfoKind
        jmp PutInfo
@end:   rts

; FE_DF: r0 = a path on a GEOS drive (a folder: a 1581 partition counts
; on its own): r1 = blocks free, r2 = blocks in all.
OvDf:   jsr Path
        bne @end
        ldx #FE_NOT_SUPPORTED
        lda feKind
        cmp #FE_P_GEOS
        bne @end
        lda feName
        beq @here
        jsr EnterName
        txa
        bne @end
@here:  lda #<curDirHead
        sta r5L
        lda #>curDirHead
        sta r5H
        jsr CalcBlksFree
        lda r4L
        sta argR1
        lda r4H
        sta argR1+1
        lda r3L
        sta argR2
        lda r3H
        sta argR2+1
        ldx #0
@end:   rts

; Path: the path at the caller's r0 resolved; Z clear and X = the error
; when it fails.
Path:   lda argR0
        sta r0L
        lda argR0+1
        sta r0H
        jsr Resolve
        txa
        rts

        .endscope

        .segment "OVL26"
        .scope Mod26

        jmp OvOpenDir           ; entry 0

        .include "fereu.inc"
        .include "feresolve.inc"

; FE_OPENDIR: r0 = a folder, or a pattern ("*" any run of characters,
; "?" one) or one name in a folder. A = the handle. "/": the drives.
OvOpenDir:
        jsr NewHandle
        bcc :+
        rts
:
        lda argR0
        sta r0L
        lda argR0+1
        sta r0H
        jsr Resolve
        txa
        bne @end
        lda feKind
        bne @geos
        sta feH + H_BLKT        ; "/" (FE_P_ROOT): the drives from slot 0
        lda #HT_ROOT
        bne @save
@geos:  lda feName
        beq @all
        jsr Wild
        bcc @pat
        jsr FindName            ; one name: a folder is listed whole
        txa
        bne @end
        jsr IsDir
        bcs @pat
        jsr EnterName
        txa
        bne @end
@all:   lda #'*'
        sta feName
        lda #0
        sta feName+1
@pat:   ldx #FE_NAME_MAX
@copy:  lda feName,x
        sta feH + H_PAT,x
        dex
        bpl @copy
        lda feDrive
        sta feH + H_DRIVE
        tax
        lda folderT-8,x
        sta feH + H_FOLDT
        lda folderS-8,x
        sta feH + H_FOLDS
        jsr Get1stDirEntry      ; (r1: the first directory block)
        txa
        bne @end
        lda r1L
        sta feH + H_BLKT
        lda r1H
        sta feH + H_BLKS
        lda #FRST_ENTRY
        sta feH + H_OFF
        lda #HT_DIR
@save:  sta feH + H_TYPE
        ldy #REU_STASH
        jsr HandleOp
        lda feHandle
        ldx #0
@end:   rts

; NewHandle: feHandle = a free handle (C clear), else C set and X =
; FE_NO_HANDLE.
NewHandle:
        lda #0
        sta feHandle
@try:   jsr HandleRegs
        lda #1                  ; (its type byte only)
        sta r2L
        ldy #REU_FETCH
        jsr ReuOp
        lda feH + H_TYPE
        beq @got
        inc feHandle
        lda feHandle
        cmp #FE_HANDLES_N
        bne @try
        ldx #FE_NO_HANDLE
        sec
        rts
@got:   clc
        rts

; Wild: C clear when feName holds "*" or "?".
Wild:   ldx #0
@ch:    lda feName,x
        beq @no
        cmp #'*'
        beq @yes
        cmp #'?'
        beq @yes
        inx
        bne @ch
@no:    sec
        rts
@yes:   clc
        rts

        .endscope

        .segment "OVL28"
        .scope Mod28

        jmp OvReadDir           ; entry 0

        .include "fereu.inc"
        .include "feinfo.inc"

; FE_READDIR: Y = a handle, r1 = an info block, r2 = a buffer for the
; name (17 bytes). X = FE_END_OF_DIR after the last one.
OvReadDir:
        ldy feY
        cpy #FE_HANDLES_N
        bcs @bad
        sty feHandle
        ldy #REU_FETCH
        jsr HandleOp
        lda feH + H_TYPE
        cmp #HT_ROOT
        beq Drives
        cmp #HT_DIR
        beq @dir
@bad:   ldx #FE_BAD_HANDLE
        rts
@dir:   sta feTouched           ; the drive and its folder of the listing
        ldx feH + H_DRIVE
        lda feH + H_FOLDT
        sta folderT-8,x
        lda feH + H_FOLDS
        sta folderS-8,x
        txa
        jsr SetDevice
@block: lda feH + H_BLKT        ; the block holding the next entry
        beq @eod
        sta r1L
        lda feH + H_BLKS
        sta r1H
        jsr ReadBuff            ; (to diskBlkBuf)
        txa
        bne @end
@entry: ldy feH + H_OFF
        lda diskBlkBuf,y
        beq @skip               ; (deleted or unused)
        jsr EntryName
        jsr Match
        bcs @skip
        lda feH + H_OFF
        clc
        adc #<diskBlkBuf
        sta r5L
        lda #>diskBlkBuf
        sta r5H
        jsr FillInfo
        jsr Advance
        jmp Found
@skip:  jsr Advance
        bcs @block
        bcc @entry
@eod:   jmp Eod
@end:   rts

; Drives (FE_READDIR on "/"): the next drive A-D that is there.
Drives: ldx feH + H_BLKT
@slot:  cpx #4
        bcs Eod
        lda driveType,x
        bne @drv
        inx
        bne @slot
@drv:   txa                     ; (C clear from the cpx)
        adc #'a'
        sta feTmp
        lda #0
        sta feTmp+1
        inx
        stx feH + H_BLKT
        lda #FE_K_DRIVE
        jsr InfoKind
        jmp Found
Eod:    ldx #FE_END_OF_DIR
        rts

; Found: the handle kept, feInfo and the name in feTmp to the caller.
Found:  ldy #REU_STASH
        jsr HandleOp
        lda argR2
        sta r0L
        lda argR2+1
        sta r0H
        ldy #0
@copy:  lda feTmp,y
        sta (r0),y
        beq @end
        iny
        bne @copy
@end:   jmp PutInfo

; Advance: past the entry at H_OFF; C set when that was a block's last
; (then the next block from its link, 0: the end).
Advance:
        lda feH + H_OFF
        clc
        adc #32
        sta feH + H_OFF         ; (after the last: FRST_ENTRY again)
        bcc @end
        lda diskBlkBuf
        sta feH + H_BLKT
        lda diskBlkBuf+1
        sta feH + H_BLKS
@end:   rts
        .assert (256 - 32 + FRST_ENTRY + 32) & $FF = FRST_ENTRY, error, "Advance: entries"

; EntryName: the name of the entry at H_OFF ($A0-padded) to feTmp,
; zero-ended.
EntryName:
        ldy feH + H_OFF
        iny                     ; (+ OFF_FNAME)
        iny
        iny
        ldx #0
@ch:    lda diskBlkBuf,y
        cmp #$A0
        beq @end
        sta feTmp,x
        iny
        inx
        cpx #FE_NAME_MAX
        bne @ch
@end:   lda #0
        sta feTmp,x
        rts

OFF_FNAME       = 3
        .assert OFF_FNAME = 3, error, "EntryName: three iny"

; Match: C clear when the name in feTmp fits the pattern at H_PAT ("*":
; any run of characters, "?": one). One way back: to the last "*", one
; character further in the name each time.
Match:  ldx #0                  ; X: in the pattern, Y: in the name
        ldy #0
        lda #$FF
        sta feM
@loop:  lda feTmp,y
        beq @tail
        lda feH + H_PAT,x
        cmp #'*'
        beq @star
        cmp #'?'
        beq @one
        cmp feTmp,y
        beq @one
        lda feM                 ; no fit: back to the last "*"
        bmi @no
        tax
        inx
        inc feMN
        ldy feMN                ; (below 128: always)
        bpl @loop
@one:   inx
        iny
        bne @loop
@star:  stx feM
        sty feMN
        inx
        bne @loop
@tail:  lda feH + H_PAT,x       ; the name used up: only "*"s may follow
        cmp #'*'
        bne @fin
        inx
        bne @tail
@fin:   cmp #1                  ; (C clear only for the pattern's end)
        rts
@no:    sec
        rts

        .endscope
