; GeoUltra Desktop: system fonts installed and uninstalled (overlay 9,
; ovl.s; docs/DESIGN.md "System font folder", step F; the user's
; decisions of 2026-11-19). Own code.

        .include "geos.inc"
        .include "desktop.inc"

        .import FileEngine, ListRead, ListDraw, Busy, Idle, Dialog, Error
        .import entryName, path
        .export Ov_FontAct, Ov_FontImport

        .segment "ZEROPAGE"

askLine:        .res 2          ; (DBVARSTR: zero page pointers)
line2:          .res 2

        .segment "OV9"          ; (overlay 9 of its own since 2026-11-19:
                                ; 3, then 7 were full)

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
Act:    jsr FreeLetter
        bcc :+
        lda #<NoLetter
        ldx #>NoLetter
        jmp Note
:       jsr Store               ; fPath: the home folder's FONTS.DNP
        bcs @end
        jsr Busy
        lda #0                  ; (Out, In: nothing done yet)
        sta status
        sta acted
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
        lda #<entryName         ; the font's name on the second line
        ldx #>entryName
        jsr Offer
        jsr ListRead
        jmp ListDraw
@end:   rts

; Offer: "Done. Restart now?" with the text at A/X on the second line;
; YES restarts keeping the session (FE_REBOOT Y = 1: back here after the
; resume, X = 0), NO returns.
Offer:  sta line2
        stx line2+1
        lda #<Restart
        ldx #>Restart
        jsr Ask
        bne :+
        ldy #1
        lda #FE_REBOOT
        jmp FileEngine
:       rts

; FreeLetter: letter = "/x" for the first drive A-D not in use, C clear;
; C set when all four are.
FreeLetter:
        ldx #0
@free:  lda driveType,x
        beq @got
        inx
        cpx #4
        bcc @free
        rts                     ; (C set by the cpx)
@got:   txa
        clc
        adc #'a'
        sta letter + 1
        rts                     ; (C clear: the adc of 0-3)

