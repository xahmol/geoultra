; GeoUltra Desktop: the sidebar's favourites and recent documents
; (docs/DESKTOP.md). Favourite folders are kept in
; SETTINGS.INI's [favourites] section, recent documents in RECENT.INI's
; [recent] section (both in the home folder, a path a line); the desktop
; reads them at its start (applications reuse its memory). Up to
; LIST_MAX of each: a favourite added at the end (the first dropped when
; full), a document opened goes to the top of the recent ones. Writing a
; file keeps its other lines (its section moves to the end): the text is
; read whole, written as a temporary file that then takes the old one's
; place (inifile.s). Without an Ultimate (VICE) the files cannot be read
; or written: the lists then live until the desktop starts again. A click on a favourite goes
; there, C=+click asks to remove it; a click on a recent document opens
; it in its folder. SETTINGS.INI's [desktop] lines are kept the same
; way (a third list, not shown): theme=, view=, clock=. The
; files themselves are read and written by inifile.s (overlay 4); the
; lists live here. Own code.

        .include "geos.inc"
        .include "desktop.inc"

        .import FileEngine, SideRedraw, SideHeading, SideItem, SideGap, SideArrows
        .import itemText, itemName, itemIcon, itemEject
        .import ThemeFiles, ThemeUse, viewMode
        .import ListRead, ListDraw, Fetch, IsSelected, Modifiers, mods
        .import IsDotDot
        .import Into, Document, Ask
        .import path, entryInfo, entryName, cur, count
        .import LoadAll, Save   ; (ovl.s: overlay 4, inifile.s)
        .export SideLoad, SideLists, SidePress, FavAdd, RecentAdd
        .export text            ; (themefile.s reads and writes a theme in it)
        .export Setup, Slot, counts, which, at, wantTheme, wantView
        .export wantToolbar, wantPanes, sortMode, deskPrefs
        .import PanesOn
        .import tbMode, Derive
        .exportzp sp            ; (inifile.s, overlay 4, uses it)

CODE_FAV        = $80           ; sidebar codes (desktop.s, Press; CODE_REC
                                ; in desktop.inc): the base + the index

        .segment "ZEROPAGE"

lp:             .res 2          ; the current list's first slot
sp:             .res 2          ; its section line ("[favourites]")

        .segment "CODE"

; SideLoad: the lists and the [desktop] wishes from the INI files
; (overlay 4, LoadAll), THEMES made or listed (overlay 1), then the theme
; named there (GeoUltra when none) and its view, or the one named.
; Called here in turn: an overlay calls no other overlay.
SideLoad:
        jsr LoadAll
        lda wantToolbar         ; (before the theme: its layout follows)
        bmi :+
        sta tbMode
:       jsr ThemeFiles
        lda #<wantTheme
        ldx #>wantTheme
        ldy wantTheme
        bne :+
        lda #<DefaultTheme
        ldx #>DefaultTheme
