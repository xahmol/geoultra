; GeoUltra Desktop: the INI files (overlay 4, ovl.s; moved out of
; side.s in the eighth code sweep, 2026-11-11, to give the core room).
; SETTINGS.INI's [favourites] and [desktop] sections and RECENT.INI's
; [recent] section are read into side.s's lists at the start (LoadAll)
; and written anew when a list changes (Save): the text read whole,
; written as a temporary file that then takes the old one's place, its
; other lines kept (its section moves to the end), as gush's turbo -s
; does (sysset.s). Without an Ultimate (VICE) nothing is read or
; written. The [desktop] keys: theme=, view=, clock= (DeskRead, the
; *Save routines). Calls only the core (side.s's Setup, Slot, Store, the
; file engine). Own code.

        .include "geos.inc"
        .include "desktop.inc"

        .import FileEngine, Setup, Slot, Store, text, counts, which, at, work
        .import wantTheme, wantView, wantToolbar, curName, clockMode, viewMode, tbMode
        .importzp lp, sp
        .export Ov_LoadAll, Ov_Save, Ov_ThemeSave, Ov_ViewSave, Ov_ClockSave, Ov_ToolbarSave
Ov_LoadAll = LoadAll            ; (the stubs in ovl.s, overlay 4)
Ov_Save = Save
Ov_ThemeSave = ThemeSave
Ov_ViewSave = ViewSave
Ov_ClockSave = ClockSave
Ov_ToolbarSave = ToolbarSave

        .segment "OV4"

; LoadAll (side.s, SideLoad): the three lists from their files (empty
; when a file is not there or cannot be read), then the [desktop]
; wishes (DeskRead).
LoadAll:
        ldx #L_FAV
        jsr Load
        ldx #L_REC
        jsr Load
        ldx #L_DESK
        jsr Load
        jmp DeskRead

; Load: list X from its file's section.
Load:   jsr Setup
        lda #0
        ldx which
        sta counts,x
        jsr Files
        bcs @end                ; (no home folder: none)
        jsr ReadText
        txa
        bne @end                ; (no Ultimate, or too large: none)
        jsr Begin
@line:  jsr AtEnd
        bcs @end
        jsr LineLen
        ldy #0
        lda (r5),y
        cmp #'['
        bne @body
        jsr IsSection
        sta inSect
        jmp @next
@body:  lda inSect
        beq @next
        jsr Take
@next:  jsr Next
        jmp @line
@end:   rts

; Take: the line at r5 (without its CR/LF) as the list's next path, when
; there is room, it is not empty and it fits PATH_LEN.
Take:   ldx which
        lda counts,x
        cmp #LIST_MAX
        bcs @end
        jsr Slot
        ldy #0
@ch:    cpy lineLen
        beq @zero
        lda (r5),y
        cmp #CR
        beq @zero
        cmp #10
        beq @zero
        cpy #PATH_LEN - 1
        bcs @end                ; (too long: left out)
        sta (r6),y
        iny
        bne @ch
@zero:  tya
        beq @end                ; (an empty line)
        lda #0
        sta (r6),y
        ldx which
        inc counts,x
@end:   rts

; Save: list X's file anew: its lines outside the section as they were,
; then the section with the list. X = 0 or the error (the old file then
; stays as it was).
Save:   jsr Setup
        jsr Files
        bcc :+
        ldx #FE_ULTIMATE        ; (no home folder: not saved)
        rts
:       jsr ReadText
        txa
        beq :+
        rts
:
        lda #<tmpPath
        sta r0L
        lda #>tmpPath
        sta r0H
        lda #FO_WRITE
        sta r2L
        lda #FE_OPEN
        jsr FileEngine
        sta handle              ; (A: the handle; txa would lose it)
        txa
        beq :+
        rts
:       sta failed
        sta needNl
        jsr Begin
@line:  jsr AtEnd
        bcs @tail
        jsr LineLen
        ldy #0
        lda (r5),y
        cmp #'['
        bne @body
        jsr IsSection
        sta inSect
