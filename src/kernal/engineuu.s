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
; FC_OVERWRITE deleted first. COPY keeps the source's name and does
; nothing in the source's own folder, so a copy under another name
; (every copy within one folder among them) goes through a temporary
; folder (module 85). X = 0 or the error.
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
:       jsr UCd                 ; the target's folder
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
@copy:  jsr SameName            ; another name (so also any copy in its
        bcs :+                  ; own folder): through a temporary folder
        jmp Via                 ; (module 85)
:       jsr CdSrc               ; the same name: COPY name, the target's
        txa                     ; folder "/"
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
        jmp UExec

Via:    jsr OvlCall             ; (module 85: through GU.TMP)
        .byte 85, 0

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

        .segment "OVL85"
        .scope Mod85

        jmp OvUVia              ; entry 0

        .include "feult.inc"
        .include "fecd.inc"

; OvUVia (module 84: a copy under another name on the Ultimate, its
; checks done; the source's path in diskBlkBuf, cSrcFT the "/" before
; its name; the target's in fePath): COPY into a temporary folder
; TMP_DIR at the top of the target's volume (made when missing; a file
; of the same name left there earlier deleted), RENAME from the
; volume's top to the target's path (a move, measured), the temporary
; folder removed again. X = 0 or the error (the first one counts).
OvUVia:
        ldx #0                  ; the target's volume: fePath's first part
@vol:   inx
        lda fePath,x
        beq :+
        cmp #'/'
        bne @vol
:       stx cSrcFS
        jsr Top
        txa
        beq :+
        rts
:       lda #U_MKDIR            ; TMP_DIR made (there already: fine)
        jsr UBegin
        jsr PutTmp
        jsr Exec
        lda #U_DELETE           ; a file of that name left in it: away
        jsr UBegin
        jsr PutTmpName
        bcs @long
        jsr Exec
        jsr CdSrc               ; COPY name, the volume "/" TMP_DIR "/"
        txa
        bne @clean
        lda #U_COPY
        jsr UBegin
        jsr PutName
        bcs @long
        lda #0
        jsr PutChk
        ldx #$FF
@top:   inx
        cpx cSrcFS
        beq :+
        lda fePath,x
        jsr PutChk
        bcc @top
        bcs @long
:       lda #'/'
        jsr PutChk
        jsr PutTmp
        lda #'/'
        jsr PutChk
        bcs @long
        jsr Exec
        txa
        bne @clean
        jsr Top                 ; RENAME TMP_DIR/name, the target's path
        txa
        bne @clean
        lda #U_RENAME
        jsr UBegin
        jsr PutTmpName
        bcs @long
        lda #0
        jsr PutChk
        ldx cSrcFS
@new:   inx
        lda fePath,x
        beq :+
        jsr PutChk
        bcc @new
        bcs @long
:       jsr Exec
@clean: txa                     ; TMP_DIR removed (the result kept on the
        pha                     ; stack: module data is reloaded after
        jsr Top                 ; each nested call)
        lda #U_DELETE
        jsr UBegin
        jsr PutTmp
        jsr Exec
        pla
        tax
@end:   rts
@long:  ldx #FE_BAD_PATH
        bne @clean

; Top: into the volume's top (fePath's first cSrcFS characters). X = 0
; or the error.
Top:    ldx cSrcFS
        jmp UCdX

; Exec: the command in uCmd sent, no data. X = 0 or the error.
Exec:   jsr UNoData
        jmp UExec

; PutTmp: TMP_DIR to uCmd. PutName: the source's name. PutTmpName:
; TMP_DIR "/" and the source's name. C set: no room.
PutTmp: ldx #0
@ch:    lda TmpDir,x
        beq @end
        jsr PutChk
        inx
        bcc @ch
        rts
@end:   clc
        rts
PutTmpName:
        jsr PutTmp
        bcs PutEnd
        lda #'/'
        jsr PutChk
        bcs PutEnd
PutName:
        ldx cSrcFT
@ch:    inx
        lda diskBlkBuf,x
        beq PutOk
        jsr PutChk
        bcc @ch
PutEnd: rts
PutOk:  clc
        rts

TmpDir: .byte "GU.TMP", 0

        .include "feuu.inc"

        .endscope
