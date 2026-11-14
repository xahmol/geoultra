; GeoUltra Settings: the Start page (overlay 8, ovl.s; the user's
; decisions of 2026-11-14, docs/DESIGN.md): the auto-exec files
; the cold start runs, in order: SETTINGS.INI [system] autoexec=/a/NAME
; lines (a path with its drive and folder; the kernal's autoexec.s reads
; them). A list (AUTO_MAX at most) with add, remove, up and down; add
; opens a browser of the GEOS drives (/a ... /e, their folders and their
; AUTO_EXEC files), a file chosen added at the list's end. Written with
; OK or Save, as the other pages. Own design and code.

        .include "geos.inc"
        .include "engine.inc"
        .include "settings.inc"

        .import ButtonDraw, OnButton, FileEngine, DrawPage
        .import IniFind, IniSet, IniDel, iniSkip, dirty, NoRoom
        .import bpath, tpath, kinds, names ; (settings.s: the core's buffers)
        .export Ov_StartDraw, Ov_StartPress

        .segment "ZEROPAGE"

sp:             .res 2          ; a name in the browser's list

        .segment "OV8"

; Ov_StartDraw: the list, or the browser while one is chosen.
Ov_StartDraw:
        lda mode
        beq ListDraw
        jmp BrowseDraw

; Ov_StartPress: a click in the view in use.
Ov_StartPress:
        lda mode
        beq ListPress
        jmp BrowsePress

; ======================================================================
; The list

; ListDraw: the title, the note, the list's box with the paths (the
; selected one inverted), the buttons.
ListDraw:
        lda #<TitleT
        ldx #>TitleT
        ldy #HEAD_Y
        jsr Line
        lda #<NoteT
        ldx #>NoteT
        ldy #NOTE_Y
        jsr Line
        jsr ListBox
        lda #$FF
        jsr FrameRectangle
        ldx #0
@r:     stx at
        txa
        jsr Entry               ; (C set: none)
        bcs @btn
        lda at
        jsr RowBase
        sta r1H
        lda #<shown
        sta r0L
        lda #>shown
        sta r0H
        lda #<TEXT_X
        sta r11L
        lda #>TEXT_X
        sta r11H
        jsr PutString
        lda at
        cmp sel
        bne :+
        jsr RowInvert
:       ldx at
        inx
        cpx #AUTO_MAX
        bcc @r
@btn:   stx count               ; (the entries)
        lda #B_ADD
        jsr BtnDraw
        lda #B_REMOVE
        jsr BtnDraw
        lda #B_UP
        jsr BtnDraw
        lda #B_DOWN
        jmp BtnDraw

; ListPress: add, remove, up, down; a row selected (again: not).
ListPress:
        jsr Count
        lda #B_ADD
        jsr BtnOn
        bcs :+
        lda count
        cmp #AUTO_MAX
        bcs @end
        jmp BrowseStart
:       lda #B_REMOVE
        jsr BtnOn
        bcs :+
        jmp Remove
:       lda #B_UP
        jsr BtnOn
        bcs :+
        lda sel
        beq @end                ; (the first: stays)
        cmp count
        bcs @end
        jmp Up
:       lda #B_DOWN
        jsr BtnOn
        bcs :+
        lda sel
        clc
        adc #1
        cmp count
        bcs @end                ; (the last: stays)
        lda sel
        jmp Down
:       jsr ListBox             ; a row?
        lda mouseYPos
        cmp r2L
        bcc @end
        cmp r2H
        bcs @end
        sec
        sbc #LIST_TOP + 1
        ldx #0
@div:   cmp #ROW_H
        bcc :+
        sbc #ROW_H
        inx
        bne @div
:       cpx count
        bcs @end
        cpx sel
        bne :+
        ldx #$FF
:       stx sel
        jmp DrawPage
@end:   rts

; Count: count = the autoexec= lines (AUTO_MAX at most).
Count:  ldx #0
@c:     stx count
        txa
        jsr Find
        bcs @end
        ldx count
        inx
        cpx #AUTO_MAX
        bcc @c
        stx count
@end:   lda #0
        sta iniSkip
        rts