@body:  lda inSect              ; (the section's lines: written anew below)
        bne @next
        jsr Put
@next:  jsr Next
        jmp @line
@tail:  lda needNl              ; (a last line without its end)
        beq :+
        jsr NewLine
:       lda sp                  ; the section, then the paths
        ldy sp+1
        jsr Write
        jsr NewLine
        lda #0
        sta at
@path:  lda at
        ldx which
        cmp counts,x
        bcs @close
        jsr Slot
        lda r6L
        ldy r6H
        jsr Write
        jsr NewLine
        inc at
        bne @path
@close: lda #FE_CLOSE
        ldy handle
        jsr FileEngine
        lda failed              ; a write failed: the new one away, the
        beq @swap               ; old one kept
        lda #<tmpPath
        sta r0L
        lda #>tmpPath
        sta r0H
        lda #FE_DELETE
        jsr FileEngine
        ldx failed
        rts
@swap:  lda #<iniPath           ; the old one away, the new one in its place
        sta r0L
        lda #>iniPath
        sta r0H
        lda #FE_DELETE
        jsr FileEngine          ; (FILE_NOT_FOUND: there was none)
        lda #<tmpPath
        sta r0L
        lda #>tmpPath
        sta r0H
        ldx which
        lda NameLo,x
        sta r1L
        lda NameHi,x
        sta r1H
        lda #FE_RENAME
        jsr FileEngine
@end:   rts

; Files: iniPath and tmpPath: the home folder and the current list's
; file names. C set when there is no home folder (no Ultimate): a bare
; name would land in the current folder.
Files:  lda #<iniPath
        sta r1L
        lda #>iniPath
        sta r1H
        lda #0
        sta iniPath
        lda #FE_HOME
        jsr FileEngine
        txa
        bne @none
        lda iniPath
        cmp #'/'
        beq :+
@none:  sec
        rts
:       ldx #0
@home:  lda iniPath,x
        sta tmpPath,x
        beq @names
        inx
        cpx #32                 ; (FE_HOME's buffer)
        bne @home
@names: ldy which
        lda NameLo,y
        sta r0L
        lda NameHi,y
        sta r0H
        lda TmpLo,y
        sta r1L
        lda TmpHi,y
        sta r1H
        ldy #0
@ch:    lda (r0),y
        sta iniPath,x
        lda (r1),y
        sta tmpPath,x
        beq @end
        inx
        iny
        bne @ch
@end:   clc
        rts

; ReadText: the file at iniPath into text (not there: empty), textLen
; its bytes. X = 0 or the error (FE_ULTIMATE: larger than TEXT_MAX).
ReadText:
        lda #0
        sta textLen
        sta textLen+1
        lda #<iniPath
        sta r0L
        lda #>iniPath
        sta r0H
        lda #FO_READ
        sta r2L
        lda #FE_OPEN
        jsr FileEngine
        sta handle              ; (A: the handle; txa would lose it)
        cpx #FILE_NOT_FOUND
        beq @none
        txa
        bne @end
        lda #<text
        sta r1L
        lda #>text
        sta r1H
        lda #<(TEXT_MAX + 1)
        sta r2L
        lda #>(TEXT_MAX + 1)
        sta r2H
        lda #FE_READ
        ldy handle
        jsr FileEngine
        lda r2L
        sta textLen
        lda r2H
        sta textLen+1
        txa
        pha
        lda #FE_CLOSE
        ldy handle
        jsr FileEngine
        pla
        tax
        bne @end
        ldx #FE_ULTIMATE        ; (too large to rewrite safely)
        lda textLen
        cmp #<(TEXT_MAX + 1)
        lda textLen+1
        sbc #>(TEXT_MAX + 1)
        bcs @end
@none:  ldx #0
@end:   rts

; Begin: r5 at the text's start, textEnd after it, outside any section.
Begin:  lda #<text
        sta r5L
        clc
        adc textLen
        sta textEnd
        lda #>text
        sta r5H
        adc textLen+1
        sta textEnd+1
        lda #0
        sta inSect
        rts

; AtEnd: C set when r5 has reached textEnd.
AtEnd:  lda r5L
        cmp textEnd
        lda r5H
        sbc textEnd+1
        rts

; Next: r5 on to the next line.
Next:   lda r5L
        clc
        adc lineLen
        sta r5L
        bcc :+
        inc r5H
:       rts

; LineLen: lineLen = the line at r5's bytes, its CR/LF included (to the
; text's end at most; a line is at most 255 bytes).
LineLen:
        ldy #0
@ch:    tya
        clc
        adc r5L
        tax
        lda #0
        adc r5H
        cpx textEnd
        sbc textEnd+1
        bcs @end
        lda (r5),y
        iny
        beq @long
        cmp #10
        bne @ch
@end:   sty lineLen
        rts
@long:  dey                     ; (255: written on as it is)
        sty lineLen
        rts

; IsSection: A = 1 when the line at r5 starts with the list's section
; line (sp; letters in any case), else 0.
IsSection:
        ldy #0
@ch:    lda (sp),y
        beq @yes
        cpy lineLen
        bcs @no
        lda (r5),y
        cmp (sp),y              ; (as it is, else in lower case: ora alone
        beq :+                  ; would turn "[" into "{")
        ora #$20
        cmp (sp),y
        bne @no
:       iny
        bne @ch
@yes:   lda #1
        rts
@no:    lda #0
        rts

; Put: the line at r5 (lineLen bytes) written; needNl when it has no LF.
Put:    lda r5L
        sta r1L
        lda r5H
        sta r1H
        lda lineLen
        sta r2L
        lda #0
        sta r2H
        sta needNl
        ldy lineLen
        beq Out
        dey
        lda (r5),y
        cmp #10
        beq Out
        inc needNl
        bne Out

; NewLine: CR LF written. Write: the zero-ended text at A/Y written.
NewLine:
        lda #<CrLf
        ldy #>CrLf
Write:  sta r1L
        sty r1H
        ldy #$FF
@len:   iny
        lda (r1),y
        bne @len
        sty r2L
        lda #0
        sta r2H
Out:    lda #FE_WRITE
        ldy handle
        jsr FileEngine
        txa
        beq :+
        stx failed
:       rts

; --- The desktop's settings in SETTINGS.INI [desktop] ----------------------
; theme= a built-in theme's name (theme.s); view= list, icons or
; detailed; clock= 24, 12 or off (24 the default; user, 2026-11-11).
; Each a line of the [desktop] list (L_DESK); other lines there stay as
; they are. A value is known by its first letter or digit.

; DeskRead (LoadAll): the [desktop] lines' wishes for the core's
; SideLoad: wantTheme = the theme's name (empty: none), wantView = the
; view (VIEW_*, $FF: none), clockMode = the clock (when named). The core
; then uses the theme (overlay 1: an overlay calls no other).
DeskRead:
        lda #0
        sta wantTheme
        lda #$FF
        sta wantView
        sta wantToolbar
        ldx #L_DESK
        jsr Setup
        ldx #KEY_THEME
        jsr FindKey             ; (A: its slot)
        bcs @view
        jsr Value               ; r0 = the name after "theme="
        ldy #0
@name:  lda (r0),y
        cmp #CR                 ; (the slot holds the line without its end;
        beq @named              ; a CR or LF there ends it too)
        cmp #10
        beq @named
        sta wantTheme,y
        beq @view
        iny
        cpy #WANT_LEN - 1
        bcc @name