:       sta r0L
        stx r0H
        jsr ThemeUse
        lda wantView            ; (a view named: it wins over the theme's)
        bmi :+
        sta viewMode
:       lda wantPanes           ; ("panes=2": two panes from the start,
        bmi :+                  ; panes.s)
        beq :+
        jsr PanesOn
:       jmp Derive              ; (the icon view: its grid; the panes')

; Setup: which = X; lp, sp for list X.
Setup:  stx which
        lda ListLo,x
        sta lp
        lda ListHi,x
        sta lp+1
        lda SectLo,x
        sta sp
        lda SectHi,x
        sta sp+1
        rts

; Slot: r6 = the current list's slot A (lp + A * 64).
Slot:   ldx #0
        stx r6H
        asl a                   ; (A < 4: A * 64 fits a byte)
        asl a
        asl a
        asl a
        asl a
        asl a
        clc
        adc lp
        sta r6L
        lda lp+1
        adc #0
        sta r6H
        rts

; --- Adding and removing -------------------------------------------------------

; FavAdd (file > add favourite, C=F): the cursor's entry when it is a
; selected folder, else the current folder, at the end of the
; favourites (the first dropped when full; one already there not added
; again); the sidebar drawn again, then saved (the user saw no reaction
; while saving first, 2026-11-06).
FavAdd: jsr Here                ; the current folder
        bcs @end
        lda count
        ora count+1
        beq @add
        lda cur
        ldx cur+1
        jsr IsSelected
        beq @add
        lda cur
        ldx cur+1
        jsr Fetch
        jsr IsDotDot            ; (".." selected: the current folder)
        beq @add
        lda entryInfo + FI_KIND
        cmp #K_FOLDER
        beq :+
        cmp #K_UDIR
        bne @add
:       jsr Join                ; the selected folder
        bcs @end
@add:   ldx #L_FAV
        jsr Setup
        jsr Find
        bcc @end                ; (there already)
        lda counts + L_FAV
        cmp #LIST_MAX
        bcc :+
        lda #0                  ; full: the first dropped
        jsr Remove
:       lda counts + L_FAV
        jsr Slot
        jsr Store
        inc counts + L_FAV
        jsr SideRedraw          ; shown first: the save takes a moment
        ldx #L_FAV
        jmp Save                ; (an error: kept until the next start)
@end:   rts

; RecentAdd (open.s, Document): entryName in the current folder at the
; top of the recent documents (moved there when it is in the list);
; saved. Not drawn: an application takes the screen next.
RecentAdd:
        jsr Here
        bcs @end
        jsr Join
        bcs @end                ; (too long: not kept)
        ldx #L_REC
        jsr Setup
        jsr Find
        bcs @new
        jsr Remove              ; (there: moved to the top)
@new:   lda counts + L_REC
        cmp #LIST_MAX
        bcc :+
        dec counts + L_REC      ; full: the last dropped
:       lda #0                  ; the others down a slot
        jsr Slot
        lda r6L
        sta r0L
        clc
        adc #PATH_LEN + 1
        sta r1L
        lda r6H
        sta r0H
        adc #0
        sta r1H
        lda counts + L_REC
        jsr Bytes
        jsr MoveData
        lda #0
        jsr Slot
        jsr Store
        inc counts + L_REC
        ldx #L_REC
        jmp Save                ; (an error: kept until the next start)
@end:   rts

; Remove: slot A of the current list (Setup) taken out, the ones after
; it up a slot.
Remove: sta at
        clc
        adc #1
        jsr Slot
        lda r6L
        sta r0L
        lda r6H
        sta r0H
        lda at
        jsr Slot
        lda r6L
        sta r1L
        lda r6H
        sta r1H
        ldx which
        lda counts,x
        sec
        sbc at
        sec
        sbc #1
        jsr Bytes
        jsr MoveData            ; (r2 = 0 moves nothing)
        ldx which
        dec counts,x
        rts

; Bytes: r2 = A slots' bytes (A * 64).
Bytes:  ldx #0
        stx r2H
        asl a
        asl a
        asl a
        asl a
        asl a
        asl a
        sta r2L
        rts

; Here: work = path (the current folder); workLen its length. C set
; when it does not fit PATH_LEN.
Here:   ldy #0
@ch:    lda path,y
        sta work,y
        beq @end
        iny
        cpy #PATH_LEN - 1
        bcc @ch
        sec
        rts
@end:   sty workLen
        clc
        rts

; Join: "/" (unless work ends in one) and entryName after work. C set
; when the result does not fit PATH_LEN.
Join:   ldy workLen
        lda work-1,y
        cmp #'/'
        beq @name
        lda #'/'
        sta work,y
        iny
@name:  ldx #0
@ch:    cpy #PATH_LEN - 1
        bcs @long
        lda entryName,x
        sta work,y
        beq @end
        iny
        inx
        bne @ch
@long:  sec
        rts
@end:   sty workLen
        clc
        rts

; Find: C clear and A = the slot when work is in the current list.
Find:   lda #0
        sta at
@slot:  lda at
        ldx which
        cmp counts,x
        bcs @none
        jsr Slot
        ldy #$FF
@ch:    iny
        lda (r6),y
        cmp work,y
        bne @next
        tax
        bne @ch
        lda at
        clc
        rts
@next:  inc at
        bne @slot
@none:  sec
        rts

; Store: work into slot r6.
Store:  ldy #$FF
@ch:    iny
        lda work,y
        sta (r6),y
        bne @ch
        rts

; --- The sidebar ---------------------------------------------------------------

; SideLists (desktop.s, Sidebar): "FAVOURITES" and "RECENT", each with a
; line per path (its last part shown, a folder's or a document's icon),
; when there are any, after the sidebar's lines so far; lines that do
; not fit above the bottom left out.
SideLists:
        ldx #L_FAV
        jsr List
        ldx #L_REC
List:   jsr Setup
        ldx which
        lda counts,x
        beq @end
        jsr SideGap
        ldx which
        lda HeadLo,x
        pha
        lda HeadHi,x
        tax
        pla
        jsr SideHeading
        bcs @end                ; (no room)
        lda #0
        sta at
@line:  lda at
        ldx which
        cmp counts,x
        bcs @end
        lda at
        jsr Slot
        jsr LastPart
        sta itemText
        stx itemText+1
        lda #0
        sta itemName+1
        sta itemEject
        ldx which
        lda ItemIcons,x
        sta itemIcon
        lda Codes,x
        ora at
        jsr SideItem
        bcs @end                ; (no room)
        inc at
        bne @line
@end:   rts

; LastPart: A/X = the path at r6's last part (after its last "/"); the
; whole path when it has one part ("/a", "/usb0") or nothing follows.
LastPart:
        ldy #0
        sty last
@ch:    lda (r6),y
        beq @end
        iny
        cmp #'/'
        bne @ch
        lda (r6),y
        beq @end
        sty last
        bne @ch
@end:   lda last
        cmp #2                  ; (one part: the whole path)
        bcs :+
        lda #0
        sta last
:       lda r6L
        clc
        adc last
        pha
        lda r6H
        adc #0
        tax
        pla
        rts

; SidePress (desktop.s, Press): A = a favourite's or recent document's
; sidebar code. A favourite: its folder (C= held: asked, then removed);
; a recent document: its folder shown, the document opened (open.s,
; Document; it goes to the top of the list there).
SidePress:
        sta code
        and #$0F
        sta at
        lda code
        and #CODE_REC - CODE_FAV
        bne @recent
        ldx #L_FAV
        jsr Setup
        lda at
        jsr Slot
        jsr Modifiers
        lda mods
        and #MOD_CBM
        bne @remove
        lda r6L
        ldx r6H
        jmp Into
@remove:
        ldy #PATH_LEN - 1       ; the path in the question (Ask shows
@copy:  lda (r6),y              ; entryName: the list's next Fetch
        sta entryName,y         ; fills it again)
        dey
        bpl @copy
        lda #<RemoveText
        ldx #>RemoveText
        jsr Ask
        bne @end                ; (NO)
        ldx #L_FAV
        jsr Setup
        lda at
        jsr Remove
        jsr SideRedraw          ; shown first: the save takes a moment
        ldx #L_FAV
        jmp Save                ; (an error: kept until the next start)
@recent:
        ldx #L_REC
        jsr Setup
        lda at
        jsr Slot
        ldy #0                  ; work = the folder, docName = the name
        sty last
@ch:    lda (r6),y
        sta work,y
        beq @split
        iny
        cmp #'/'
        bne @ch
        sty last                ; (after the last "/"; sty sets no
        jmp @ch                 ; flags: Z is still cmp's)
@split: ldy last
        beq @end                ; (no folder: not a path)
        ldx #0
@name:  lda (r6),y
        sta docName,x
        beq :+
        iny
        inx
        bne @name
:       ldy last                ; the folder: up to its "/" ("/" for "/x")
        cpy #1
        beq :+
        dey
:       lda #0
        sta work,y
        lda #<work
        sta r0L
        lda #>work
        sta r0H
        lda #FE_CD
        jsr FileEngine
        txa
        bne @end                ; (gone: nothing)
        jsr ListRead
        jsr SideArrows
        jsr ListDraw
        ldx #PATH_LEN - 1       ; the name to entryName now (ListDraw's
@doc:   lda docName,x           ; Fetches fill it)
        sta entryName,x
        dex
        bpl @doc
        jmp Document
@end:   rts

DefaultTheme:   .byte "GeoUltra", 0
ListLo:         .byte <favs, <recents, <favs     ; ([desktop]: no list
ListHi:         .byte >favs, >recents, >favs     ; of its own since 2026-11-13,
                                                 ; inifile.s KeyVal, SetLine)
SectLo:         .byte <FavSect, <RecSect, <DeskSect
SectHi:         .byte >FavSect, >RecSect, >DeskSect
ItemIcons:      .byte IC_FOLDER, IC_DOC
DeskSect:       .byte "[desktop]", 0
HeadLo:         .byte <FavHead, <RecHead
HeadHi:         .byte >FavHead, >RecHead
Codes:          .byte CODE_FAV, CODE_REC
FavSect:        .byte "[favourites]", 0
RecSect:        .byte "[recent]", 0
FavHead:        .byte "Favourites", 0
RecHead:        .byte "Recent", 0
RemoveText:     .byte BOLDON, "Remove from favourites?", PLAINTEXT, 0

        .segment "DATA"

counts:         .byte 0, 0, 0   ; favourites, recent documents, [desktop]
which:          .byte 0
at:             .byte 0
last:           .byte 0
code:           .byte 0
workLen:        .byte 0

        .segment "BSS"

wantTheme:      .res WANT_LEN   ; inifile.s, DeskRead: the theme named,
wantView:       .res 1          ; the view named ($FF: none)
wantToolbar:    .res 1          ; the toolbar named ($FF: none)
wantPanes:      .res 1          ; panes= (0 one, 1 two, $FF: none)
deskPrefs:      .res 1          ; copy= and delete= (PREF_*, desktop.inc)
sortMode:       .res 1          ; sort= (sort.s Lead): 0 name, 1 date, 2
                                ; size, 3 type
favs:           .res LIST_MAX * (PATH_LEN + 1)
recents:        .res LIST_MAX * (PATH_LEN + 1)
work:           .res PATH_LEN + 1
docName:        .res PATH_LEN   ; (entryName's size)
text:           .res TEXT_MAX + 1   ; shared, one user at a time: the INI
                                ; files (inifile.s), a theme file
                                ; (themefile.s), an action's path (full:
                                ; actions.s, tree.s, mount.s), the path
                                ; line's part (cutPath, list.s), the
                                ; toolbar's home path (toolbar.s), the
                                ; icon view's icon and info at its end
                                ; (iconview.s)
