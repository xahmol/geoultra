; GeoUltra Desktop: disk images (docs/DESKTOP.md, step D6). Opening a
; disk image on the Ultimate (.d64, .d71, .d81, .dnp) asks for a drive:
; a dialog with a button per letter A-D, next to each the image mounted
; there now or "free" (free letters offered too: user, 2026-11-06); the
; choice mounts it (FE_MOUNT: the old image written back first,
; MOUNTS.INI written anew), then the list shows that drive's root and
; the sidebar its disk name. Unmount (user, 2026-11-06): an eject icon at
; the right end of each sidebar drive line that holds an image (drawn by
; desktop.s through HasImage); a click on it asks, then FE_UMOUNT.
; Errors are shown (errors.s, Error) and change nothing. Mount and
; Eject live in overlay 3 (ovl.s); IsImage, HasImage,
; Info, Letter and the eject icon in the core (the list and the sidebar
; call them while drawing). Own code.

        .include "geos.inc"
        .include "desktop.inc"

        .import FileEngine, Into, Drive, ListRead, ListDraw, SideRedraw
        .import Error, Append, full, entryName, path   ; (errors.s, actions.s)
        .import Busy, Idle
        .import Dialog
        .export Ov_Mount, Ov_Eject, HasImage, EjectIcon, IsImage
Ov_Mount = Mount                ; (ovl.s: the stubs Mount and Eject)
Ov_Eject = Eject

DRIVES          = 4             ; A-D (E is the system drive: no image)
LINE_LEN        = 12            ; a drive's line in the dialog: 11
                                ; characters (clear of CANCEL) and the zero
MINFO_LEN       = 64            ; FE_MOUNTINFO's buffer
ROW0            = 20            ; the dialog's first drive button's top
ROW_STEP        = 18            ; buttons 16 high, 2 apart
TEXT_X          = 64            ; a line's x, right of its button
TEXT_DY         = 11            ; its baseline below the button's top

        .segment "OV3"

; Mount: entryName (a file in the current Ultimate folder) mounted on
; the drive asked for, when it is a disk image; else nothing.
Mount:  jsr IsImage
        bcs @end
        ldy #0                  ; full = path "/" entryName (actions.s:
@p:     lda path,y              ; Append bounds it; the engine refuses a
        sta full,y              ; path longer than it takes)
        beq @join
        iny
        bne @p
@join:  jsr Append
        ldx #0                  ; each drive's line
@line:  stx drv
        jsr Lines
        ldx drv
        inx
        cpx #DRIVES
        bcc @line
        lda #<mountDlg
        sta r0L
        lda #>mountDlg
        sta r0H
        jsr Dialog
        lda r0L
        cmp #OK                 ; (a drive button ends it with OK)
        bne @end
        lda choice
        jsr Letter
        lda #<full
        sta r1L
        lda #>full
        sta r1H
        lda #FE_MOUNT
        jsr Busy                ; (the image loads: a moment)
        jsr FileEngine
        jsr Idle
        txa
        beq :+
        jmp Error               ; (entryName: the image)
:       jsr SideRedraw          ; its disk's name in the sidebar
        lda #<drivePath         ; the list at the drive's root
        ldx #>drivePath
        jmp Into
@end:   rts

        .segment "CODE"

; IsImage: C clear when entryName ends in .d64, .d71, .d81 or .dnp (any
; case).
IsImage:
        ldy #0
@len:   lda entryName,y
        beq @ext
        iny
        bne @len
@ext:   cpy #5                  ; at least "x.d64"
        bcc @no
        lda entryName-4,y
        cmp #'.'
        bne @no
        ldx #0                  ; each extension in Exts
@try:   lda entryName-3,y
        ora #$20                ; (lower case; digits keep their bit 5)
        cmp Exts,x
        bne @next
        lda entryName-2,y
        ora #$20
        cmp Exts+1,x
        bne @next
        lda entryName-1,y
        ora #$20
        cmp Exts+2,x
        bne @next
        clc
        rts
@next:  inx
        inx
        inx
        cpx #Exts_n
        bcc @try
@no:    sec
        rts

        .segment "OV3"