; Entry: shown = autoexec= line A's path (cut to LIST_CHARS); C set when
; there is none. iniSkip 0 again.
Entry:  jsr Find
        bcs @none
        cmp #LIST_CHARS
        bcc :+
        lda #LIST_CHARS
:       tay
        lda #0
        sta shown,y
@c:     dey
        bmi @ok
        lda (r2),y
        sta shown,y
        jmp @c
@ok:    lda #0
        sta iniSkip
        clc
        rts
@none:  lda #0
        sta iniSkip
        sec
        rts

; Find: IniFind for autoexec= line A (r2 its value, A its length; C set:
; none). Leaves iniSkip = A.
Find:   sta iniSkip
        jsr Key
        jmp IniFind

; Key: r0 = "system", r1 = "autoexec".
Key:    lda #<SSystem
        sta r0L
        lda #>SSystem
        sta r0H
        lda #<KAuto
        sta r1L
        lda #>KAuto
        sta r1H
        rts

; Remove: the selected line taken out.
Remove: lda sel
        cmp count
        bcs @end
        sta iniSkip
        jsr Key
        jsr IniDel
        lda #0
        sta iniSkip
        lda #$FF
        sta sel
        jmp Changed
@end:   rts

; Up, Down: the selected line (A) swapped with the one before (Up) or
; after it (Down); the selection follows it.
Up:     sec
        sbc #1
Down:   sta at                  ; lines at and at + 1 swapped
        jsr Find                ; the first's value to tpath
        bcs @end
        jsr Copy
        lda at
        clc
        adc #1
        jsr Find                ; the second's to bpath (the browser's
        bcs @end                ; buffer: free here)
        tay                     ; (A its length)
        lda #0
        sta bpath,y
@b:     dey
        bmi :+
        lda (r2),y
        sta bpath,y
        jmp @b
:
        lda at                  ; line at = the second's
        sta iniSkip
        jsr Key
        lda #<bpath
        sta r2L
        lda #>bpath
        sta r2H
        jsr IniSet
        bcs @room
        lda at
        clc
        adc #1
        sta iniSkip             ; line at + 1 = the first's
        jsr Key
        lda #<tpath
        sta r2L
        lda #>tpath
        sta r2H
        jsr IniSet
        bcs @room
        lda sel                 ; the selection with its line
        cmp at
        bne :+
        inc sel
        jmp Changed
:       dec sel
        jmp Changed
@room:  lda #0
        sta iniSkip
        jmp NoRoom
@end:   lda #0
        sta iniSkip
        rts

; Copy: tpath = the value at r2 (A its length).
Copy:   sta vlen
        tay
        lda #0
        sta tpath,y
@c:     dey
        bmi @end
        lda (r2),y
        sta tpath,y
        jmp @c
@end:   rts

; Changed: dirty, iniSkip 0, the page drawn again.
Changed:
        lda #0
        sta iniSkip
        lda #1
        sta dirty
        jmp DrawPage

; ======================================================================
; The browser: the GEOS drives, their folders and AUTO_EXEC files

; BrowseStart: from "/" (the drives).
BrowseStart:
        lda #'/'
        sta bpath
        lda #0
        sta bpath+1
        lda #1
        sta mode
        jsr ReadDir
        jmp DrawPage

; ReadDir: names = bpath's drives (A-E), folders and AUTO_EXEC files
; (".." first below "/"), bcount of them; top 0, nothing chosen.
ReadDir:
        lda #0
        sta bcount
        sta top
        lda #$FF
        sta bsel
        lda bpath+1             ; below "/": ".."
        beq :+
        lda #<DotDot
        sta r0L
        lda #>DotDot
        sta r0H
        lda #FE_K_FOLDER
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
@read:  lda bcount
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
        lda info + FI_KIND
        cmp #FE_K_DRIVE
        beq @add
        cmp #FE_K_FOLDER
        beq @add
        cmp #FE_K_GEOS
        bne @read
        lda info + FI_GTYPE
        cmp #AUTO_EXEC
        bne @read
        lda #FE_K_GEOS
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

