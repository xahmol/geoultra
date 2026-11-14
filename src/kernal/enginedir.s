; File engine: looking at files (docs/FILE_ENGINE.md "Functions"; engine.s
; has the module list): module 25 FE_STAT and FE_DF, module 26
; FE_OPENDIR, module 28 FE_READDIR (FE_CLOSE is in module 22). Own code.

        .include "geos.inc"
        .include "hw.inc"
        .include "kcalls.inc"
        .include "engine.inc"

        .import OvlCall, SysRAMOp, folderT, folderS, FindFile

        .segment "OVL25"
        .scope Mod25

        jmp OvStat              ; entry 0
        jmp OvDf                ; entry 3

UStat:  jsr OvlCall             ; (module 37: FE_STAT on the Ultimate)
        .byte 37, 0
LongOf: jsr OvlCall             ; (module 51: a file's long name to feTmp)
        .byte 51, 9

        .include "feresolve.inc"
        .include "feinfo.inc"

; FE_STAT: r0 = a path, r1 = an info block, r2 = 0 or a buffer of
; FE_LONG_MAX + 1 bytes for its long name (else its short one). A GEOS
; file's header is left in fileHeader. On the Ultimate: module 37.
OvStat: lda #1
        sta feUlt
        jsr Path
        bne @end
        lda feKind
        cmp #FE_P_ULTIMATE
        bne :+
        jmp UStat
:
        lda feKind              ; "/": the root
        beq @kind
        lda #FE_K_DRIVE         ; "/a": the drive
        ldx feName
        beq @kind
        jsr FindName
        txa
        bne @end
        lda r1L                 ; (its key, for its long name)
        sta lnKeyT
        lda r1H
        sta lnKeyS
        lda r5L
        sta lnKeyO
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
        bne @long
        jsr GetFHdrInfo         ; (r9: the entry; X its error)
        txa
        bne @end
@long:  lda argR2+1             ; the long name (else the short one) to r2
        beq @ok                 ; (after the header: it reads GU.LONGNAMES,
        jsr LongOf              ; dirEntryBuf changes)
        lda argR2
        sta r0L
        lda argR2+1
        sta r0H
        ldy #$FF
@copy:  iny
        lda feTmp,y
        sta (r0),y
        bne @copy
@ok:    ldx #0
        rts
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

UOpen:  jsr OvlCall             ; (module 38: FE_OPENDIR on the Ultimate)
        .byte 38, 0
HMark:  jsr OvlCall             ; (module 81: the handle's drive byte)
        .byte 81, 21

        .include "fereu.inc"
        .include "fehandle.inc"
        .include "feresolve.inc"
        .include "felen.inc"

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
        lda #1                  ; (Ultimate paths taken)
        sta feUlt
        jsr Resolve
        txa
        beq :+
        rts
:       lda feKind
        cmp #FE_P_ULTIMATE
        bne :+
        jmp UOpen
:       cmp #FE_P_ROOT
        bne @geos
        sta feH + H_BLKT        ; "/" (FE_P_ROOT): the drives from slot 0
        lda #HT_ROOT
        jmp @save
@geos:  lda feName
        beq @all
        jsr Wild
        bcc @pat
        jsr FindName            ; one name: a folder is listed whole
        txa
        beq :+
        jmp @end
:       jsr IsDir
        bcs @one
        jsr EnterName
        txa
        bne @end
@all:   lda #'*'
        sta feName
        lda #0
        sta feName+1
@pat:   jsr IsLongN             ; a pattern: at most FE_NAME_MAX characters
        beq :+
        ldx #FE_BAD_PATH
        rts
:       ldx #FE_NAME_MAX
@copy:  lda feName,x
        sta feH + H_PAT,x
        dex
        bpl @copy
        bmi @where
@one:   lda #LN_EXACT           ; one file: by its short name, $A0-padded
        sta feH + H_PAT         ; (its long name may be longer than a
        ldx #0                  ; pattern)
        ldy #0
@exact: lda feShort,y
        beq @pad
        iny
        bne @put
@pad:   lda #$A0
@put:   sta feH + H_PAT + 1,x
        inx
        cpx #FE_NAME_MAX
        bne @exact
@where:
        lda feDrive
        tax
        jsr HMark               ; (drive E or a disk image shown there:
        sta feH + H_DRIVE       ; marked, so HDrive shows it again)
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

UDir:   jsr OvlCall             ; (module 39: an Ultimate listing)
        .byte 39, 0
Root:   jsr OvlCall             ; (module 40: "/")
        .byte 40, 0
HDrive: jsr OvlCall             ; (module 81: a handle's drive current)
        .byte 81, 18
Pick:   jsr OvlCall             ; (module 51: the entry's long name, the
        .byte 51, 0             ; pattern; C clear: listed)

; FE_READDIR: Y = a handle, r1 = an info block, r2 = a buffer for the
; name (FE_LONG_MAX + 1 bytes: the long name, else the short one), r3 =
; 0 or a buffer of 17 bytes for the short name. X = FE_END_OF_DIR after
; the last one. GU.LONGNAMES is not listed.
OvReadDir:
        ldy feY
        cpy #FE_HANDLES_N
        bcs @bad
        sty feHandle
        ldy #REU_FETCH
        jsr HandleOp
        lda feH + H_TYPE
        cmp #HT_ROOT
        beq Root
        cmp #HT_UDIR
        beq UDir
        cmp #HT_DIR
        beq @dir
@bad:   ldx #FE_BAD_HANDLE
        rts
@dir:   sta feTouched           ; the drive and its folder of the listing
        lda feH + H_DRIVE       ; (drive E: shown again in its slot)
        jsr HDrive
        txa
        bne @end
        ldx curDrive
        lda feH + H_FOLDT
        sta folderT-8,x
        lda feH + H_FOLDS
        sta folderS-8,x
        jsr GetDirHead          ; (its header: GU.LONGNAMES is found from it)
        txa
        bne @end
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
        jsr EntryName           ; (its short name to feTmp)
        lda feH + H_OFF
        sta lnKeyO              ; (its key, for its long name)
        clc
        adc #<diskBlkBuf
        sta r5L
        lda #>diskBlkBuf
        sta r5H
        jsr FillInfo
        lda feH + H_BLKT
        sta lnKeyT
        lda feH + H_BLKS
        sta lnKeyS
        jsr Advance
        jsr Pick                ; (module 51: diskBlkBuf read anew after)
        bcs @block
        jmp Found
@skip:  jsr Advance
        bcs @block
        bcc @entry
@eod:   jmp Eod
@end:   rts

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

        .endscope