; Lines: drive X's line in the dialog: the name of the image mounted
; there (the part after its path's last "/", cut to fit), or "free".
Lines:  txa
        jsr Info
        txa
        bne @none
        jsr NamePart            ; X = the name's start in info (uses Y)
        jsr LineY               ; Y = its line's start
@ch:    lda info,x
        sta lines,y
        beq @end
        iny
        inx
        tya                     ; (cut: the line's last byte stays 0)
        ldy drv
        cmp LineEnd,y
        tay
        bcc @ch
        lda #0
        sta lines,y
@end:   rts
@none:  jsr LineY
        ldx #0
@f:     lda FreeText,x
        sta lines,y
        beq @end
        iny
        inx
        bne @f

; LineY: Y = drive drv's line's start in lines (LINE_LEN * drive).
LineY:  ldy drv
        lda LineAt,y
        tay
        rts

; NamePart: X = the start of the last part of the path in info.
NamePart:
        ldx #0
        ldy #0
@ch:    lda info,y
        beq @end
        iny
        cmp #'/'
        bne @ch
        tya
        tax
        bne @ch
@end:   rts

        .segment "CODE"

; Info: FE_MOUNTINFO for drive A (0-3) into info. X = 0 when it holds
; an image, else the error (DEV_NOT_FOUND: none). drivePath set for it.
Info:   jsr Letter
        lda #<info
        sta r1L
        lda #>info
        sta r1H
        lda #FE_MOUNTINFO
        jmp FileEngine

; Letter: drivePath = drive A's path ("/a"-"/d"), r0 = it.
Letter: clc
        adc #'a'
        sta drivePath + 1
        lda #<drivePath
        sta r0L
        lda #>drivePath
        sta r0H
        rts

; HasImage: C clear when drive A (0-3) holds an image (desktop.s draws
; the eject icon then). Destroys r0-r15 (the engine's).
HasImage:
        jsr Info
        cpx #1                  ; (X = 0: C clear)
        rts

        .segment "OV3"

; Eject: A = a sidebar drive line's letter ('a'-'d'), clicked on its
; eject icon: the drive's image unmounted after asking; a drive without
; one is entered as a click on its line would.
Eject:  sta letter
        sec
        sbc #'a'
        jsr Info
        txa
        beq :+
        lda letter              ; (no image: as a click on the line)
        jmp Drive
:       jsr NamePart            ; the question's second line: the name
        ldy #0
@n:     lda info,x
        sta ejectName,y
        beq @ask
        iny
        inx
        cpy #MINFO_LEN - 1
        bcc @n
        lda #0
        sta ejectName,y
@ask:   lda letter
        and #$DF                ; (upper case)
        sta EjectLetter
        lda #<ejectDlg
        sta r0L
        lda #>ejectDlg
        sta r0H
        jsr Dialog
        lda r0L
        cmp #YES
        bne @end
        lda letter
        sta drivePath + 1
        lda #<drivePath
        sta r0L
        lda #>drivePath
        sta r0H
        lda #FE_UMOUNT
        jsr Busy                ; (the write-back: a moment)
        jsr FileEngine
        jsr Idle
        txa
        beq @gone
        ldy #0                  ; (the error's first line: the image)
@e:     lda ejectName,y
        sta entryName,y
        beq :+
        iny
        bne @e
:       jmp Error
@gone:  jsr SideRedraw          ; the drive's line away
        lda path + 1            ; the list was on that drive: to "/"
        cmp letter
        bne @here
        lda path + 2
        beq @root
        cmp #'/'
        bne @here
@root:  lda #<RootPath
        ldx #>RootPath
        jmp Into
@here:  jsr ListRead            ; (at "/": one drive fewer)
        jmp ListDraw
@end:   rts

; The drive buttons' routines (DBUSRICON): the choice, the dialog ended
; as by OK.
PickA:  lda #0
        beq Pick
PickB:  lda #1
        bne Pick
PickC:  lda #2
        bne Pick
PickD:  lda #3
Pick:   sta choice
        lda #OK
        sta sysDBData
        jmp RstrFrmDialogue

        .segment "CODE"
Exts:   .byte "d64", "d71", "d81", "dnp"
Exts_n = * - Exts
        .segment "OV3"
LineAt: .repeat DRIVES, i
        .byte i * LINE_LEN
        .endrepeat
LineEnd:
        .repeat DRIVES, i
        .byte i * LINE_LEN + LINE_LEN - 1
        .endrepeat
FreeText:       .byte "free", 0
RootPath:       .byte "/", 0
MountText:      .byte BOLDON, "Mount on drive:", PLAINTEXT, 0
EjectText:      .byte BOLDON, "Unmount drive "
EjectLetter:    .byte "A?", PLAINTEXT, 0

        .segment "CODE"

; EjectIcon: the sidebar's eject icon, 8 x 8 (one card), own drawing,
; GEOS compacted bitmap (8 unique bytes).
EjectIcon:
        .byte $80 + 8
        .byte %00010000
        .byte %00111000
        .byte %01111100
        .byte %11111110
        .byte %00000000
        .byte %11111110
        .byte %11111110
        .byte %00000000

        .segment "OV3"

        .include "drvicon_A.inc"
        .include "drvicon_B.inc"
        .include "drvicon_C.inc"
        .include "drvicon_D.inc"

mountDlg:
        .byte DEF_DB_POS | 1
        .byte DBTXTSTR, TXT_LN_X - 8, ROW0 - 6
        .word MountText
        .repeat DRIVES, i
        .byte DBUSRICON, 1, ROW0 + i * ROW_STEP
        .word DriveButtons + i * 8
        .byte DBTXTSTR, TEXT_X, ROW0 + i * ROW_STEP + TEXT_DY
        .word lines + i * LINE_LEN
        .endrepeat
        .byte CANCEL, DBI_X_2, DBI_Y_2
        .byte 0

; DBUSRICON records: picture, x and y (from the dialog), width in cards,
; height, routine.
DriveButtons:
        .word DriveIconA
        .byte 0, 0, 6, 16
        .word PickA
        .word DriveIconB
        .byte 0, 0, 6, 16
        .word PickB
        .word DriveIconC
        .byte 0, 0, 6, 16
        .word PickC
        .word DriveIconD
        .byte 0, 0, 6, 16
        .word PickD

ejectDlg:
        .byte DEF_DB_POS | 1
        .byte DBTXTSTR, TXT_LN_X, TXT_LN_1_Y + 6
        .word EjectText
        .byte DBTXTSTR, TXT_LN_X, TXT_LN_2_Y + 6
        .word ejectName
        .byte YES, DBI_X_0, DBI_Y_2
        .byte NO, DBI_X_2, DBI_Y_2
        .byte 0

        .segment "DATA"

drivePath:      .byte "/a", 0

        .segment "BSS"

info:           .res MINFO_LEN
lines:          .res DRIVES * LINE_LEN
ejectName:      .res MINFO_LEN
drv:            .res 1
choice:         .res 1
letter:         .res 1
