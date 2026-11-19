; GeoUltra Desktop: system fonts installed and uninstalled (overlay 3,
; ovl.s; docs/DESIGN.md "System font folder", step F; the user's
; decisions of 2026-11-19). Own code.

        .include "geos.inc"
        .include "desktop.inc"

        .import FileEngine, ListRead, ListDraw, Busy, Idle, Dialog, Error
        .import entryName, path
        .export Ov_FontAct

        .segment "ZEROPAGE"

askLine:        .res 2          ; (DBVARSTR: a zero page pointer)

        .segment "OV3"

; --- System fonts (docs/DESIGN.md "System font folder"; the user's
; decisions of 2026-11-19) ---------------------------------------------

; Ov_FontAct (list.s TaskOrMount, item 1 of the context menu; the cursor's
; entry fetched, a GEOS font): in /f "uninstall", elsewhere "install as
; system font". GEOULTRA/FONTS.DNP (made with 8 tracks when missing) is
; mounted in a free drive letter for it (the tested write path, written
; back when unmounted): the font copied into it, or deleted from it (and
; its CVT in GEOULTRA/fonts, which the desktop would install again);
; then unmounted. The change counts from the next start: "Done. Restart
; now?" (the font's name on the second line; texts within the dialog's
; width, the user's rule)
; restarts keeping the session (FE_REBOOT Y = 1). No free letter: a
; note, nothing done.
        .scope FontScope
Act:    ldx #0                  ; a free letter
@free:  lda driveType,x
        beq @got
        inx
        cpx #4
        bcc @free
        lda #<NoLetter
        ldx #>NoLetter
        jmp Note
@got:   txa
        clc
        adc #'a'
        sta letter + 1
        jsr Store               ; fPath: the home folder's FONTS.DNP
        bcs @end
        jsr Busy
        jsr Uninst              ; (Z set: uninstalling, in /f)
        bne :+
        jsr Out
        jmp @done
:       jsr In
@done:  jsr Idle
        ldx status
        beq :+
        jmp Error               ; (none for "not there": status 0)
:       bit acted
        bpl @end
        lda #<Restart           ; done: "Restart now?"
        ldx #>Restart
        jsr Ask
        bne @list
        ldy #1                  ; restarted, the session kept (back here
        lda #FE_REBOOT          ; after the resume)
        jsr FileEngine
@list:  jsr ListRead
        jmp ListDraw
@end:   rts

; Out (uninstall): the font deleted from FONTS.DNP (mounted on letter for
; it) and its CVT from GEOULTRA/fonts; status its error, acted $80 when
; done. No FONTS.DNP: nothing (status 0, acted 0).
Out:    lda #0
        sta status
        sta acted
        lda #<fPath
        ldx #>fPath
        jsr Stat
        bne @end
        jsr MountIt
        stx status
        bne @end
        lda #<letter            ; /x/name out of it
        ldx #>letter
        jsr Join
        lda #FE_DELETE
        jsr FileEngine
        stx status
        jsr UMount
        lda status
        bne @end
        jsr Cvt                 ; (none: fine)
        lda #$80
        sta acted
@end:   rts

; In (install): FONTS.DNP made when missing (8 tracks), mounted on letter,
; the font (path/name) copied into it, unmounted; status, acted as Out.
In:     lda #0
        sta acted
        lda #<fPath
        ldx #>fPath
        jsr Stat
        beq @have
        lda #<fPath
        sta r0L
        lda #>fPath
        sta r0H
        lda #<StoreName
        sta r1L
        lda #>StoreName
        sta r1H
        lda #8
        sta r2L
        lda #FE_MKIMG
        jsr FileEngine
        stx status
        txa
        bne @end
@have:  jsr MountIt
        stx status
        bne @end
        lda #<path              ; path/name into /x
        ldx #>path
        jsr Join
        lda #<letter
        sta r1L
        lda #>letter
        sta r1H
        lda #0
        sta r2L
        lda #FE_COPY
        jsr FileEngine
        stx status
        jsr UMount
        lda status
        bne @end
        lda #$80
        sta acted
@end:   rts

; Uninst: Z set when the current folder is /f (the installed fonts).
Uninst: lda path + 1
        cmp #'f'
        bne :+
        lda path + 2
:       rts

; Store: fPath = the home folder ("/USB0/GEOULTRA/", FE_HOME) and
; FONTS.DNP; C set without an Ultimate (nothing to do).
Store:  lda #<fPath
        sta r1L
        lda #>fPath
        sta r1H
        lda #FE_HOME
        jsr FileEngine
        txa
        sec
        bne @end
        ldy #0
@end1:  lda fPath,y
        beq :+
        iny
        bne @end1
