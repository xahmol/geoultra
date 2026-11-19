; GeoUltra Desktop: the INI files (overlay 4, ovl.s; moved out of
; side.s in the eighth code sweep, 2026-11-11, to give the core room).
; SETTINGS.INI's [favourites] and [desktop] sections and RECENT.INI's
; [recent] section are read into side.s's lists at the start (LoadAll)
; and written anew when a list changes (Save): the text read whole,
; written as a temporary file that then takes the old one's place, its
; other lines kept (its section moves to the end), as gush's turbo -s
; does (sysset.s). Without an Ultimate (VICE) nothing is read or
; written. The [desktop] keys: theme=, view=, clock=, toolbar=, panes=,
; printer= (DeskRead, the *Save routines, UsePrinter). Calls only the
; core (side.s's Setup, Slot, the file engine, errors.s's Error). Own
; code.

        .include "geos.inc"
        .include "desktop.inc"

        .import FileEngine, Setup, Slot, text, counts, which, at
        .import panes, wantPanes, sortMode, deskPrefs
        .import wantTheme, wantView, wantToolbar, curName, clockMode, viewMode, tbMode
        .importzp sp
        .import entryName, Error
        .export Ov_LoadAll, Ov_Save, Ov_ThemeSave, Ov_ViewSave, Ov_ClockSave, Ov_ToolbarSave
        .export Ov_PanesSave, Ov_PanesKeep, Ov_SortSave, Ov_UsePrinter
Ov_LoadAll = LoadAll            ; (the stubs in ovl.s, overlay 4)
Ov_Save = Save
Ov_ThemeSave = ThemeSave
Ov_ViewSave = ViewSave
Ov_ClockSave = ClockSave
Ov_UsePrinter = UsePrinter
Ov_ToolbarSave = ToolbarSave
Ov_PanesSave = PanesSave
Ov_PanesKeep = PanesKeep
Ov_SortSave = SortSave

        .segment "OV4"

INI_OV4 = 1                     ; (ini.inc's variables in this overlay:
                                ; they are used only while it runs)
