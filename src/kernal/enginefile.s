; File engine: changing files and folders (docs/FILE_ENGINE.md
; "Functions"; engine.s has the module list): module 27 FE_DELETE,
; FE_RENAME, FE_MKDIR, FE_RMDIR, FE_CD. Own code.

        .include "geos.inc"
        .include "hw.inc"
        .include "kcalls.inc"
        .include "engine.inc"

        .import OvlCall, SysRAMOp, FindFile

        .segment "OVL27"
        .scope Mod27

        jmp OvDelete            ; entry 0
        jmp OvRename            ; entry 3
        jmp OvMkDir             ; entry 6
        jmp OvRmDir             ; entry 9
        jmp OvCd                ; entry 12
        jmp OvSelect            ; entry 15

        .include "fereu.inc"
        .include "feresolve.inc"

RemoveDir:
        jsr OvlCall             ; (extension table +25)
        .byte 13, 3
UFile:  jsr OvlCall             ; (module 41: the function on the Ultimate)
        .byte 41, 0
LRename:
        jsr OvlCall             ; (module 54: rename, long names)
        .byte 54, 0
LMkDir: jsr OvlCall             ; (module 54: a folder, long names)
        .byte 54, 3
Drop:   jsr OvlCall             ; (module 51: a deleted file's record)
        .byte 51, 3
UCdAll: jsr OvlCall             ; (module 41: into an Ultimate folder)
        .byte 41, 3

; FE_DELETE: r0 = a file (not a folder, not locked).
OvDelete:
        jsr Target
        bcs @end
        jsr FindName
        txa
        bne @end
        jsr IsDir
        ldx #FE_IS_FOLDER
        bcc @end
        jsr Locked              ; (task.s: write-protected, or open in
                                ; another task)
        bne @end
        jsr Key
        jsr NameR0
        jsr DeleteFile
        txa
        bne @end
        jmp Drop                ; (its long name's record)
@end:   rts

; FE_RENAME, FE_SETLONG: r0 = a file or folder, r1 = its new name (no
; "/", 1 to FE_LONG_MAX characters; a long one gets a short name made
; for it, module 54; another file of that name: FILE_EXISTS).
OvRename:
        jsr Target
        bcs @end
        lda argR1
        sta r1L
        lda argR1+1
        sta r1H
        ldy #0
@ch:    lda (r1),y
        sta feTmp,y
        beq @got
        cmp #'/'
        beq @bad
        iny
        cpy #FE_LONG_MAX + 1
        bne @ch
@bad:   ldx #FE_BAD_PATH
@end:   rts
@got:   tya
        beq @bad
        jsr FindName            ; the old one there: its key
        txa
        bne @end
        lda r1L
        sta cSrcET
        lda r1H
        sta cSrcES
        lda r5L
        sta cSrcEO
        jmp LRename

; FE_MKDIR: r0 = a new folder, r2L = tracks (1581 partitions; 0: the
; default). MakeDir's errors (STRUCT_MISMAT: no folders on this drive).
; Module 54 (long names).
OvMkDir:
        jsr Target
        bcs @end
        jmp LMkDir
@end:   rts

; FE_RMDIR: r0 = an empty folder.
OvRmDir:
        jsr Target
        bcs @end
        jsr FindName            ; (its key, for its long name)
        txa
        bne @end
        jsr Key
        jsr NameR0
        jsr RemoveDir
        txa
        bne :+
        jmp Drop
:       cpx #STRUCT_MISMAT
        bne @end
        ldx #FE_NOT_FOLDER
@end:   rts

; FE_CD: r0 = a folder, a drive or "/": the current directory. On the
; Ultimate: a folder it can enter.
OvCd:   lda #1
        sta feUlt
        jsr Path
        bne @end
        lda feKind
        beq @set                ; "/"
        cmp #FE_P_ULTIMATE
        bne @geos
        jsr UCdAll              ; (module 41)
        txa
        bne @end
        beq @set
@geos:
        lda feName
        beq @set                ; a drive
        jsr EnterName
        txa
        bne @end
@set:   lda #<fePath
        sta r0L
        lda #>fePath
        sta r0H
        lda #<FE_CWD
        sta r1L
        lda #>FE_CWD
        sta r1H
        lda #<(FE_PATH_MAX + 1)
        sta r2L
        lda #>(FE_PATH_MAX + 1)
        sta r2H
        ldy #REU_STASH
        jsr ReuOp
        ldx #0
@end:   rts

; FE_SELECT: r0 = a file on a GEOS drive, r1 = a buffer of 17 bytes:
; its drive and folder become the caller's current ones (not put back, as
; after every other function; the disk is open), its short name to r1:
; ready for GetFile (gush starts programs so).
OvSelect:
        jsr Path                ; (feUlt 0: an Ultimate path not taken)
        bne @end
        ldx #FE_BAD_PATH
        lda feName              ; ("/" or a drive)
        beq @end
        jsr FindName
        txa
        bne @end
        stx feTouched           ; (0: the dispatcher leaves the drive)
        lda argR1
        sta r1L
        lda argR1+1
        sta r1H
        ldy #FE_NAME_MAX
@copy:  lda feShort,y
        sta (r1),y
        dey
        bpl @copy
@end:   rts

; Target: the caller's r0 resolved to something in a folder of a GEOS
; drive (C clear); else C set and X = the error (FE_BAD_PATH for "/" or
; a drive). On the Ultimate the whole function is module 41's: Target's
; return address is dropped, so module 41 returns to the function's
; caller.
Target: lda #1
        sta feUlt
        jsr Path
        bne @no
        lda feKind
        cmp #FE_P_ULTIMATE
        bne :+
        pla
        pla
        jmp UFile
:       ldx #FE_BAD_PATH
        lda feName
        beq @no
        clc
        rts
@no:    sec
        rts

; Path: the caller's r0 resolved; Z clear and X = the error when it fails.
Path:   lda argR0
        sta r0L
        lda argR0+1
        sta r0H
        jsr Resolve
        txa
        rts

; Key: lnKey* = the file FindName found (r1, r5).
Key:    lda r1L
        sta lnKeyT
        lda r1H
        sta lnKeyS
        lda r5L
        sta lnKeyO
        rts

; NameR0: r0 = feShort (the name on disk).
NameR0: lda #<feShort
        sta r0L
        lda #>feShort
        sta r0H
        rts


; Locked (task.s, module 98): X = WR_PR_ON (dirEntryBuf's file
; write-protected), FE_IN_TASK (open in another task) or 0; Z as X.
; (A stub: OvlCall returns to its caller.)
Locked: jsr OvlCall
        .byte 98, 12

        .endscope