@named: lda #0
        sta wantTheme,y
@view:  ldx #KEY_VIEW
        jsr FindKey
        bcs @clock
        jsr Value
        ldx #ViewFirst - First
        jsr Pick
        bcs @clock
        sta wantView
@clock: ldx #KEY_CLOCK
        jsr FindKey
        bcs @bar
        jsr Value
        ldx #ClockFirst - First
        jsr Pick
        bcs @bar
        sta clockMode
@bar:   ldx #KEY_TOOLBAR
        jsr FindKey
        bcs @end
        jsr Value
        ldx #ToolbarFirst - First
        jsr Pick
        bcs @end
        sta wantToolbar
@end:   rts

; Pick: A = the index of the value at r0 among the first characters at
; First + X (three, zero after them); C set when none matches.
Pick:   ldy #0
        lda (r0),y
        ora #$20                ; (lower case; digits keep their bit 5)
        sta key
        ldy #0
@try:   lda First,x
        beq @none
        cmp key
        beq @got
        inx
        iny
        bne @try
@got:   tya
        clc
        rts
@none:  sec
        rts

; Value: r0 = the value of slot A's line (after its key, keyLen
; characters, FindKey).
Value:  jsr Slot
        lda r6L
        clc
        adc keyLen
        sta r0L
        lda r6H
        adc #0
        sta r0H
        rts

; ThemeSave: "theme=" and the theme in use, then "view=" and its view
; (a theme brings its own); ViewSave: "view=" and viewMode; ClockSave:
; "clock=" and clockMode; each as a [desktop] line, SETTINGS.INI
; written (an error: the setting lasts until the desktop starts again).
ThemeSave:
        lda #<curName           ; (themefile.s: the name in use)
        sta r1L
        lda #>curName
        sta r1H
        ldx #KEY_THEME
        jsr SetLine
