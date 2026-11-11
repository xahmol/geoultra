; GeoUltra Desktop: the toolbar (docs/DESKTOP.md, "Toolbar and
; right-click"; the user's decisions and mock-up of 2026-11-11). A row
; under the menu bar across the full width, its height a view option
; (tbMode, theme.s: TB_TWO two lines, 16 px, framed 16 x 14 buttons;
; TB_ONE one line, 8 px, the icons flat; TB_OFF none). 15 buttons in
; four groups: back, forward, up, root, home | top, end | view, refresh
; | new folder, info, select all, copy, paste, delete. Each button sits
; on two cards (BitmapUp places bitmaps on cards), 16 px apart from x 8
; with 8 px between the groups (the mock-up: 4 and 6, not on cards).
; A button's bitmap is made when drawn: the frame template with the
; icon shifted into its middle. Back, forward and info do nothing yet
; (the history and the Info dialog are later steps). Own design and
; drawings (the mock-up's icons).

        .include "geos.inc"
        .include "desktop.inc"

        .import tbMode, topY, cMenu, Paint, px0, px1, py0, py1, pcol
        .import Up, Into, ListKey, ListEnd, SelAll, ListRead, ListDraw
        .import View, viewMode, NewFolder, Copy, Paste, Delete, FileEngine
        .export ToolDraw, ToolPress, ToolPaint

TB_Y            = MENU_BOTTOM + 2 ; the toolbar's first pixel row (16)
TB_BUTTONS      = 15
TB_CARD0        = 1             ; the first button's card (x 8)
FRAME_ROWS      = 14
FLAT_ROWS       = 8
ICON_ROW        = 3             ; the icon's first row in a frame
DOT_ROWS        = 4             ; a flat group line: 4 dots, 2 px apart

        .segment "CODE"

; ToolDraw: the toolbar drawn (nothing when it is off): its area
; cleared, each button, the line under two-line buttons or the dotted
; lines between the groups of flat ones. Destroys A, X, Y, r0-r4, r11.
ToolDraw:
        lda tbMode
        cmp #TB_OFF
        bne :+
        rts
:       lda #0
        jsr SetPattern
        lda #TB_Y
        sta r2L
        ldx topY
        dex
        stx r2H
        jsr Across
        jsr Rectangle
        lda #0
        sta at
@button:
        jsr Make
        ldx at
        lda Cards,x
        sta r1L
        lda #TB_Y
        sta r1H
        lda #<bits
        sta r0L
        lda #>bits
        sta r0H
        lda #2
        sta r2L
        lda #FRAME_ROWS
        ldx tbMode
        beq :+
        lda #FLAT_ROWS
:       sta r2H
        jsr BitmapUp
        inc at
        lda at
        cmp #TB_BUTTONS
        bcc @button
        lda tbMode              ; two lines: a line under the buttons
        bne @dots
        ldx topY
        dex
        stx r11L
        jsr Across
        lda #$FF
        jmp HorizontalLine
@dots:  ldx #GROUPS_N - 2       ; one line: dots between the groups
@group: stx at
        lda GroupLine,x         ; (x: a card's start + 4, in the gap)
        asl a
        asl a
        asl a
        clc
        adc #4
        sta r3L
        lda #0
        sta r3H
        lda #TB_Y
        sta r11L
@dot:   jsr DrawPoint1
        lda r11L
        clc
        adc #2
        sta r11L
        cmp #TB_Y + 2 * DOT_ROWS
        bcc @dot
        ldx at
        dex
        bpl @group
        rts

; DrawPoint1: a black point at r3 (x), r11L (y). Keeps r3, r11L.
DrawPoint1:
        sec                     ; (C set: drawn; N clear: in black)
        lda #0
        jmp DrawPoint

; Make: bits = button `at`'s compacted bitmap: two lines, the frame
; template and the icon 3 pixels in (rows 3-10); one line, the icon
; alone, 4 pixels in. Destroys A, X, Y, r4.
Make:   lda #$80 + 2 * FRAME_ROWS  ; (a unique packet: its length)
        ldx tbMode
        beq :+
        lda #$80 + 2 * FLAT_ROWS
:       sta bits
        ldx #2 * FRAME_ROWS - 1 ; the template (or zeros)
@t:     lda Frame,x
        ldy tbMode
        beq :+
        lda #0
:       sta bits + 1,x
        dex
        bpl @t
        lda at                  ; r4 = the icon: Icons + at * 8
        asl a
        asl a
        asl a
        clc
        adc #<Icons
        sta r4L
        lda #>Icons
        adc #0
        sta r4H
        ldy #0
        ldx #2 * ICON_ROW       ; its first row's left byte in the frame
        lda tbMode
        beq @row
        ldx #0
@row:   lda (r4),y
        sta shift
        lda #0
        sta shift + 1
        lda tbMode              ; framed: 3 pixels right, flat: 4
        beq :+
        lsr shift
        ror shift + 1
:       lsr shift
        ror shift + 1
        lsr shift
        ror shift + 1
        lsr shift
        ror shift + 1
        lda shift
        ora bits + 1,x
        sta bits + 1,x
        lda shift + 1
        ora bits + 2,x
        sta bits + 2,x
        inx
        inx
        iny
        cpy #8
        bcc @row
        rts

; Across: r3-r4 = x 0 to 319.
Across: lda #0
        sta r3L
        sta r3H
        lda #<SCREEN_RIGHT
        sta r4L
        lda #>SCREEN_RIGHT
        sta r4H
        rts

; ToolPaint: the toolbar's cells in the menu bar's colours (theme.s's
; PaintAll; a theme colour of its own is a later step).
ToolPaint:
        lda topY
        lsr a
        lsr a
        lsr a
        tax
        dex
        cpx #TB_Y / 8           ; (off: no rows)
        bcc @end
        stx py1
        lda #TB_Y / 8
        sta py0
        lda #0
        sta px0
        lda #39
        sta px1
        lda cMenu
        sta pcol
        jmp Paint
@end:   rts

; ToolPress: C clear when the press (mouseXPos, mouseYPos) was on the
; toolbar's row (a button's action done, or nothing between buttons);
; C set when it was below it.
ToolPress:
        lda mouseYPos
        cmp topY
        bcc :+
        rts                     ; (C set: below the toolbar)
:       lda mouseXPos+1         ; the card: x / 8
        lsr a
        lda mouseXPos
        ror a
        lsr a
        lsr a
        sta card
        ldx #TB_BUTTONS - 1
@b:     lda card
        sec
        sbc Cards,x
        cmp #2                  ; (on its two cards; left of it: large)
        bcc @hit
        dex
        bpl @b
        clc                     ; (between buttons: nothing)
        rts
@hit:   txa
        asl a
        tax
        lda Acts+1,x
        pha
        lda Acts,x
        pha
        rts                     ; (the action's rts: back with C as left)

; The buttons' actions (C on return does not matter: Press ends).
Root:   lda #<RootPath
        ldx #>RootPath
        jmp Into
Home:   lda #<homePath          ; FE_HOME ("/USB0/GEOULTRA/"; none
        sta r1L                 ; without an Ultimate: nothing)
        lda #>homePath
        sta r1H
        lda #FE_HOME
        jsr FileEngine
        txa
        bne Nothing
        ldy #0                  ; its last "/" dropped
@end:   lda homePath,y
        beq :+
        iny
        bne @end
:       dey
        beq :+                  ; ("/" alone stays)
        lda homePath,y
        cmp #'/'
        bne :+
        lda #0
        sta homePath,y
:       lda #<homePath
        ldx #>homePath
        jmp Into
Top:    lda #KEY_HOME           ; (the list's own key)
        jmp ListKey
ViewNext:                       ; list -> detailed -> list (icons: a
        lda #VIEW_DETAILED      ; later step)
        ldx viewMode
        cpx #VIEW_LIST
        beq :+
        lda #VIEW_LIST
:       jmp View
Refresh:
        jsr ListRead
        jmp ListDraw
Nothing:
        rts

Acts:   .word Nothing-1, Nothing-1, Up-1, Root-1, Home-1   ; back, forward: T2
        .word Top-1, ListEnd-1
        .word ViewNext-1, Refresh-1
        .word NewFolder-1, Nothing-1, SelAll-1, Copy-1, Paste-1, Delete-1
        .assert (* - Acts) / 2 = TB_BUTTONS, error, "an action per button"

; The buttons' cards: 16 px apart from x 8, 8 px between the groups.
Cards:  .byte 1, 3, 5, 7, 9
        .byte 12, 14
        .byte 17, 19
        .byte 22, 24, 26, 28, 30, 32
GROUPS_N = 4
GroupLine:      .byte 11, 16, 21        ; the gaps' cards (flat: dots)

; The frame (16 x 14: rounded corners, a shadow right and below).
Frame:  .byte $00, $00, $7F, $F8, $80, $06, $80, $06, $80, $06, $80, $06
        .byte $80, $06, $80, $06, $80, $06, $80, $06, $80, $06, $80, $06
        .byte $7F, $FA, $7F, $FE

; The icons, 8 x 8, rows top to bottom (the approved mock-up).
Icons:  .byte $00, $20, $60, $FE, $60, $20, $00, $00    ; back
        .byte $00, $08, $0C, $FE, $0C, $08, $00, $00    ; forward
        .byte $10, $38, $7C, $FE, $38, $38, $38, $00    ; up
        .byte $06, $0C, $0C, $18, $30, $30, $60, $00    ; root "/"
        .byte $10, $38, $7C, $FE, $44, $54, $7C, $00    ; home
        .byte $FE, $00, $10, $38, $7C, $10, $10, $00    ; top
        .byte $10, $10, $7C, $38, $10, $00, $FE, $00    ; end
        .byte $EE, $EE, $EE, $00, $EE, $EE, $EE, $00    ; view
        .byte $3A, $46, $8E, $80, $82, $44, $38, $00    ; refresh
        .byte $70, $8F, $81, $91, $B9, $91, $FF, $00    ; new folder
        .byte $38, $54, $82, $92, $92, $54, $38, $00    ; info
        .byte $AA, $01, $80, $01, $80, $01, $55, $00    ; select all
        .byte $F0, $9E, $92, $92, $F2, $12, $1E, $00    ; copy
        .byte $38, $EE, $82, $BA, $82, $BA, $FE, $00    ; paste
        .byte $38, $FE, $44, $54, $54, $54, $38, $00    ; delete
        .assert * - Icons = 8 * TB_BUTTONS, error, "an icon per button"

RootPath:       .byte "/", 0

        .segment "BSS"

bits:           .res 1 + 2 * FRAME_ROWS ; a button's compacted bitmap
shift:          .res 2
at:             .res 1
card:           .res 1
homePath:       .res 64
