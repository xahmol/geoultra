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

        .include "fereu.inc"
        .include "feresolve.inc"

MakeDir:
        jsr OvlCall             ; (extension table +20, folders.s)
        .byte 14, 0
RemoveDir:
        jsr OvlCall             ; (extension table +25)
        .byte 13, 3

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
        ldx #WR_PR_ON
        lda dirEntryBuf
        and #$40                ; locked
        bne @end
        jsr NameR0
        jmp DeleteFile
@end:   rts

; FE_RENAME: r0 = a file or folder, r1 = its new name (no "/", at most
; FE_NAME_MAX characters, not there yet).
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
        cpy #FE_NAME_MAX + 1
        bne @ch
@bad:   ldx #FE_BAD_PATH
@end:   rts
@got:   tya
        beq @bad
        jsr FindName            ; the old one there
        txa
        bne @end
        lda #<feTmp             ; the new one not
        sta r6L
        lda #>feTmp
        sta r6H
        jsr FindFile
        txa
        beq @exists
        cpx #FILE_NOT_FOUND
        bne @end
        lda #<feName
        sta r6L
        lda #>feName
        sta r6H
        lda #<feTmp
        sta r0L
        lda #>feTmp
        sta r0H
        jmp RenameFile
@exists:
        ldx #FILE_EXISTS
        rts

; FE_MKDIR: r0 = a new folder, r2L = tracks (1581 partitions; 0: the
; default). MakeDir's errors (STRUCT_MISMAT: no folders on this drive).
OvMkDir:
        jsr Target
        bcs @end
        jsr NameR0
        lda argR2
        sta r2L
        jmp MakeDir
@end:   rts

; FE_RMDIR: r0 = an empty folder.
OvRmDir:
        jsr Target
        bcs @end
        jsr NameR0
        jsr RemoveDir
        cpx #STRUCT_MISMAT
        bne @end
        ldx #FE_NOT_FOLDER
@end:   rts

; FE_CD: r0 = a folder, a drive or "/": the current directory.
OvCd:   jsr Path
        bne @end
        lda feKind
        beq @set                ; "/"
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
        lda #FE_PATH_MAX + 1
        sta r2L
        lda #0
        sta r2H
        ldy #REU_STASH
        jsr ReuOp
        ldx #0
@end:   rts

; Target: the caller's r0 resolved to something in a folder of a GEOS
; drive (C clear); else C set and X = the error (FE_BAD_PATH for "/" or
; a drive).
Target: jsr Path
        bne @no
        ldx #FE_BAD_PATH
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

; NameR0: r0 = feName.
NameR0: lda #<feName
        sta r0L
        lda #>feName
        sta r0H
        rts

        .endscope