ViewSave:
        lda viewMode
        ldx #KEY_VIEW
        ldy #ViewWords - Words  ; (0: no branch on Z)
        jmp Word
ToolbarSave:
        lda tbMode
        ldx #KEY_TOOLBAR
        ldy #ToolbarWords - Words
        bne Word                ; (not 0: always)
ClockSave:
        lda clockMode
        ldx #KEY_CLOCK
        ldy #ClockWords - Words
; Word: key X with word A of the words at Words + Y (zero-ended, one
; after the other) as its value: SetLine.
Word:   sta at
@skip:  lda at                  ; word A: past A zeros
        beq @here
@ch:    lda Words,y
        iny
        cmp #0
        bne @ch
        dec at
        jmp @skip
@here:  tya
        clc
        adc #<Words
        sta r1L
        lda #>Words
        adc #0
        sta r1H
; SetLine: key X (KEY_THEME, KEY_VIEW, KEY_CLOCK) and the value at r1 as
; a [desktop] line: the one there replaced, else added (the last
; replaced when the list is full); SETTINGS.INI written.
SetLine:
        stx key
        ldx #L_DESK
        jsr Setup
        ldx key
        ldy #0                  ; work = the key and the value
@key:   lda Keys,x
        beq @val0
        sta work,y
        inx
        iny
        bne @key
@val0:  sty keyLen
        tya
        tax                     ; X: in work, Y: in the value
        ldy #0
@val:   lda (r1),y
        sta work,x
        beq @slot
        iny
        inx
        cpx #PATH_LEN - 1
        bcc @val
        lda #0
        sta work + PATH_LEN - 1
@slot:  ldx key                 ; its slot: the old line's, else the next
        jsr FindKey
        bcc @store
        lda counts + L_DESK
        cmp #LIST_MAX
        bcc :+
        lda #LIST_MAX - 1       ; (full: the last one replaced)
        bne @store
:       inc counts + L_DESK
@store: jsr Slot
        jsr Store
        ldx #L_DESK
        jmp Save

; FindKey: C clear and A = the slot of the current list (Setup) whose
; line starts with key X (Keys + X, zero-ended, any case), keyLen its
; length; C set when none does.
FindKey:
        stx key
        lda #0
        sta at
@slot:  lda at
        ldx which
        cmp counts,x
        bcs @none
        jsr Slot
        ldy #0
        ldx key
@ch:    lda Keys,x
        beq @found
        lda (r6),y
        cmp #'A'
        bcc :+
        cmp #'Z' + 1
        bcs :+
        ora #$20
:       cmp Keys,x
        bne @next
        inx
        iny
        bne @ch
@found: sty keyLen
        lda at
        clc
        rts
@next:  inc at
        bne @slot
@none:  sec
        rts

KEY_THEME = 0
Keys:           .byte "theme=", 0
KEY_VIEW = * - Keys
                .byte "view=", 0
KEY_CLOCK = * - Keys
                .byte "clock=", 0
KEY_TOOLBAR = * - Keys
                .byte "toolbar=", 0
First:                                  ; a value's first character
ViewFirst:      .byte "lid", 0          ; list, icons, detailed
ClockFirst:     .byte "21o", 0          ; 24, 12, off
ToolbarFirst:   .byte "18o", 0          ; 16, 8, off (its height in pixels)
Words:
ViewWords:      .byte "list", 0, "icons", 0, "detailed", 0
ClockWords:     .byte "24", 0, "12", 0, "off", 0
ToolbarWords:   .byte "16", 0, "8", 0, "off", 0

NameLo:         .byte <IniName, <RecName, <IniName
NameHi:         .byte >IniName, >RecName, >IniName
TmpLo:          .byte <IniTmp, <RecTmp, <IniTmp
TmpHi:          .byte >IniTmp, >RecTmp, >IniTmp
IniName:        .byte "SETTINGS.INI", 0
IniTmp:         .byte "SETTINGS.TMP", 0
RecName:        .byte "RECENT.INI", 0
RecTmp:         .byte "RECENT.TMP", 0
CrLf:           .byte CR, 10, 0

; Scratch while the overlay runs (LoadAll, Save: one call each).
handle:         .byte 0
failed:         .byte 0
needNl:         .byte 0
inSect:         .byte 0
lineLen:        .byte 0
key:            .byte 0         ; FindKey, SetLine: the key's offset
keyLen:         .byte 0         ; and its length
textLen:        .word 0
textEnd:        .word 0

        .segment "BSS"

iniPath:        .res 48
tmpPath:        .res 48