CLOCK_OV4 = 1                   ; (clock.inc's variables in this overlay)
        .include "clock.inc"    ; ClockShift: [time] adjust= (ClockAdjust)
        .include "ini.inc"      ; (SETTINGS.INI's [desktop] keys: DeskText,
                                ; KeyVal, SetLine; shared with Settings)

; LoadAll (side.s, SideLoad): the three lists from their files (empty
; when a file is not there or cannot be read), then the [desktop]
; wishes (DeskRead).
LoadAll:
        ldx #L_FAV
        jsr Load
        ldx #L_REC
        jsr Load
        jmp DeskRead            ; ([desktop]: from the file's text)

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
        bcs Finish
        jsr Slot
        lda r6L
        ldy r6H
        jsr Write
        jsr NewLine
        inc at
        bne @path
; Finish (Save, WriteText): the new file closed; written well, it takes
; the old one's place, else it is deleted (the old one kept). X = 0 or
; the error.
Finish:
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
        lda PrntFilename        ; no printer yet: GU Epson FX-80 (drive E;
        bne :+                  ; docs/design/DESIGN.md "Printing"), unless
        ldx #DEF_PRN_LEN        ; printer= names another
@def:   lda DefPrinter,x
        sta PrntFilename,x
        dex
        bpl @def
:       lda #0
        sta wantTheme
        lda #$FF
        sta wantView
        sta wantToolbar
        sta wantPanes
        lda #0                  ; (sort=: by name unless named; copy=ask,
        sta sortMode            ; delete=ask)
        sta deskPrefs
        jsr DeskText
        bcc :+
        rts                     ; (no file: the defaults)
:       jsr ClockAdjust         ; (after a cold start: [time] adjust=)
        ldx #KEY_THEME
        jsr KeyVal             ; (A: its slot)
        bcs @view
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
        jsr KeyVal
        bcs @clock
        ldx #ViewFirst - First
        jsr Pick
        bcs @clock
        sta wantView
@clock: ldx #KEY_CLOCK
        jsr KeyVal
        bcs @bar
        ldx #ClockFirst - First
        jsr Pick
        bcs @bar
        sta clockMode
@bar:   ldx #KEY_TOOLBAR
        jsr KeyVal
        bcs @panes
        ldx #ToolbarFirst - First
        jsr Pick
        bcs @panes
        sta wantToolbar
@panes: ldx #KEY_PANES
        jsr KeyVal
        bcs @pane2
        ldx #PanesFirst - First
        jsr Pick
        bcs @pane2
        sta wantPanes
@pane2: ldx #KEY_SORT           ; sort= (sort.s): name, date, size, type;
        jsr KeyVal             ; "-" in front: reversed (SORT_REV)
        bcs :+
        ldy #0
        sty key
        lda (r0),y
        cmp #'-'
        bne @key
        lda #SORT_REV
        sta key
        inc r0L
        bne @key
        inc r0H
@key:   lda key             ; (Pick uses key: the flag on the stack)
        pha
        ldx #SortFirst - First
        jsr Pick
        bcs @nok
        sta key
        pla
        ora key
        sta sortMode
        bcc :+                  ; (C clear: always)
@nok:   pla
:       ldx #KEY_COPY           ; copy= (tree.s): ask, replace, skip, newer
        jsr KeyVal
        bcs :+
        ldx #CopyFirst - First
        jsr Pick
        bcs :+
        sta deskPrefs           ; (bits 0-1)
:       ldx #KEY_DEL            ; delete=now (actions.s): no question
        jsr KeyVal
        bcs :+
        ldx #DelFirst - First
        jsr Pick
        bcs :+
        tax
        beq :+
        lda deskPrefs
        ora #PREF_NOASK
        sta deskPrefs
:       ldx #KEY_ICOLS          ; iconcolours=off (iconview.s): no icon
        jsr KeyVal              ; colours by type (on, off: the second
        bcs :+                  ; letter tells)
        ldy #1
        lda (r0),y
        ora #$20
        cmp #'f'
        bne :+
        lda deskPrefs
        ora #PREF_PLAIN
        sta deskPrefs
:       ldx #KEY_PRINTER        ; printer= (a printer driver's name, to its
        jsr KeyVal              ; line's end): PrntFilename
        bcs :+
        ldy #0
@pn:    lda (r0),y
        cmp #' '
        bcc @pz
        sta PrntFilename,y
        iny
        cpy #16
        bcc @pn
@pz:    lda #0
        sta PrntFilename,y
:       ldx #KEY_PANE2          ; the other pane's folder, into its state
        jsr KeyVal             ; in the REU (list.s's PaneInit gave it "/"
        bcs @end                ; before this; the user, 2026-11-12: two
        ldy #0                  ; two-window mode)
@ch:    lda (r0),y
        cmp #' ' + 1            ; (its line's end)
        bcc @zero
        sta pbuf,y
        iny
        cpy #PATH_LEN - 1
        bcc @ch
@zero:  lda #0
        sta pbuf,y
        cpy #0
        beq @end
        jsr PaneRegs
        jmp StashRAM
@end:   rts

; PanesKeep (desktop.s Leave: before a program or a desk accessory
; takes over): with two panes, the other pane's folder as [desktop]
; pane2= when it changed (a path longer than a line holds: not kept).
; The pane in use is the file engine's current folder: it comes back by
; itself. Keeps r2, r3 and r6: the callers set the program's name (r6)
; and a document's disk and name (r2, r3) before Leave (found 2026-11-13:
; in two panes geoFolder and programs did not start, the INI code's Slot
; had changed r6).
PanesKeep:
        ldx #3
@save:  lda r2L,x               ; (r2, r3: $06-$09)
        sta keepRegs,x
        dex
        bpl @save
        lda r6L
        sta keepR6
        lda r6H
        sta keepR6+1
        jsr Keep2
        ldx #3
@back:  lda keepRegs,x
        sta r2L,x
        dex
        bpl @back
        lda keepR6
        sta r6L
        lda keepR6+1
        sta r6H
        rts

Keep2:  lda panes
        beq @end
        jsr PaneRegs            ; its path's start from the REU
        jsr FetchRAM
        ldy #0
@len:   lda pbuf,y
        beq @got
        iny
        cpy #PATH_LEN - 1
        bcc @len
@end:   rts                     ; (too long)
@got:   jsr DeskText            ; the same as the line there: nothing
        bcs @end
        ldx #KEY_PANE2
        jsr KeyVal
        bcs @set
        ldy #$FF
@cmp:   iny
        lda pbuf,y
        beq @last
        cmp (r0),y
        beq @cmp
        bne @set
@last:  lda (r0),y              ; (the line's value ends here too?)
        cmp #' ' + 1
        bcc @end
@set:   lda #<pbuf
        sta valPtr
        lda #>pbuf
        sta valPtr+1
        ldx #KEY_PANE2
        jmp SetIn               ; (the text read just now)

; PaneRegs: r0-r3 for the other pane's path's first PATH_LEN bytes
; (list.s SwapPane's first part) and pbuf.
PaneRegs:
        lda #<pbuf
        sta r0L
        lda #>pbuf
        sta r0H
        lda #0
        sta r1L
        sta r2H
        lda #PANE_PAGE
        sta r1H
        lda #PATH_LEN
        sta r2L
        lda #PANE_BANK
        sta r3L
        rts

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
PanesSave:
        lda panes
        ldx #KEY_PANES
        ldy #PanesWords - Words
        bne Word                ; (not 0: always)
ToolbarSave:
        lda tbMode
        ldx #KEY_TOOLBAR
        ldy #ToolbarWords - Words
        bne Word                ; (not 0: always)
; SortSave: "sort=" and sortMode's word, "-" in front when reversed.
SortSave:
        ldx #0
        lda sortMode
        bpl :+
        lda #'-'
        sta sortVal
        inx
:       lda sortMode
        and #SORT_KEYS
        asl a                   ; (SortWords: four letters each)
        asl a
        tay
        lda #4
        sta at
@ch:    lda SortWords,y
        sta sortVal,x
        inx
        iny
        dec at
        bne @ch
        lda #0
        sta sortVal,x
        lda #<sortVal
        sta r1L
        lda #>sortVal
        sta r1H
        ldx #KEY_SORT
        jmp SetLine
; UsePrinter (open.s: a printer driver opened, also from the context
; menu's "use as printer"): entryName the printer (PrntFilename, which
; applications load), kept as SETTINGS.INI's [desktop] printer= (when
; it can be written), the note that it is.
UsePrinter:
        ldy #0
:       lda entryName,y
        sta PrntFilename,y
        beq :+
        iny
        cpy #16
        bcc :-
        lda #0
        sta PrntFilename,y
:       lda #<PrntFilename
        sta r1L
        lda #>PrntFilename
        sta r1H
        ldx #KEY_PRINTER
        jsr SetLine
        ldx #ERR_PRINTER
        jmp Error
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
; SetLine: key X (KEY_*) and the zero-ended value at r1 as SETTINGS.INI's
; [desktop] line: the file read anew, the key's line replaced or added
; (ini.inc IniSet; the other lines and sections as they are), written
; back. (Until 2026-11-13 the desktop kept [desktop] as four lines of its
; own and wrote them over the file: Settings' further lines, delete=,
; copy=, panes= ..., were lost; the user's test.) X = 0 or the error.
SetLine:
        stx key
        lda r1L
        sta valPtr
        lda r1H
        sta valPtr+1
        jsr DeskText
        bcc :+
        ldx #FE_ULTIMATE        ; (no home folder or no file to keep)
        rts
:       ldx key
SetIn:  lda valPtr              ; (Keep2: the text read, X the key,
        sta r2L                 ; valPtr the value)
        lda valPtr+1
        sta r2H
        jsr KeyRegs
        jsr IniSet
        bcc WriteText
        ldx #FE_ULTIMATE        ; (the text is full: not written)
        rts

; WriteText: the text (iniLen bytes) written as tmpPath, then in
; iniPath's place (Finish, as Save). X = 0 or the error.
WriteText:
        lda #<tmpPath
        sta r0L
        lda #>tmpPath
        sta r0H
        lda #FO_WRITE
        sta r2L
        lda #FE_OPEN
        jsr FileEngine
        sta handle
        txa
        beq :+
        rts
:       sta failed
        lda #<text
        sta r1L
        lda #>text
        sta r1H
        lda iniLen
        sta r2L
        lda iniLen+1
        sta r2H
        lda #FE_WRITE
        ldy handle
        jsr FileEngine
        stx failed
        jmp Finish

; DeskText: SETTINGS.INI read whole into text for ini.inc (iniBase,
; iniMax, iniLen, the zero after it); not there: an empty text. C set
; when there is no home folder or it could not be read.
DeskText:
        ldx #L_DESK
        jsr Setup               ; (which: the file's names, Files)
        jsr Files
        bcs @end
        jsr ReadText
        txa
        bne @fail
        lda #<text
        sta iniBase
        clc
        adc textLen
        sta r0L
        lda #>text
        sta iniBase+1
        adc textLen+1
        sta r0H
        lda #0
        tay
        sta (r0),y
        lda textLen
        sta iniLen
        lda textLen+1
        sta iniLen+1
        lda #<TEXT_MAX
        sta iniMax
        lda #>TEXT_MAX
        sta iniMax+1
        lda #0                  ; (no line of a key passed over)
        sta iniSkip
        clc
        rts
@fail:  sec
@end:   rts

; ClockAdjust (DeskRead, the text read): right after a cold start, which
; took the time from the Ultimate's clock (the kernal's guClockFresh,
; $C0FB), GEOS's clock moved by [time] adjust= (signed minutes, set by
; Settings' Time page; the user, 2026-11-13), the CIA's from it
; (FE_SETTIME, which also clears the flag). Once per cold start.
ClockAdjust:
        lda GU_CLOCK_FRESH
        bne :+
        rts
:       lda #0
        sta GU_CLOCK_FRESH
        lda #<STime
        sta r0L
        lda #>STime
        sta r0H
        lda #<KAdjust
        sta r1L
        lda #>KAdjust
        sta r1H
        jsr IniFind
        bcc :+
        rts                     ; (none)
:       sta adjLen
        lda #0
        sta delta
        sta delta+1
        sta adjNeg
        tay
        lda (r2),y
        cmp #'-'
        bne @dig
        inc adjNeg
        iny
@dig:   cpy adjLen
        bcs @sign
        lda (r2),y
        sec
        sbc #'0'
        cmp #10
        bcs @sign
        pha                     ; delta = delta * 10 + the digit
        lda delta
        ldx delta+1
        asl delta
        rol delta+1
        asl delta
        rol delta+1             ; (* 4)
        clc
        adc delta
        sta delta
        txa
        adc delta+1
        sta delta+1             ; (* 5)
        asl delta
        rol delta+1             ; (* 10)
        pla
        clc
        adc delta
        sta delta
        bcc :+
        inc delta+1
:       iny
        bne @dig
@sign:  lda adjNeg
        beq :+
        lda #0
        sec
        sbc delta
        sta delta
        lda #0
        sbc delta+1
        sta delta+1
:       lda delta
        ora delta+1
        beq @end
        jsr ClockShift
        lda #FE_SETTIME
        jmp FileEngine
@end:   rts

; KeyVal: key X's value in the text (DeskText): C clear and r0 = its
; first character (the line goes on to its CR), C set when not there.
KeyVal: jsr KeyRegs
        jsr IniFind
        bcs @end
        lda r2L
        sta r0L
        lda r2H
        sta r0H
@end:   rts

; KeyRegs: r0 = "desktop", r1 = key X's name. Keeps X.
KeyRegs:
        lda #<SDesk
        sta r0L
        lda #>SDesk
        sta r0H
        lda KeyLo,x
        sta r1L
        lda KeyHi,x
        sta r1H
        rts

KEY_THEME       = 0             ; [desktop]'s keys (KeyLo, KeyHi)
KEY_VIEW        = 1
KEY_CLOCK       = 2
KEY_TOOLBAR     = 3
KEY_PANES       = 4
KEY_PANE2       = 5
KEY_SORT        = 6
KEY_COPY        = 7
KEY_DEL         = 8
KEY_ICOLS       = 9
KEY_PRINTER     = 10
KeyLo:  .byte <KTheme, <KView, <KClock, <KToolbar, <KPanes, <KPane2, <KSort, <KCopy, <KDel
        .byte <KIcols, <KPrinter
KeyHi:  .byte >KTheme, >KView, >KClock, >KToolbar, >KPanes, >KPane2, >KSort, >KCopy, >KDel
        .byte >KIcols, >KPrinter
SDesk:          .byte "desktop", 0
STime:          .byte "time", 0
KAdjust:        .byte "adjust", 0
KTheme:         .byte "theme", 0
KView:          .byte "view", 0
KClock:         .byte "clock", 0
KToolbar:       .byte "toolbar", 0
KPanes:         .byte "panes", 0
KPane2:         .byte "pane2", 0
KSort:          .byte "sort", 0
KCopy:          .byte "copy", 0
KDel:           .byte "delete", 0
KIcols:         .byte "iconcolours", 0
KPrinter:       .byte "printer", 0
DefPrinter:     .byte "GU Epson FX-80", 0
DEF_PRN_LEN     = * - DefPrinter - 1
First:                                  ; a value's first character
ViewFirst:      .byte "lid", 0          ; list, icons, detailed
ClockFirst:     .byte "21o", 0          ; 24, 12, off
ToolbarFirst:   .byte "18o", 0          ; 16, 8, off (its height in pixels)
PanesFirst:     .byte "12", 0           ; one list, two panes
SortFirst:      .byte "ndst", 0         ; name, date, size, type
CopyFirst:      .byte "arsn", 0         ; ask, replace, skip, newer
DelFirst:       .byte "an", 0           ; ask, now
Words:
ViewWords:      .byte "list", 0, "icons", 0, "detailed", 0
ClockWords:     .byte "24", 0, "12", 0, "off", 0
ToolbarWords:   .byte "16", 0, "8", 0, "off", 0
PanesWords:     .byte "1", 0, "2", 0
SortWords:      .byte "namedatesizetype" ; (sort=, SortSave: four each)
sortVal:        .res 6          ; SortSave: "-" and the word

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
key:            .byte 0         ; SetLine: the key (KEY_*)
valPtr:         .word 0         ; SetLine: the value
delta:          .word 0         ; ClockAdjust: the minutes (clock.inc)
adjLen:         .byte 0
adjNeg:         .byte 0
textLen:        .word 0
textEnd:        .word 0

pbuf:           .res PATH_LEN   ; PanesKeep, DeskRead: the other pane's path
keepRegs:       .res 4          ; PanesKeep: r2, r3
keepR6:         .res 2

; (in the overlay: Files sets both in every call that uses them)
iniPath:        .res 48
tmpPath:        .res 48
