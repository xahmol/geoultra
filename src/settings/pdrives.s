; GeoUltra Settings: the Drives page (overlay 7, ovl.s; docs/design/SETTINGS.md
; the user's decisions of 2026-11-14). Three views on one page:
;
; - the drives: a row per drive A-D: its image's name, "choose" and
;   "none" (unmount, asked first); for a mounted one "long names on/off"
;   (FE_MOUNTINFO with r1 = 0) and, for a DNP, its tracks [-] n [+] with
;   "resize" (FE_MOUNT with ",tracks=N": written back, loaded again);
;   "new image" below;
; - a browser of the Ultimate's folders for "choose": the folder's
;   subfolders and disk images, ".." up, starting in the drive's image's
;   folder (else GEOULTRA); an image chosen is mounted at once (FE_MOUNT,
;   MOUNTS.INI written by the engine);
; - a form for a new, empty image (FE_MKIMG): Type [-] [+], a DNP's
;   Tracks [-] [+], the name (a box that opens the text dialog), made in
;   the browser's last folder, then offered for the first empty drive.
;
; Changes take effect at once through the file engine; nothing waits for
; Save. Own design and code.

        .include "geos.inc"
        .include "engine.inc"
        .include "settings.inc"

        .import ButtonDraw, OnButton, FileEngine, Ask2, DrawPage
        .import bpath, tpath, kinds, names ; (settings.s: in the core, for room)
        .export Ov_DriveDraw, Ov_DrivePress

        .segment "ZEROPAGE"

dAsk:           .res 2          ; a question's text (DBVARSTR)
dp:             .res 2          ; a name in the list being walked

        .segment "OV7"

; Ov_DriveDraw: the view in use drawn (the page area is clear).
Ov_DriveDraw:
        lda mode
        cmp #M_BROWSE
        bne :+
        jmp BrowseDraw
:       cmp #M_FORM
        bne RowsDraw
        jmp FormDraw

; Ov_DrivePress: a click in the view in use.
Ov_DrivePress:
        lda mode
        cmp #M_BROWSE
        bne :+
        jmp BrowsePress
:       cmp #M_FORM
        beq :+
        jmp RowsPress
:       jmp FormPress

; ======================================================================
; The drives' rows

; RowsDraw: for each drive its letter, its image's name (or "none
; mounted"), its buttons; "new image" below.
RowsDraw:
        ldx #3
@d:     stx drv
        jsr Info
        jsr RowDraw
        ldx drv
        dex
        bpl @d
        lda #B_NEW
        jmp BtnDraw

; RowDraw: drive drv's row (Info done).
RowDraw:
        jsr RowY
        lda drv                 ; its letter, bold
        clc
        adc #'A'
        sta letter
        lda #<LetterT
        ldx #>LetterT
        ldy #<LETTER_X
        jsr TextAt
        lda dType
        bne :+
        lda #<NoneT
        ldx #>NoneT
        ldy #<NAME_X
        jsr TextAt
        lda #B_CHOOSE
        jmp BtnDraw
:       jsr FileName            ; its image's file name, cut to fit
        lda #<shown
        ldx #>shown
        ldy #<NAME_X
        jsr TextAt
        lda #B_CHOOSE
        jsr BtnDraw
        lda #B_NONE
        jsr BtnDraw
        lda dFlags              ; line 2: long names, a DNP's tracks
        and #F_NOLONG
        beq :+
        lda #B_LONGOFF
        .byte $2C               ; (bit abs: skips the next lda)
:       lda #B_LONGON
        jsr BtnDraw
        lda dType
        cmp #DRV_NATIVE
        bne @end
        lda #<TracksT
        ldx #>TracksT
        ldy #<TRACKS_X
        jsr Text2
        lda #B_TDN
        jsr BtnDraw
        lda #B_TUP
        jsr BtnDraw
        lda #B_RESIZE
        jsr BtnDraw
        jmp WantDraw
@end:   rts

; WantDraw: drive drv's wanted tracks between [-] and [+].
WantDraw:
        jsr RowY
        lda #0
        jsr SetPattern
        lda rowY
        clc
        adc #LINE2 - 9
        sta r2L
        adc #11
        sta r2H
        lda #<WANT_X
        sta r3L
        lda #>WANT_X
        sta r3H
        lda #<(TUP_X - 2)
        sta r4L
        lda #>(TUP_X - 2)
        sta r4H
        jsr Rectangle
        ldx drv
        lda want,x
        jsr Number
        lda #<num
        ldx #>num
        ldy #<WANT_X + 1
        jmp Text2

; RowsPress: a click on a row's button or "new image".
RowsPress:
        lda #B_NEW
        jsr BtnOn
        bcs :+
        jmp FormStart
:       ldx #3
@d:     stx drv
        jsr Info
        jsr RowY
        lda #B_CHOOSE
        jsr BtnOn
        bcs :+
        jmp BrowseStart
:       lda dType
        beq @next
        lda #B_NONE
        jsr BtnOn
        bcs :+
        jmp Unmount
:       lda #B_LONGON           ; (the same place on and off)
        jsr BtnOn
        bcs :+
        jmp Long
:       lda dType
        cmp #DRV_NATIVE
        bne @next
        lda #B_TDN
        jsr BtnOn
        bcs :+
        ldx drv
        lda want,x
        cmp #MIN_TRACKS + 1
        bcc @done
        dec want,x
        jmp WantDraw
:       lda #B_TUP
        jsr BtnOn
        bcs :+
        ldx drv
        lda want,x
        cmp #MAX_TRACKS
        bcs @done
        inc want,x
        jmp WantDraw
:       lda #B_RESIZE
        jsr BtnOn
        bcs @next
        jmp Resize
@next:  ldx drv
        dex
        bpl @d
@done:  rts

; Info: drive drv's dType (DRV_*, 0: none), dTracks, dFlags, its image's
; path in ipath (FE_MOUNTINFO); want[drv] = its tracks when not set yet.
Info:   jsr DrvPath
        lda #<ipath
        sta r1L
        lda #>ipath
        sta r1H
        lda #FE_MOUNTINFO
        jsr FileEngine
        lda #0
        cpx #0
        bne :+
        lda r2L
:       sta dType
        lda r3L
        sta dTracks
        lda r3H
        sta dFlags
        ldx drv
        lda want,x
        bne :+
        lda dTracks
        sta want,x
:       rts

; DrvPath: r0 = "/a" + drv.
DrvPath:
        lda drv
        clc
        adc #'a'
        sta drvPath + 1
        lda #<drvPath
        sta r0L
        lda #>drvPath
        sta r0H
        rts

; FileName: shown = ipath's last part, at most SHOWN_MAX characters.
FileName:
        ldx #0                  ; after the last "/"
        ldy #0
@find:  lda ipath,x
        beq @copy
        inx
        cmp #'/'
        bne @find
        txa
        tay
        jmp @find
@copy:  ldx #0
@c:     lda ipath,y
        sta shown,x
        beq @end
        iny
        inx
        cpx #SHOWN_MAX
        bcc @c
        lda #0
        sta shown,x
@end:   rts

; Unmount: "Unmount drive X?" asked; Yes: FE_UMOUNT (written back first).
Unmount:
        lda drv
        clc
        adc #'A'
        sta askDrive
        lda #<AskUmount
        sta dAsk
        lda #>AskUmount
        sta dAsk+1
        lda #<UmountDlg
        ldx #>UmountDlg
        jsr Ask2
        cmp #YES
        beq :+
        jmp Redraw
:       jsr DrvPath
        lda #FE_UMOUNT
        jsr FileEngine
        jmp Done

; Long: drive drv's long names switched (on <-> off).
Long:   jsr DrvPath
        lda #0
        sta r1L
        sta r1H
        lda dFlags
        and #F_NOLONG
        eor #F_NOLONG           ; (now off: on; on: off)
        beq :+
        lda #1
:       sta r3L
        lda #FE_MOUNTINFO
        jsr FileEngine
        jmp Done

; Resize: drive drv mounted again at want[drv] tracks (FE_MOUNT with
; ",tracks=N": written back, loaded again); its long names as before.
Resize: ldx drv
        lda want,x
        cmp dTracks
        beq Redraw              ; (the same size)
        jsr PathTracks          ; tpath = ipath ",tracks=N"
        lda #<tpath
        sta r1L
        lda #>tpath
        sta r1H
        jsr Mount
        txa
        bne Done
        lda dFlags              ; long names off again (the mount
        and #F_NOLONG           ; clears it)
        beq Done
        jsr Long2
        jmp Done

; Long2: drive drv's long names off (FE_MOUNTINFO with r1 = 0).
Long2:  jsr DrvPath
        lda #0
        sta r1L
        sta r1H
        lda #1
        sta r3L
        lda #FE_MOUNTINFO
        jmp FileEngine

; PathTracks: tpath = ipath + ",tracks=" + want[drv].
PathTracks:
        ldx #0
@p:     lda ipath,x
        sta tpath,x
        beq :+
        inx
        bne @p
:       ldy #0
@t:     lda TracksOpt,y
        sta tpath,x
        beq :+
        inx
        iny
        bne @t
:       stx at
        ldx drv
        lda want,x
        jsr Number
        ldx at
        ldy #0
@n:     lda num,y
        sta tpath,x
        beq @end
        inx
        iny
        bne @n
@end:   rts

; Mount: FE_MOUNT drive drv from the path at r1. X = 0 or the error.
Mount:  jsr DrvPath
        lda #FE_MOUNT
        jmp FileEngine

; Done (X: an engine call's result): its error said, if any; the page
; drawn again (want[] read anew).
Done:   txa
        beq Redraw
        jsr Error
Redraw: lda #0
        ldx #3
@w:     sta want,x
        dex
        bpl @w
        jmp DrawPage

; RowY: rowY = drive drv's first line's baseline.
RowY:   lda drv
        asl a
        asl a
        asl a
        asl a
        asl a
        adc drv                 ; * 34 (32 + 2)
        adc drv
        adc #ROW0_Y
        sta rowY
        rts

; ======================================================================
; The browser

; BrowseStart (choose for drive drv): its image's folder, else GEOULTRA;
; the list read, the browser shown.
BrowseStart:
        lda dType
        beq @home
        ldx #$FF                ; the image's path up to its last "/"
@c:     inx
        lda ipath,x
        sta bpath,x
        bne @c
@cut:   dex
        bmi @home
        lda bpath,x
        cmp #'/'
        bne @cut
        lda #0
        sta bpath,x
        jmp @read
@home:  jsr Home
@read:  lda #M_BROWSE
        sta mode
        jsr ReadDir
        jmp DrawPage

; Home: bpath = the home folder (FE_HOME, its last "/" taken off).
Home:   lda #<bpath
        sta r1L
        lda #>bpath
        sta r1H
        lda #0
        sta bpath
        lda #FE_HOME
        jsr FileEngine
        ldx #$FF
@e:     inx
        lda bpath,x
        bne @e
        dex
        bmi @end
        lda bpath,x
        cmp #'/'
        bne @end
        lda #0
        sta bpath,x
@end:   rts

; ReadDir: names = bpath's subfolders and disk images (".." first below a
; root), count of them; top 0, nothing selected.
ReadDir:
        lda #0
        sta count
        sta top
        lda #$FF
        sta selRow
        jsr Slashes             ; below a root ("/usb0/x"): ".."
        cmp #2
        bcc :+
        lda #<DotDot
        sta r0L
        lda #>DotDot
        sta r0H
        lda #K_UDIR
        jsr AddR0
:       lda #<bpath
        sta r0L
        lda #>bpath
        sta r0H
        lda #FE_OPENDIR
        jsr FileEngine
        sta handle
        txa
        bne @end
@read:  lda count
        cmp #NAMES_MAX
        bcs @close
        lda #<info
        sta r1L
        lda #>info
        sta r1H
        lda #<ename
        sta r2L
        lda #>ename
        sta r2H
        lda #0
        sta r3L
        sta r3H
        ldy handle
        lda #FE_READDIR
        jsr FileEngine
        txa
        bne @close
        lda info                ; (FI_KIND)
        cmp #K_UDIR
        beq @add
        cmp #K_UFILE
        bne @read
        jsr IsImage
        bcs @read
        lda #K_UFILE
@add:   pha
        lda #<ename
        sta r0L
        lda #>ename
        sta r0H
        pla
        jsr AddR0
        jmp @read
@close: lda #FE_CLOSE
        ldy handle
        jsr FileEngine
@end:   rts

; Slashes: A = the "/" in bpath.
Slashes:
        ldx #0
        ldy #0
@s:     lda bpath,x
        beq @end
        inx
        cmp #'/'
        bne @s
        iny
        bne @s
@end:   tya
        rts

; AddR0: the name at r0 (kind A) as the list's next one, when it fits
; (NAME_LEN - 1 characters at most: longer ones left out).
AddR0:  ldx count
        sta kinds,x
        jsr NameAt              ; dp = names + count * NAME_LEN
        ldy #0
@c:     lda (r0),y
        sta (dp),y
        beq @ok
        iny
        cpy #NAME_LEN
        bcc @c
        rts                     ; (too long: not added)
@ok:    inc count
        rts

; NameAt: dp = the name of entry X.
NameAt: txa
        pha
        lda #<names
        sta dp
        lda #>names
        sta dp+1
@m:     dex
        bmi @end
        lda dp
        clc
        adc #NAME_LEN
        sta dp
        bcc @m
        inc dp+1
        bne @m
@end:   pla
        tax
        rts

; IsImage: C clear when ename ends in .d64, .d71, .d81 or .dnp (any
; case).
IsImage:
        ldy #$FF
@e:     iny
        lda ename,y
        bne @e
        cpy #5
        bcc @no
        lda ename-4,y
        cmp #'.'
        bne @no
        lda ename-3,y
        ora #$20
        cmp #'d'
        bne @no
        ldx #3
@k:     lda ename-2,y
        ora #$20
        cmp Ext2,x
        bne @next
        lda ename-1,y
        ora #$20
        cmp Ext3,x
        beq @yes
@next:  dex
        bpl @k
@no:    sec
        rts
@yes:   clc
        rts

; BrowseDraw: the title, the folder, the list (rows from top, the
; selected one inverted), the buttons.
BrowseDraw:
        lda drv
        clc
        adc #'A'
        sta chooseDrive
        lda #<ChooseT
        ldx #>ChooseT
        ldy #HEAD_Y
        jsr Line
        jsr PathShown
        lda #<shown
        ldx #>shown
        ldy #PATH_Y
        jsr Line
        lda #$FF                ; the list's frame
        jsr ListBox
        jsr FrameRectangle
        ldx #0
@r:     stx at
        txa
        clc
        adc top
        cmp count
        bcs @btn
        tax
        jsr NameAt
        ldy #0                  ; its name, cut, "/" after a folder
@c:     lda (dp),y
        sta shown,y
        beq :+
        iny
        cpy #LIST_CHARS
        bcc @c
:       lda kinds,x
        cmp #K_UDIR
        bne :+
        lda #'/'
        sta shown,y
        iny
:       lda #0
        sta shown,y
        lda at
        jsr RowBase
        sta r1H
        lda #<shown
        sta r0L
        lda #>shown
        sta r0H
        lda #<LIST_TEXT_X
        sta r11L
        lda #>LIST_TEXT_X
        sta r11H
        jsr PutString
        ldx at
        txa
        clc
        adc top
        cmp selRow
        bne :+
        lda at
        jsr RowInvert
:       ldx at
        inx
        cpx #LIST_ROWS
        bcc @r
@btn:   lda #B_OPEN
        jsr BtnDraw
        lda #B_CANCEL
        jsr BtnDraw
        lda #B_UP
        jsr BtnDraw
        lda #B_DOWN
        jmp BtnDraw

; BrowsePress: open, cancel, the list's [-] [+], a row (selected; again
; or open: entered or mounted).
BrowsePress:
        lda #B_CANCEL
        jsr BtnOn
        bcs :+
        jmp Back
:       lda #B_OPEN
        jsr BtnOn
        bcs :+
        jmp Act
:       lda #B_UP
        jsr BtnOn
        bcs :+
        lda top
        sec
        sbc #LIST_ROWS
        bcs @top
        lda #0
@top:   sta top
        jmp DrawPage
:       lda #B_DOWN
        jsr BtnOn
        bcs :+
        lda top
        clc
        adc #LIST_ROWS
        cmp count
        bcs @end
        sta top
        jmp DrawPage
:       jsr ListBox             ; a row?
        lda mouseYPos           ; (the list's width: the scroll buttons
        cmp r2L                 ; right of it were asked first)
        bcc @end
        cmp r2H
        bcs @end
        lda mouseYPos
        sec
        sbc #LIST_TOP + 1
        ldx #0
@div:   cmp #ROW_H
        bcc :+
        sbc #ROW_H
        inx
        bne @div
:       txa
        clc
        adc top
        cmp count
        bcs @end
        cmp selRow
        beq Act                 ; (clicked again: open)
        sta selRow
        jmp DrawPage
@end:   rts

; Act: the selected entry: a folder entered (".." up), an image mounted
; on drive drv (and back to the drives).
Act:    ldx selRow
        cpx count
        bcs @end
        jsr NameAt
        lda kinds,x
        cmp #K_UDIR
        bne @image
        ldy #0                  ; ".."?
        lda (dp),y
        cmp #'.'
        bne @into
        iny
        lda (dp),y
        cmp #'.'
        bne @into
        ldx #$FF                ; up: bpath to its last "/"
@e:     inx
        lda bpath,x
        bne @e
@cut:   dex
        lda bpath,x
        cmp #'/'
        bne @cut
        lda #0
        sta bpath,x
        jmp @read
@into:  jsr Join                ; bpath "/" name
        bcs @end
@read:  jsr ReadDir
        jmp DrawPage
@image: ldx #$FF                ; tpath = bpath "/" name
@p:     inx
        lda bpath,x
        sta tpath,x
        bne @p
        lda #'/'
        sta tpath,x
        inx
        ldy #0
@n:     lda (dp),y
        sta tpath,x
        beq :+
        inx
        iny
        cpx #PATH_MAX
        bcc @n
        lda #0
        sta tpath,x
:       lda #<tpath
        sta r1L
        lda #>tpath
        sta r1H
        jsr Mount
        stx at
        lda #M_ROWS
        sta mode
        ldx at
        jmp Done
@end:   rts

; Join: bpath "/" the name at dp; C set when it would not fit.
Join:   ldx #$FF
@e:     inx
        lda bpath,x
        bne @e
        stx at                  ; (where the "/" goes: kept on a failure)
        lda #'/'
        sta bpath,x
        inx
        ldy #0
@c:     lda (dp),y
        sta bpath,x
        beq @ok
        inx
        iny
        cpx #PATH_MAX
        bcc @c
        ldx at                  ; too long: as it was
        lda #0
        sta bpath,x
        sec
        rts
@ok:    clc
        rts

; Back: the drives' rows again.
Back:   lda #M_ROWS
        sta mode
        jmp Redraw

; PathShown: shown = bpath's last PATH_CHARS characters ("..." before).
PathShown:
        ldx #$FF
@e:     inx
        lda bpath,x
        bne @e
        txa
        sec
        sbc #PATH_CHARS
        bcs :+
        lda #0
:       tay
        ldx #0
        cpy #0
        beq @c
        lda #'.'
        sta shown
        sta shown+1
        sta shown+2
        ldx #3
@c:     lda bpath,y
        sta shown,x
        beq @end
        inx
        iny
        bne @c
@end:   rts

; ListBox: r2-r4 = the list's box.
ListBox:
        lda #LIST_TOP
        sta r2L
        lda #LIST_TOP + LIST_ROWS * ROW_H + 2
        sta r2H
        lda #<LIST_X
        sta r3L
        lda #>LIST_X
        sta r3H
        lda #<LIST_R
        sta r4L
        lda #>LIST_R
        sta r4H
        rts

; RowBase: A = row A's baseline.
RowBase:
        tax
        lda #LIST_TOP + ROW_H - 2
@m:     dex
        bmi @end
        clc
        adc #ROW_H
        bne @m
@end:   rts

; RowInvert: row A of the list inverted.
RowInvert:
        jsr RowBase
        sec
        sbc #ROW_H - 3
        sta r2L
        clc
        adc #ROW_H - 1
        sta r2H
        lda #<(LIST_X + 1)
        sta r3L
        lda #>(LIST_X + 1)
        sta r3H
        lda #<(LIST_R - 1)
        sta r4L
        lda #>(LIST_R - 1)
        sta r4H
        jmp InvertRectangle

; ======================================================================
; The new image's form

; FormStart: the form with its first type (D81), 16 tracks, no name; in
; the browser's last folder (GEOULTRA at first).
FormStart:
        lda #M_FORM
        sta mode
        lda #2
        sta fType
        lda #16
        sta fTracks
        lda #0
        sta fName
        lda bpath
        bne :+
        jsr Home
:       jmp DrawPage

; FormDraw: the title, Type, Tracks (a DNP), the name's box, the folder,
; make and cancel.
FormDraw:
        lda #<NewT
        ldx #>NewT
        ldy #HEAD_Y
        jsr Line
        lda #ROW0_Y + 8
        sta rowY
        lda #<TypeT
        ldx #>TypeT
        ldy #<LETTER_X
        jsr TextAt
        lda #B_TYDN
        jsr BtnDraw
        lda #B_TYUP
        jsr BtnDraw
        ldx fType
        lda ExtLo,x
        pha
        lda ExtHi,x
        tax
        pla
        ldy #<FORM_VAL_X
        jsr TextAt
        lda fType
        cmp #T_DNP
        bne @name
        lda #ROW0_Y + 8 + FORM_DY
        sta rowY
        lda #<TracksT
        ldx #>TracksT
        ldy #<LETTER_X
        jsr TextAt
        lda #B_FTDN
        jsr BtnDraw
        lda #B_FTUP
        jsr BtnDraw
        lda fTracks
        jsr Number
        lda #<num
        ldx #>num
        ldy #<FORM_VAL_X
        jsr TextAt
@name:  lda #ROW0_Y + 8 + 2 * FORM_DY
        sta rowY
        lda #<NameT
        ldx #>NameT
        ldy #<LETTER_X
        jsr TextAt
        lda #B_NAME
        jsr BtnDraw
        lda #<fName
        ldx #>fName
        ldy #<(FORM_BTN_X + 3)
        jsr TextAt
        lda #ROW0_Y + 8 + 3 * FORM_DY
        sta rowY
        lda #<InT
        ldx #>InT
        ldy #<LETTER_X
        jsr TextAt
        jsr PathShown
        lda #<shown
        ldx #>shown
        ldy #<(LETTER_X + 14)
        jsr TextAt
        lda #B_MAKE
        jsr BtnDraw
        lda #B_CANCEL
        jmp BtnDraw

; FormPress: the steppers, the name's box, make, cancel.
FormPress:
        lda #B_CANCEL
        jsr BtnOn
        bcs :+
        jmp Back
:       lda #ROW0_Y + 8
        sta rowY
        lda #B_TYDN
        jsr BtnOn
        bcs :+
        ldx fType
        dex
        bpl @ty
        ldx #T_DNP
@ty:    stx fType
        jmp DrawPage
:       lda #B_TYUP
        jsr BtnOn
        bcs :+
        ldx fType
        inx
        cpx #T_DNP + 1
        bcc @ty
        ldx #0
        beq @ty
:       lda #ROW0_Y + 8 + FORM_DY
        sta rowY
        lda fType
        cmp #T_DNP
        bne @name
        lda #B_FTDN
        jsr BtnOn
        bcs :+
        lda fTracks
        cmp #MIN_TRACKS + 1
        bcc @end
        dec fTracks
        jmp DrawPage
:       lda #B_FTUP
        jsr BtnOn
        bcs @name
        lda fTracks
        cmp #MAX_TRACKS
        bcs @end
        inc fTracks
        jmp DrawPage
@name:  lda #ROW0_Y + 8 + 2 * FORM_DY
        sta rowY
        lda #B_NAME
        jsr BtnOn
        bcs :+
        jmp AskName
:       lda #B_MAKE
        jsr BtnOn
        bcs @end
        jmp Make
@end:   rts

; AskName: the name typed (the text dialog; NAME_CHARS at most).
AskName:
        lda #<NameAsk
        sta dAsk
        lda #>NameAsk
        sta dAsk+1
        lda #<fName
        sta r5L
        lda #>fName
        sta r5H
        lda #<NameDlg
        ldx #>NameDlg
        jsr Ask2
        jmp DrawPage

; Make: tpath = bpath "/" name "." type; FE_MKIMG (the name as its disk
; name, a DNP's tracks); then "Mount it on drive X?" for the first empty
; drive (none: back to the drives).
Make:   lda fName
        bne :+
        jmp AskName             ; (no name yet: asked first)
:       ldx #$FF
@p:     inx
        lda bpath,x
        sta tpath,x
        bne @p
        lda #'/'
        sta tpath,x
        inx
        ldy #0
@n:     lda fName,y
        beq @dot
        sta tpath,x
        inx
        iny
        bne @n
@dot:   ldy fType
        lda #'.'
        sta tpath,x
        lda #'d'
        sta tpath+1,x
        lda Ext2,y
        sta tpath+2,x
        lda Ext3,y
        sta tpath+3,x
        lda #0
        sta tpath+4,x
        lda #<tpath
        sta r0L
        lda #>tpath
        sta r0H
        lda #<fName
        sta r1L
        lda #>fName
        sta r1H
        lda fTracks
        sta r2L
        lda #FE_MKIMG
        jsr FileEngine
        txa
        beq :+
        jmp Done
:       lda #M_ROWS
        sta mode
        ldx #0                  ; the first empty drive
@d:     stx drv
        jsr Info
        lda dType
        beq @ask
        ldx drv
        inx
        cpx #4
        bcc @d
        jmp Redraw
@ask:   lda drv
        clc
        adc #'A'
        sta mountDrive
        lda #<AskMount
        sta dAsk
        lda #>AskMount
        sta dAsk+1
        lda #<YesNoDlg
        ldx #>YesNoDlg
        jsr Ask2
        cmp #YES
        beq :+
        jmp Redraw
:       lda #<tpath
        sta r1L
        lda #>tpath
        sta r1H
        jsr Mount
        jmp Done

; ======================================================================
; Shared

; Error: X = an engine error, said in a dialog (the common ones in
; words, else its number).
Error:  txa
        ldx #ERRS - 1
@f:     cmp ErrCode,x
        beq @w
        dex
        bpl @f
        jsr Hex
        lda #<ErrNum
        ldx #>ErrNum
        bne @set
@w:     lda ErrLo,x
        pha
        lda ErrHi,x
        tax
        pla
@set:   sta dAsk
        stx dAsk+1
        lda #<OkDlg
        ldx #>OkDlg
        jmp Ask2

; Hex: A as two hex digits into errHex.
Hex:    pha
        lsr a
        lsr a
        lsr a
        lsr a
        jsr @d
        sta errHex
        pla
        and #$0F
        jsr @d
        sta errHex+1
        rts
@d:     cmp #10
        bcc :+
        adc #'A' - '0' - 10 - 1
:       adc #'0'
        rts

; Number: num = A in decimal.
Number: ldx #0
        ldy #'0' - 1            ; hundreds
@h:     iny
        sec
        sbc #100
        bcs @h
        adc #100
        cpy #'0'
        beq :+
        jsr PutY
:       ldy #'0' - 1            ; tens
@t:     iny
        sec
        sbc #10
        bcs @t
        adc #10
        cpx #0
        bne @tw
        cpy #'0'
        beq :+
@tw:    jsr PutY
:       ora #'0'
        sta num,x
        lda #0
        sta num+1,x
        rts

; PutY: Y to num + X, X on. Keeps A.
PutY:   pha
        tya
        sta num,x
        inx
        pla
        rts

; BtnDraw, BtnOn: button A of BtnDefs at rowY (its y relative to it):
; drawn; or C clear when the pointer is on it.
BtnDraw:
        jsr BtnRec
        jmp ButtonDraw
BtnOn:  jsr BtnRec
        jmp OnButton

; BtnRec: btn = button A's record (x; y = rowY + its dy, or its own y
; when its flag is 1; width; label); A/X = btn.
BtnRec: asl a
        asl a
        asl a
        tax
        lda BtnDefs,x
        sta btn
        lda BtnDefs+1,x
        sta btn+1
        lda BtnDefs+2,x
        ldy BtnDefs+6,x         ; (1: a y of its own)
        bne :+
        clc
        adc rowY
:       sta btn+2
        lda BtnDefs+3,x
        sta btn+3
        lda BtnDefs+4,x
        sta btn+4
        lda BtnDefs+5,x
        sta btn+5
        lda #<btn
        ldx #>btn
        rts

; TextAt: the text at A/X at x Y (0-255), baseline rowY. Text2: on the
; row's second line. Line: the text at A/X at LETTER_X, baseline Y.
Text2:  pha
        lda rowY
        clc
        adc #LINE2
        bne TextY
TextAt: pha
        lda rowY
TextY:  sta r1H
        pla
        sta r0L
        stx r0H
        sty r11L
        lda #0
        sta r11H
        jmp PutString
Line:   sty r1H
        sta r0L
        stx r0H
        lda #<LETTER_X
        sta r11L
        lda #0
        sta r11H
        jmp PutString

; --- data

M_ROWS          = 0
M_BROWSE        = 1
M_FORM          = 2
ROW0_Y          = 30            ; the first drive's line 1 (34 a drive)
LINE2           = 14            ; a drive's second line below its first
LETTER_X        = PAGE_LEFT + 6
NAME_X          = LETTER_X + 14
SHOWN_MAX       = 20            ; an image's name shown, at most
TRACKS_X        = NAME_X + 80
TDN_X           = TRACKS_X + 36
WANT_X          = TDN_X + 16
TUP_X           = WANT_X + 22
RESIZE_X        = TUP_X + 16
CHOOSE_X        = 232
NONE_X          = 276
NEW_Y           = 157           ; "new image", make, open, cancel: their top
MIN_TRACKS      = 2
MAX_TRACKS      = 255
HEAD_Y         = 26
PATH_Y          = 38
PATH_CHARS      = 30
LIST_X          = LETTER_X
LIST_R          = 296
LIST_TOP        = 42
ROW_H           = 11
LIST_ROWS       = 10
LIST_CHARS      = 30
LIST_TEXT_X     = LIST_X + 4
NAMES_MAX       = 24
NAME_LEN        = 48
PATH_MAX        = 126
FORM_DY         = 18
FORM_VAL_X      = LETTER_X + 70
FORM_BTN_X      = LETTER_X + 52
FORM_PLUS_X     = FORM_VAL_X + 80
NAME_CHARS      = 12
T_DNP           = 3
K_UDIR          = 6
K_UFILE         = 5
F_NOLONG        = $10           ; (drvflags.inc)

; The buttons: x (word), dy below rowY (or its own y), width, label (a
; word), 1 for its own y (a word).
B_CHOOSE        = 0
B_NONE          = 1
B_LONGON        = 2
B_LONGOFF       = 3
B_TDN           = 4
B_TUP           = 5
B_RESIZE        = 6
B_NEW           = 7
B_OPEN          = 8
B_CANCEL        = 9
B_UP            = 10
B_DOWN          = 11
B_TYDN          = 12
B_TYUP          = 13
B_FTDN          = 14
B_FTUP          = 15
B_NAME          = 16
B_MAKE          = 17
BtnDefs:
        .word CHOOSE_X
        .byte <-9, 40
        .word ChooseB, 0
        .word NONE_X
        .byte <-9, 30
        .word NoneB, 0
        .word NAME_X
        .byte LINE2 - 9, 76
        .word LongOnB, 0
        .word NAME_X
        .byte LINE2 - 9, 76
        .word LongOffB, 0
        .word TDN_X
        .byte LINE2 - 9, 14
        .word MinusB, 0
        .word TUP_X
        .byte LINE2 - 9, 14
        .word PlusB, 0
        .word RESIZE_X
        .byte LINE2 - 9, 36
        .word ResizeB, 0
        .word NAME_X
        .byte NEW_Y, 60
        .word NewB, 1
        .word NAME_X
        .byte NEW_Y, 40
        .word OpenB, 1
        .word NAME_X + 48
        .byte NEW_Y, 44
        .word CancelB, 1
        .word LIST_R + 4
        .byte LIST_TOP + 1, 14
        .word MinusB, 1
        .word LIST_R + 4
        .byte LIST_TOP + LIST_ROWS * ROW_H - 11, 14
        .word PlusB, 1
        .word FORM_BTN_X
        .byte <-9, 14
        .word MinusB, 0
        .word FORM_PLUS_X
        .byte <-9, 14
        .word PlusB, 0
        .word FORM_BTN_X
        .byte <-9, 14
        .word MinusB, 0
        .word FORM_PLUS_X
        .byte <-9, 14
        .word PlusB, 0
        .word FORM_BTN_X
        .byte <-9, 100
        .word Empty, 0
        .word NAME_X
        .byte NEW_Y, 40
        .word MakeB, 1
        .assert * - BtnDefs = 8 * 18, error, "BtnDefs: 8 bytes a button"
        .assert RESIZE_X + 36 < 318 && FORM_PLUS_X + 14 < 318, error, "the buttons fit the page"

ChooseB:        .byte "choose", 0
NoneB:          .byte "none", 0
LongOnB:        .byte "long names on", 0
LongOffB:       .byte "long names off", 0
MinusB:         .byte "-", 0
PlusB:          .byte "+", 0
ResizeB:        .byte "resize", 0
NewB:           .byte "new image", 0
OpenB:          .byte "open", 0
CancelB:        .byte "cancel", 0
MakeB:          .byte "make", 0
Empty:          .byte 0
LetterT:        .byte BOLDON
letter:         .byte "A", PLAINTEXT, 0
NoneT:          .byte "(none)", 0
TracksT:        .byte "tracks", 0
ChooseT:        .byte BOLDON, "Drive "
chooseDrive:    .byte "A: an image", PLAINTEXT, 0
NewT:           .byte BOLDON, "A new disk image", PLAINTEXT, 0
TypeT:          .byte "Type", 0
NameT:          .byte "Name", 0
InT:            .byte "In", 0
DotDot:         .byte "..", 0
TracksOpt:      .byte ",tracks=", 0
drvPath:        .byte "/a", 0
Ext2:           .byte "678n"
Ext3:           .byte "411p"
ExtLo:          .byte <ExtD64, <ExtD71, <ExtD81, <ExtDnp
ExtHi:          .byte >ExtD64, >ExtD71, >ExtD81, >ExtDnp
ExtD64:         .byte "D64 (1541)", 0
ExtD71:         .byte "D71 (1571)", 0
ExtD81:         .byte "D81 (1581)", 0
ExtDnp:         .byte "DNP (native)", 0

AskUmount:      .byte "Unmount drive "
askDrive:       .byte "A? Its changes are", 0
AskMount:       .byte "Mount it on drive "
mountDrive:     .byte "A?", 0
NameAsk:        .byte "The new image's name:", 0
ChangesT:       .byte "written back first.", 0
YesNoDlg:       .byte DEF_DB_POS | 1
                .byte DBVARSTR, TXT_LN_X, TXT_LN_1_Y + 6, dAsk
                .byte YES, 1, DBI_Y_2
                .byte NO, DBI_X_2, DBI_Y_2
                .byte 0
UmountDlg:      .byte DEF_DB_POS | 1
                .byte DBVARSTR, TXT_LN_X, TXT_LN_1_Y + 6, dAsk
                .byte DBTXTSTR, TXT_LN_X, TXT_LN_2_Y + 6
                .word ChangesT
                .byte YES, 1, DBI_Y_2
                .byte NO, DBI_X_2, DBI_Y_2
                .byte 0
OkDlg:          .byte DEF_DB_POS | 1
                .byte DBVARSTR, TXT_LN_X, TXT_LN_1_Y + 6, dAsk
                .byte OK, DBI_X_2, DBI_Y_2
                .byte 0
NameDlg:        .byte DEF_DB_POS | 1
                .byte DBVARSTR, TXT_LN_X, TXT_LN_1_Y + 6, dAsk
                .byte DBGETSTRING, TXT_LN_X, TXT_LN_2_Y, r5, NAME_CHARS
                .byte OK, 1, DBI_Y_2
                .byte CANCEL, DBI_X_2, DBI_Y_2
                .byte 0
ERRS            = 5
ErrCode:        .byte INSUFF_SPACE, FE_NOT_SUPPORTED, FILE_EXISTS, FE_ULTIMATE, FE_MOUNTED
ErrLo:          .byte <ENoRoom, <ESize, <EExists, <EUlt, <EMounted
ErrHi:          .byte >ENoRoom, >ESize, >EExists, >EUlt, >EMounted
ENoRoom:        .byte "Not enough free REU for it.", 0
ESize:          .byte "Files lie beyond that size.", 0
EExists:        .byte "A file of that name is there.", 0
EUlt:           .byte "The Ultimate refused it.", 0
EMounted:       .byte "Another drive has that image.", 0
ErrNum:         .byte "It did not work: error $"
errHex:         .byte "00", 0

mode:           .byte M_ROWS
want:           .byte 0, 0, 0, 0 ; each drive's tracks wanted (0: its own)
drv:            .byte 0
at:             .byte 0
rowY:           .byte 0
dType:          .byte 0
dTracks:        .byte 0
dFlags:         .byte 0
handle:         .byte 0
count:          .byte 0
top:            .byte 0
selRow:         .byte $FF
fType:          .byte 2
fTracks:        .byte 16
fName:          .res NAME_CHARS + 1
btn:            .res 6
num:            .res 4
info:           .res 16
shown:          .res 34
ename:          .res 61
ipath:          .res 64
