; File engine: from one Ultimate path to another (docs/FILE_ENGINE.md,
; "Copying"; engine.s has the module list; 2026-11-11, for the
; desktop's folders): module 83 FE_MOVE as a rename from the volume's
; top (files and folders, anywhere on the same volume), module 84 a
; file's FE_COPY with the Ultimate's own COPY. Both are called by module
; 43 (enginexfer.s), which resolved the source.
;
; Measured on a U64-II with firmware 3.15a (2026-11-11): RENAME takes
; paths relative to the current folder on both sides and so moves a file
; or a folder (with everything in it) into another folder of the same
; volume; an absolute path is refused. COPY copies a file of the current
; folder into a folder given by its absolute path, under the same name,
; and does not overwrite (ultimate-uci-oscar64 manual). Own code.

        .include "geos.inc"
        .include "hw.inc"
        .include "kcalls.inc"
        .include "engine.inc"

        .import OvlCall

U_COPY          = $0B           ; the DOS COPY command

        .segment "OVL83"
        .scope Mod83

        jmp OvUMove             ; entry 0

        .include "feult.inc"
        .include "fecd.inc"

Resolve:
        jsr OvlCall
        .byte 23, 0

; OvUMove (FE_MOVE from the Ultimate, the source resolved): when the
; target lies on the same Ultimate volume, a RENAME from the volume's top
; does it (a file or a folder; into an existing folder under the
; source's name; an existing file replaced only with FC_OVERWRITE): C
; clear, X the result. Else C set and r0 = the caller's r0 again (module
; 43 then copies and deletes). The source's path kept in diskBlkBuf.
OvUMove:
        jsr SaveSrc
        lda argR1
        sta r0L
        lda argR1+1
        sta r0H
        jsr Resolve
        txa
        bne @no
        lda feKind
        cmp #FE_P_ULTIMATE
        bne @no
        jsr Volume              ; (cSrcFS: the volume's length)
        bcs @no
        jsr IntoFolder          ; into an existing folder: its own name
        bcs @long
        jsr Same                ; onto itself: nothing to do
        bne :+
        ldx #0
        clc
        rts
:       jsr Rename
        cpx #FILE_EXISTS        ; there already: replaced when allowed
        bne @done
        lda argR2
        and #FC_OVERWRITE
        beq @done
        jsr UCd                 ; (the target's folder: fePos)
        txa
        bne @done
        lda #U_DELETE
        jsr UBegin
        jsr UPutName
        jsr UNoData
        jsr UExec
        txa
        bne @done
        jsr Rename
@done:  clc
        rts
@long:  ldx #FE_BAD_PATH
        clc
        rts
@no:    lda argR0
        sta r0L
        lda argR0+1
        sta r0H
        sec
        rts

; Rename: into the volume's top (fePath's first cSrcFS characters),
; RENAME the old path (diskBlkBuf) to the new one (fePath), both after
; the volume's "/". X = the result (FE_BAD_PATH: too long for a command).
Rename: ldx cSrcFS
        jsr UCdX
        txa
        bne @end
        lda #U_RENAME
        jsr UBegin
        ldx cSrcFS
@old:   inx
        lda diskBlkBuf,x
        jsr PutChk
        bcs @long
        cmp #0                  ; (the zero between the two)
        bne @old
        ldx cSrcFS
@new:   inx
        lda fePath,x
        beq @send
        jsr PutChk
        bcs @long
        bcc @new
@send:  jsr UNoData
        jmp UExec
@long:  ldx #FE_BAD_PATH
@end:   rts

; Volume: C clear when the target (fePath) lies on the source's volume
; (diskBlkBuf): the same first part ("/usb0"); cSrcFS = its length. C
; set: another volume.
Volume: ldx #0
@ch:    inx
        lda fePath,x
        beq @top
        cmp #'/'
        beq @top
        cmp diskBlkBuf,x
        beq @ch
@other: sec
        rts
@top:   lda diskBlkBuf,x        ; (the source ends its volume here too)
        beq @same
        cmp #'/'
        bne @other
@same:  stx cSrcFS
        clc
        rts

        .include "feuu.inc"     ; (SaveSrc, IntoFolder, Same, PutChk,
                                ; EndOf: shared with module 84)

        .endscope

        .segment "OVL84"
        .scope Mod84

        jmp OvUCopy             ; entry 0

        .include "feult.inc"
        .include "fecd.inc"

Resolve:
        jsr OvlCall
        .byte 23, 0

; OvUCopy (FE_COPY or FE_MOVE from one Ultimate path to another; module
; 43, the source file closed again): the Ultimate's COPY from the
; source's folder into the target's folder, then a RENAME there when the
; target has another name. An existing target file: FILE_EXISTS, or with
; FC_OVERWRITE deleted first. COPY keeps the source's name, so a copy
; under another name into a folder that already has a file of the
; source's name gives FE_NOT_SUPPORTED, and so does a copy into the
; source's own folder (COPY does nothing there). X = 0 or the error.
OvUCopy:
        lda argR0
        sta r0L
        lda argR0+1
        sta r0H
        jsr Resolve
        txa
        bne @end
        jsr SaveSrc
        lda argR1
        sta r0L
        lda argR1+1
        sta r0H
        jsr Resolve
        txa
        bne @end
        jsr IntoFolder          ; into an existing folder: the source's name
        bcs @long
        jsr Same                ; (onto itself: refused; Same uses X)
        bne :+
        ldx #FE_BAD_PATH
        rts
:       ldx #FE_NOT_SUPPORTED   ; in its own folder: COPY would do nothing
        lda fePos               ; and the rename below would take the
        cmp cSrcFT              ; source itself (measured: a copy became
        bne :+                  ; a move), so refused
        tay
@same:  dey
        bmi @end                ; (the same folder)
        lda fePath,y
        cmp diskBlkBuf,y
        beq @same
:
        jsr UCd                 ; the target's folder
        txa
        bne @end
        lda argR2               ; an existing target: replaced when
        and #FC_OVERWRITE       ; allowed, else FILE_EXISTS
        beq @check
        lda #U_DELETE
        jsr UBegin
        jsr UPutName
        jsr UNoData
        jsr UExec               ; (not there: fine)
        jmp @copy
@check: lda #U_OPEN             ; (opened: it is there)
        jsr UBegin
        lda #UO_READ
        jsr UPut
        jsr UPutName
        jsr UNoData
        jsr UExec
        txa
        bne @copy
        lda #U_CLOSE
        jsr UBegin
        jsr UNoData
        jsr UExec
        ldx #FILE_EXISTS
@end:   rts
@long:  ldx #FE_BAD_PATH
        rts
@copy:  jsr CdSrc               ; COPY name, the target's folder "/"
        txa
        bne @end
        lda #U_COPY
        jsr UBegin
        ldx cSrcFT
@name:  inx
        lda diskBlkBuf,x
        jsr PutChk
        bcs @long
        cmp #0
        bne @name
        ldx #$FF
@dir:   inx
        cpx fePos
        beq @slash
        lda fePath,x
        jsr PutChk
        bcs @long
        bcc @dir
@slash: lda #'/'
        jsr PutChk
        bcs @long
        jsr UNoData
        jsr UExec
        txa
        beq :+
        cpx #FILE_EXISTS        ; (another name, and the source's name
        bne @end                ; already in that folder: COPY keeps the
        jsr SameName            ; name, so this copy cannot be made)
        ldx #FILE_EXISTS        ; (SameName uses X)
        bcs @end                ; (C set: the same name)
        ldx #FE_NOT_SUPPORTED
        rts
:       jsr SameName            ; another name: renamed in the target's
        ldx #0                  ; folder (SameName uses X)
        bcs @end
        jsr UCd
        txa
        bne @end
        lda #U_RENAME
        jsr UBegin
        ldx cSrcFT
@old:   inx
        lda diskBlkBuf,x
        jsr PutChk
        bcs @long
        cmp #0
        bne @old
        jsr UPutName
        jsr UNoData
        jmp UExec

; CdSrc: into the source's folder (diskBlkBuf's first cSrcFT
; characters). X = 0 or the error.
CdSrc:  lda #U_CD
        jsr UBegin
        ldx #$FF
@ch:    inx
        cpx cSrcFT
        beq @send
        lda diskBlkBuf,x
        jsr PutChk
        bcc @ch
        ldx #FE_BAD_PATH
        rts
@send:  jsr UNoData
        jmp UExec

; SameName: C set when the target's last part (fePath after fePos) is
; the source's (diskBlkBuf after cSrcFT), C clear when not. Destroys X.
SameName:
        ldx cSrcFT
        ldy fePos
@ch:    inx
        iny
        lda diskBlkBuf,x
        cmp fePath,y
        bne @no
        cmp #0
        bne @ch
        sec
        rts
@no:    clc
        rts

        .include "feuu.inc"

        .endscope