; AddR0: the name at r0 (kind A) as the browser's next entry when it
; fits (NAME_LEN - 1 characters).
AddR0:  ldx bcount
        sta kinds,x
        jsr NameAt
        ldy #0
@c:     lda (r0),y
        sta (sp),y
        beq @ok
        iny
        cpy #NAME_LEN
        bcc @c
        rts
@ok:    inc bcount
        rts

; NameAt: sp = the browser's name X (X kept).
NameAt: txa
        pha
        lda #<names
        sta sp
        lda #>names
        sta sp+1
@m:     dex
        bmi @end
        lda sp
        clc
        adc #NAME_LEN
        sta sp
        bcc @m
        inc sp+1
        bne @m
@end:   pla
        tax
        rts

; BrowseDraw: the title, the folder, the entries (from top; a folder or
; drive with "/" after it), the chosen one inverted, the buttons.
BrowseDraw:
        lda #<ChooseT
        ldx #>ChooseT
        ldy #HEAD_Y
        jsr Line
        lda #<bpath
        ldx #>bpath
        ldy #NOTE_Y
        jsr Line
        jsr ListBox
        lda #$FF
        jsr FrameRectangle
        ldx #0
@r:     stx at
        txa
        clc
        adc top
        cmp bcount
        bcs @btn
        tax
        jsr NameAt
        ldy #0
@c:     lda (sp),y
        sta shown,y
        beq :+
        iny
        cpy #LIST_CHARS
        bcc @c
:       lda kinds,x
        cmp #FE_K_GEOS
        beq :+
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
        lda #<TEXT_X
        sta r11L
        lda #>TEXT_X
        sta r11H
        jsr PutString
        ldx at
        txa
        clc
        adc top
        cmp bsel
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
        lda #B_PGUP
        jsr BtnDraw
        lda #B_PGDN
        jmp BtnDraw

; BrowsePress: open, cancel, page up, down, an entry (chosen; again or
; open: a drive or folder entered, ".." up, a file added).
BrowsePress:
        lda #B_CANCEL
        jsr BtnOn
        bcs :+
        jmp Back
:       lda #B_OPEN
        jsr BtnOn
        bcs :+
        jmp Act
:       lda #B_PGUP
        jsr BtnOn
        bcs :+
        lda top
        sec
        sbc #LIST_ROWS
        bcs @top
        lda #0
@top:   sta top
        jmp DrawPage
:       lda #B_PGDN
        jsr BtnOn
        bcs :+
        lda top
        clc
        adc #LIST_ROWS
        cmp bcount
        bcs @end
        sta top
        jmp DrawPage
:       jsr ListBox
        lda mouseYPos
        cmp r2L
        bcc @end
        cmp r2H
        bcs @end
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
        cmp bcount
        bcs @end
        cmp bsel
        beq Act
        sta bsel
        jmp DrawPage
@end:   rts

; Act: the chosen entry: ".." up, a drive or folder entered, a file's
; path added as the list's last autoexec= line (back to the list).
Act:    ldx bsel
        cpx bcount
        bcs @end
        jsr NameAt
        lda kinds,x
        cmp #FE_K_GEOS
        beq @file
        ldy #0
        lda (sp),y
        cmp #'.'
        bne @into
        iny
        lda (sp),y
        cmp #'.'
        bne @into
        ldx #$FF                ; up: bpath to its last "/" ("/" stays)
@e:     inx
        lda bpath,x
        bne @e
@cut:   dex
        lda bpath,x
        cmp #'/'
        bne @cut
        txa
        bne :+
        inx                     ; ("/a" up: "/")
:       lda #0
        sta bpath,x
        jmp @read
@into:  jsr Join
        bcs @end
@read:  jsr ReadDir
        jmp DrawPage
@file:  jsr Join                ; bpath "/" name: the path
        bcs @end
        lda #$FF                ; a new autoexec= line (after the others)
        sta iniSkip
        jsr Key
        lda #<bpath
        sta r2L
        lda #>bpath
        sta r2H
        jsr IniSet
        bcc :+
        lda #0
        sta iniSkip
        jmp NoRoom
:       lda #0
        sta mode
        lda #$FF
        sta sel
        jmp Changed
@end:   rts

