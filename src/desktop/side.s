; GeoUltra Desktop: the sidebar's favourites and recent documents
; (docs/DESKTOP.md, step D5b). Favourite folders are kept in
; SETTINGS.INI's [favourites] section, recent documents in RECENT.INI's
; [recent] section (both in the home folder, a path a line); the desktop
; reads them at its start (applications reuse its memory). Up to
; LIST_MAX of each: a favourite added at the end (the first dropped when
; full), a document opened goes to the top of the recent ones. Writing a
; file keeps its other lines (its section moves to the end): the text is
; read whole, written as a temporary file that then takes the old one's
; place, as gush's turbo -s does (sysset.s, own code). Without an
; Ultimate (VICE) the files cannot be read or written: the lists then
; live until the desktop starts again. A click on a favourite goes
; there, C=+click asks to remove it; a click on a recent document opens
; it in its folder. Own code.

        .include "geos.inc"

        .import FileEngine, SideText, SideName, SideLine, SideRedraw, rowY
        .import ListRead, ListDraw, Fetch, IsSelected, Modifiers, mods
        .import Into, Document, Ask
        .import path, entryInfo, entryName, cur, count
        .export SideLoad, SideLists, SidePress, FavAdd, RecentAdd

MoveData        = $C17E         ; GEOS jump table

FE_CLOSE        = 4
FE_DELETE       = 7
FE_RENAME       = 10
FE_CD           = 11
FE_OPEN         = 13
FE_READ         = 14
FE_WRITE        = 15
FE_HOME         = 26
FO_READ         = 0
FO_WRITE        = 1
FE_ULTIMATE     = $4F
FI_KIND         = 0
K_FOLDER        = 2
K_UDIR          = 6
MOD_CBM         = 2             ; (list.s, Modifiers)

ROW_H           = 9             ; (desktop.s)
SIDE_LAST       = 196           ; the lowest baseline in the sidebar
LIST_MAX        = 4             ; favourites, recent documents
PATH_LEN        = 63            ; a path and its zero (entryName's size:
                                ; SidePress shows one in the question)
TEXT_MAX        = 3072          ; an INI file's bytes, at most
L_FAV           = 0             ; the lists ("which")
L_REC           = 1
CODE_FAV        = $80           ; sidebar codes (desktop.s, Press):
CODE_REC        = $90           ; the list's base + the index

        .segment "ZEROPAGE"

lp:             .res 2          ; the current list's first slot
sp:             .res 2          ; its section line ("[favourites]")

        .segment "CODE"

; SideLoad: both lists from their files (empty when a file is not there
; or cannot be read).
SideLoad:
        ldx #L_FAV
        jsr Load
        ldx #L_REC
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
; again); saved, the sidebar drawn again.
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
        ldx #L_FAV
        jsr Save                ; (an error: kept until the next start)
        jmp SideRedraw
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
; line per path (its last part shown), when there are any, under the
; lines drawn so far (rowY: the last one's baseline); lines that would
; pass SIDE_LAST left out.
SideLists:
        ldx #L_FAV
        jsr List
        ldx #L_REC
List:   jsr Setup
        ldx which
        lda counts,x
        beq @end
        lda rowY
        clc
        adc #ROW_H + 2
        cmp #SIDE_LAST + 1
        bcs @end
        sta rowY
        ldx which
        lda HeadLo,x
        pha
        lda HeadHi,x
        tax
        pla
        ldy rowY
        jsr SideText
        lda #0
        sta at
@line:  lda at
        ldx which
        cmp counts,x
        bcs @end
        lda rowY
        clc
        adc #ROW_H
        cmp #SIDE_LAST + 1
        bcs @end
        sta rowY
        ldx which
        lda Codes,x
        ora at
        jsr SideLine
        lda at
        jsr Slot
        jsr LastPart
        ldy rowY
        jsr SideName
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
        ldx #L_FAV
        jsr Save
        jmp SideRedraw
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
        jsr ListDraw
        ldx #PATH_LEN - 1       ; the name to entryName now (ListDraw's
@doc:   lda docName,x           ; Fetches fill it)
        sta entryName,x
        dex
        bpl @doc
        jmp Document
@end:   rts

ListLo:         .byte <favs, <recents
ListHi:         .byte >favs, >recents
SectLo:         .byte <FavSect, <RecSect
SectHi:         .byte >FavSect, >RecSect
NameLo:         .byte <IniName, <RecName
NameHi:         .byte >IniName, >RecName
TmpLo:          .byte <IniTmp, <RecTmp
TmpHi:          .byte >IniTmp, >RecTmp
HeadLo:         .byte <FavHead, <RecHead
HeadHi:         .byte >FavHead, >RecHead
Codes:          .byte CODE_FAV, CODE_REC
FavSect:        .byte "[favourites]", 0
RecSect:        .byte "[recent]", 0
IniName:        .byte "SETTINGS.INI", 0
IniTmp:         .byte "SETTINGS.TMP", 0
RecName:        .byte "RECENT.INI", 0
RecTmp:         .byte "RECENT.TMP", 0
FavHead:        .byte BOLDON, "FAVOURITES", PLAINTEXT, 0
RecHead:        .byte BOLDON, "RECENT", PLAINTEXT, 0
RemoveText:     .byte BOLDON, "Remove from favourites?", PLAINTEXT, 0
CrLf:           .byte CR, 10, 0

        .segment "DATA"

counts:         .byte 0, 0      ; favourites, recent documents
which:          .byte 0
handle:         .byte 0
failed:         .byte 0
needNl:         .byte 0
inSect:         .byte 0
lineLen:        .byte 0
at:             .byte 0
last:           .byte 0
code:           .byte 0
workLen:        .byte 0
textLen:        .word 0
textEnd:        .word 0

        .segment "BSS"

favs:           .res LIST_MAX * (PATH_LEN + 1)
recents:        .res LIST_MAX * (PATH_LEN + 1)
work:           .res PATH_LEN + 1
docName:        .res PATH_LEN   ; (entryName's size)
iniPath:        .res 48
tmpPath:        .res 48
text:           .res TEXT_MAX + 1