:       ldx #0
@cp:    lda StoreFile,x
        sta fPath,y
        beq @ok
        iny
        inx
        bne @cp
@ok:    clc
@end:   rts

; Stat: Z set when the path at A/X exists (FE_STAT).
Stat:   sta r0L
        stx r0H
        lda #<info
        sta r1L
        lda #>info
        sta r1H
        lda #0
        sta r2L
        sta r2H
        lda #FE_STAT
        jsr FileEngine
        txa
        rts

; MountIt: fPath mounted on letter (FE_MOUNT); Z set when it worked, X.
MountIt:
        lda #<letter
        sta r0L
        lda #>letter
        sta r0H
        lda #<fPath
        sta r1L
        lda #>fPath
        sta r1H
        lda #FE_MOUNT
        jsr FileEngine
        txa
        rts

; UMount: letter unmounted (written back); its error left for status.
UMount: lda #<letter
        sta r0L
        lda #>letter
        sta r0H
        lda #FE_UMOUNT
        jmp FileEngine

; Join: src = the path at A/X, "/", entryName (r0 = src).
Join:   sta r0L
        stx r0H
        ldy #0
:       lda (r0),y
        sta src,y
        beq :+
        iny
        bne :-
:       lda #'/'
        sta src,y
        iny
        ldx #0
:       lda entryName,x
        sta src,y
        beq :+
        iny
        inx
        cpx #NAME_KEEP
        bcc :-
        lda #0
        sta src,y
:       lda #<src
        sta r0L
        lda #>src
        sta r0H
        rts

; Cvt: GEOULTRA/fonts/<name>.cvt deleted (the desktop installs the CVTs
; there at its start; none there: fine). fPath ends in "FONTS.DNP".
Cvt:    ldy #0
:       lda fPath,y             ; the home folder: fPath up to "FONTS.DNP"
        beq :+
        iny
        bne :-
:       tya
        sec
        sbc #9                  ; (strlen "FONTS.DNP")
        tay
        ldx #0
:       lda CvtDir,x            ; "fonts/"
        beq :+
        sta fPath,y
        iny
        inx
        bne :-
:       ldx #0
:       lda entryName,x
        beq :+
        sta fPath,y
        iny
        inx
        cpx #NAME_KEEP
        bcc :-
:       ldx #0
:       lda CvtExt,x
        sta fPath,y
        beq :+
        iny
        inx
        bne :-
:       lda #<fPath
        sta r0L
        lda #>fPath
        sta r0H
        lda #FE_DELETE
        jmp FileEngine

; Ask: the question at A/X with YES and NO (the font's name on the
; second line): Z set for YES.
Ask:    sta askLine
        stx askLine+1
        lda #<askDlg
        sta r0L
        lda #>askDlg
        sta r0H
        jsr Dialog
        lda r0L
        cmp #YES
        rts

askDlg: .byte DEF_DB_POS | 1
        .byte DBVARSTR, TXT_LN_X, TXT_LN_1_Y + 6, askLine
        .byte DBTXTSTR, TXT_LN_X, TXT_LN_2_Y + 6
        .word entryName
        .byte YES, DBI_X_0, DBI_Y_2
        .byte NO, DBI_X_2, DBI_Y_2
        .byte 0

; Note: the text at A/X with OK.
Note:   sta askLine
        stx askLine+1
        lda #<noteDlg
        sta r0L
        lda #>noteDlg
        sta r0H
        jmp Dialog

noteDlg:                        ; (the second line: the only note's)
        .byte DEF_DB_POS | 1
        .byte DBVARSTR, TXT_LN_X, TXT_LN_1_Y + 6, askLine
        .byte DBTXTSTR, TXT_LN_X, TXT_LN_2_Y + 6
        .word NoLetter2
        .byte OK, DBI_X_2, DBI_Y_2
        .byte 0
NoLetter:       .byte BOLDON, "No drive letter free.", PLAINTEXT, 0
NoLetter2:      .byte "Free one to install fonts.", 0
Restart:        .byte BOLDON, "Done. Restart now?", PLAINTEXT, 0
StoreFile:      .byte "FONTS.DNP", 0
StoreName:      .byte "System fonts", 0
CvtDir:         .byte "fonts/", 0
CvtExt:         .byte ".cvt", 0
NAME_KEEP       = 16            ; a GEOS name's characters

letter:         .byte "/x", 0   ; the free drive letter's path
status:         .byte 0
acted:          .byte 0         ; $80: a font installed or uninstalled
fPath:          .res 48         ; FONTS.DNP's path, then its CVT's
src:            .res 63 + 18    ; (a path, "/", a GEOS name)
info:           .res 16         ; (FE_STAT's info block)
        .endscope
Ov_FontAct = FontScope::Act