; Import (Ov_FontImport; desktop.s Start, step F4): the CVT files directly in
; GEOULTRA/fonts (the user's installed set; its subfolders are a library)
; that /f does not have yet go into FONTS.DNP; then the restart offered.
; One that is in FONTS.DNP already but not active (the restart refused)
; is skipped by FE_COPY (FILE_EXISTS): no question again, though FONTS.DNP
; is mounted for it at each start until the restart. No home folder (no
; Ultimate), no fonts folder, or no free letter: nothing, quietly (the
; start goes on; the next start tries again).
Import:
        jsr Store
        bcc :+
        rts
:       lda #0
        sta acted
        sta mounted
        jsr Home                ; src = the home folder, Y its length
        ldx #0
:       lda CvtDir,x            ; + "fonts" (the folder, no slash)
        sta src,y
        iny
        inx
        cpx #5
        bcc :-
        lda #0
        sta src,y
        lda #<src
        sta r0L
        lda #>src
        sta r0H
        lda #FE_OPENDIR
        jsr FileEngine
        sta handle
        txa
        bne @end
@next:  ldy handle
        lda #<info
        sta r1L
        lda #>info
        sta r1H
        lda #<cvtName
        sta r2L
        lda #>cvtName
        sta r2H
        lda #0
        sta r3L
        sta r3H
        lda #FE_READDIR
        jsr FileEngine
        txa
        bne @close              ; (FE_END_OF_DIR, or an error: done)
        lda info + FI_KIND
        cmp #K_UFILE
        bne @next
        jsr IsCvt
        bcs @next
        jsr Active              ; in /f already: nothing to do
        beq @next
        jsr Bring
        bcc @next
@close: ldy handle
        lda #FE_CLOSE
        jsr FileEngine
        bit mounted
        bpl @end
        jsr UMount              ; (not written back: no question, the
        txa                     ; fonts are not in FONTS.DNP; the next
        beq :+                  ; start tries again)
        lsr acted
:       jsr Idle
        bit acted
        bpl @end
        lda #<FromDir
        ldx #>FromDir
        jmp Offer
@end:   rts

; IsCvt: C clear when cvtName ends in ".cvt" (any case) after 1-16
; characters (a GEOS name); then Y = the stem's length.
IsCvt:  ldy #0
:       lda cvtName,y
        beq :+
        iny
        cpy #21
        bcc :-
        rts                     ; (too long: C set)
:       cpy #5
        bcc @no
        tya
        sec
        sbc #3                  ; ("cvt": the last three)
        tay
        ldx #0
:       lda cvtName,y
        ora #$20                ; (lower case: ASCII letters)
        cmp CvtExt + 1,x
        bne @no
        iny
        inx
        cpx #3
        bcc :-
        lda cvtName - 4,y       ; (the dot)
        cmp #'.'
        bne @no
        tya
        sec
        sbc #4
        tay
        clc
        rts
@no:    sec
        rts

; Active: Z set when /f has the stem (Y long) of cvtName (FE_STAT).
Active: ldx #0
:       lda FPath,x
        sta src,x
        inx
        cpx #3
        bcc :-
        ldx #0
:       lda cvtName,x
        sta src + 3,x
        inx
        dey
        bne :-
        lda #0
        sta src + 3,x
        lda #<src
        ldx #>src
        jmp Stat

; Bring: cvtName copied from GEOULTRA/fonts into FONTS.DNP (made and
; mounted on the first one: a free letter, Busy); acted $80 for a copy,
; FILE_EXISTS (there, not active yet) skipped. C set: stop (no letter,
; or an error: status).
Bring:  bit mounted
        bmi @copy
        jsr FreeLetter
        bcs @end
        jsr Busy
        jsr Make
        bne @fail
        jsr MountIt
        bne @fail
        lda #$80
        sta mounted
@copy:  jsr Home                ; src = home + "fonts/" + cvtName
        ldx #0
:       lda CvtDir,x
        beq :+
        sta src,y
        iny
        inx
        bne :-
:       ldx #0
:       lda cvtName,x
        sta src,y
        beq :+
        iny
        inx
        bne :-
:       lda #<src
        sta r0L
        lda #>src
        sta r0H
        lda #<letter
        sta r1L
        lda #>letter
        sta r1H
        lda #0
        sta r2L
        lda #FE_COPY
        jsr FileEngine
        txa
        beq @done
        cmp #FILE_EXISTS
        beq @ok
        sec
        rts
@done:  lda #$80
        sta acted
@ok:    clc
@end:   rts
@fail:  jsr Idle                ; (the error not shown: the start
        sec                     ; goes on, the next one tries again)
        rts

; Home: src = fPath without "FONTS.DNP" (the home folder, its slash);
; Y = its length.
Home:   ldy #0
:       lda fPath,y
        sta src,y
        beq :+
        iny
        bne :-
:       tya
        sec
        sbc #9                  ; (strlen "FONTS.DNP")
        tay
        rts

; Make: FONTS.DNP made (8 tracks, "System fonts") when missing; Z set
; when it is there, X the error otherwise.
Make:   lda #<fPath
        ldx #>fPath
        jsr Stat
        beq @end
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
        txa
@end:   rts

; Out (uninstall): the font deleted from FONTS.DNP (mounted on letter for
; it) and its CVT from GEOULTRA/fonts; status its error, acted $80 when
; done. No FONTS.DNP: nothing (status 0, acted 0).
Out:    lda #<fPath
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
        jsr Fin
        bit acted
        bpl @end
        jmp Cvt                 ; (none: fine)
@end:   rts

; Fin: X (the change's error) into status, FONTS.DNP unmounted (written
; back: its error into status when the change worked); acted $80 when
; both worked.
Fin:    stx status
        jsr UMount
        lda status
        bne :+
        stx status
        txa
        bne :+
        lda #$80
        sta acted
:       rts

; In (install): FONTS.DNP made when missing (8 tracks), mounted on letter,
; the font (path/name) copied into it, unmounted; status, acted as Out.
In:     jsr Make
        stx status
        bne @end
        jsr MountIt
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
        jmp Fin
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
@ok:    lda fPath               ; (an empty home: no Ultimate, VICE)
        cmp #'/'
        bne :+
        clc
        rts
:       sec
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
:       lda entryName,x         ; (a GEOS name: 16 characters at most,
        sta src,y               ; from a GEOS directory)
        beq :+
        iny
        inx
        bne :-
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
        bne :-
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
        .byte DBVARSTR, TXT_LN_X, TXT_LN_2_Y + 6, line2
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

letter:         .byte "/x", 0   ; the free drive letter's path
status:         .byte 0
mounted:        .byte 0         ; $80: FONTS.DNP on letter (the import)
handle:         .byte 0         ; the fonts folder's (FE_OPENDIR)
cvtName:        .res 61         ; FE_READDIR's name (its long names)
FPath:          .byte "/f/"
FromDir:        .byte "Fonts from GEOULTRA/fonts", 0
acted:          .byte 0         ; $80: a font installed or uninstalled
fPath:          .res 64         ; FONTS.DNP's path, then its CVT's (a home of
                                ; up to 31, "fonts/", 16, ".cvt", 0: 58)
src:            .res 63 + 18    ; (a path, "/", a GEOS name)
info:           .res 16         ; (FE_STAT's info block)
        .endscope
Ov_FontAct = FontScope::Act
Ov_FontImport = FontScope::Import