; Join: bpath "/" the name at sp (at "/": no second "/"); C set when it
; would not fit AUTO_LEN - 1 (the kernal's list).
Join:   ldx #$FF
@e:     inx
        lda bpath,x
        bne @e
        stx at
        cpx #1                  ; ("/": the name right after it)
        beq :+
        lda #'/'
        sta bpath,x
        inx
:       ldy #0
@c:     lda (sp),y
        sta bpath,x
        beq @ok
        inx
        iny
        cpx #AUTO_LEN - 1
        bcc @c
        ldx at
        lda #0
        sta bpath,x
        sec
        rts
@ok:    clc
        rts

; Back: the list again.
Back:   lda #0
        sta mode
        jmp DrawPage

; ======================================================================
; Shared

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

; RowInvert: row A inverted.
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

; BtnDraw, BtnOn: button A of BtnDefs: drawn; C clear when the pointer
; is on it.
BtnDraw:
        jsr BtnAt
        jmp ButtonDraw
BtnOn:  jsr BtnAt
        jmp OnButton
BtnAt:  asl a                   ; (records of 6 bytes)
        sta tmp
        asl a
        adc tmp
        clc
        adc #<BtnDefs
        tay
        lda #>BtnDefs
        adc #0
        tax
        tya
        rts

; Line: the text at A/X at LIST_X, baseline Y.
Line:   sty r1H
        sta r0L
        stx r0H
        lda #<LIST_X
        sta r11L
        lda #>LIST_X
        sta r11H
        jmp PutString

; --- data

HEAD_Y          = 26
NOTE_Y          = 37
LIST_X          = PAGE_LEFT + 6
LIST_R          = 300
LIST_TOP        = 42
ROW_H           = 11
LIST_ROWS       = 10
LIST_CHARS      = 30
TEXT_X          = LIST_X + 4
AUTO_MAX        = 8             ; (the kernal's autoexec.s)
AUTO_LEN        = 64
NAMES_MAX       = 24            ; (the core's names: 24 of 48)
NAME_LEN        = 48
BTN_Y           = 157
B_ADD           = 0
B_REMOVE        = 1
B_UP            = 2
B_DOWN          = 3
B_OPEN          = 4
B_CANCEL        = 5
B_PGUP          = 6
B_PGDN          = 7
BtnDefs:
        .word LIST_X
        .byte BTN_Y, 30
        .word AddB
        .word LIST_X + 36
        .byte BTN_Y, 46
        .word RemoveB
        .word LIST_X + 88
        .byte BTN_Y, 24
        .word UpB
        .word LIST_X + 118
        .byte BTN_Y, 38
        .word DownB
        .word LIST_X
        .byte BTN_Y, 40
        .word OpenB
        .word LIST_X + 46
        .byte BTN_Y, 44
        .word CancelB
        .word LIST_R + 4
        .byte LIST_TOP + 1, 14
        .word MinusB
        .word LIST_R + 4
        .byte LIST_TOP + LIST_ROWS * ROW_H - 11, 14
        .word PlusB

TitleT:         .byte BOLDON, "Run at the start", PLAINTEXT, 0
NoteT:          .byte "Auto-exec files, in order; SHIFT skips", 0
ChooseT:        .byte BOLDON, "An auto-exec file", PLAINTEXT, 0
AddB:           .byte "add", 0
RemoveB:        .byte "remove", 0
UpB:            .byte "up", 0
DownB:          .byte "down", 0
OpenB:          .byte "open", 0
CancelB:        .byte "cancel", 0
MinusB:         .byte "-", 0
PlusB:          .byte "+", 0
SSystem:        .byte "system", 0
KAuto:          .byte "autoexec", 0
DotDot:         .byte "..", 0

mode:           .byte 0         ; 0 the list, 1 the browser
sel:            .byte $FF       ; the list's selected line
count:          .byte 0
at:             .byte 0
tmp:            .byte 0
vlen:           .byte 0
handle:         .byte 0
bcount:         .byte 0
bsel:           .byte $FF
top:            .byte 0
info:           .res 16
shown:          .res LIST_CHARS + 2
ename:          .res 61
