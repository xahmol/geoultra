; GeoUltra Desktop: actions on the selection (docs/DESKTOP.md).
; Copy and cut keep the source folder (srcPath) and the names of the
; selected entries (or the cursor's, when none is selected) in the
; application's REU (bank CLIP_BANK, CLIP_SIZE bytes each); paste copies
; (FE_COPY) or moves (FE_MOVE) them into the current folder, folders
; with everything in them (tree.s), asking before anything is replaced;
; after a cut-and-paste the clipboard is empty. Delete asks once for the
; selection, then removes files and folders (a folder that is not empty
; after a second question). Rename (the cursor's
; entry) and new folder ask for a name (a dialog with an input line).
; Errors are shown in a dialog and end the action. Through the file
; engine, so the Ultimate's file system is a peer of the drives (CVT on
; the way, as in gush). Own code.

        .include "geos.inc"
        .include "desktop.inc"

        .import FileEngine, ListRead, ListDraw, Fetch, IsSelected
        .import deskPrefs
        .import entryName, cur, count, path, IsDotDot
        .import Busy, Idle
        .import TreeStart, PasteItem, DeleteItem   ; (tree.s, the same overlay)
        .import text            ; (side.s's INI text holds `full` while one
full = text                     ; engine call copies, moves or mounts it)
        .import Dialog
        .export Ov_Copy, Ov_Cut, Ov_Paste, Ov_Delete, Ov_Rename, Ov_NewFolder, Ov_Ask
        .export clipCount       ; (desktop.s: 0 at the start)
Ov_Copy = Copy                  ; (overlay 2: the stubs in ovl.s)
Ov_Cut = Cut
Ov_Paste = Paste
Ov_Delete = Delete
Ov_Rename = Rename
Ov_NewFolder = NewFolder
Ov_Ask = Ask
        .import Error, Append   ; (errors.s, in the core)
        .export full            ; (mount.s: an image's path)

FE_CANCELLED    = $47

CLIP_BANK       = 5             ; (1-4: the entry table, list.s)
CLIP_SIZE       = 64            ; a name and its zero
CLIP_MAX        = 1008          ; (63 KB: the bank's last KB the other
                                ; pane's state, list.s SwapPane)
        .assert CLIP_MAX * CLIP_SIZE <= PANE_PAGE * 256, error, "clipboard: into the pane state"
NAME_MAX        = 40            ; an input line's characters

        .segment "ZEROPAGE"

askLine:        .res 2          ; (DBVARSTR: zero page pointers)
nameLine:       .res 2

        .segment "OV2"

; Copy, Cut: the selection to the clipboard (mode 0: copy, 1: move).
Copy:   lda #0
        beq Clip
Cut:    lda #1
Clip:   sta clipMode
        ldy #0                  ; the source folder
@path:  lda path,y
        sta srcPath,y
        beq :+
        iny
        bne @path
:       lda #0
        sta clipCount
        sta clipCount+1
        sta n
        sta n+1
        jsr AnySelected
        sta some
@entry: lda n                   ; each entry selected (or the cursor's)
        cmp count
        bne :+
        lda n+1
        cmp count+1
        beq @end
:       lda n
        ldx n+1
        jsr Wanted
        bcs @next
        lda n
        ldx n+1
        jsr Fetch
        jsr IsDotDot            ; (".." not copied)
        beq @next
        lda clipCount
        ldx clipCount+1
        jsr ClipPlace
        jsr StashRAM
        inc clipCount
        bne @next
        inc clipCount+1
@next:  inc n
        bne @entry
        inc n+1
        bne @entry
@end:   rts

; Wanted: C clear when entry A/X takes part: selected, or the cursor's
; when nothing is selected (some = 0).
Wanted: ldy some
        beq @cursor
        jsr IsSelected
        beq @no
        clc
        rts
@cursor:
        cmp cur
        bne @no
        cpx cur+1
        bne @no
        clc
        rts
@no:    sec
        rts

; WhatGoes: entryName = what Delete will delete, for its question: the
; one entry's name, or "N entries" (Wanted's, ".." left out, as the
; delete loop takes them; the user's test 2026-11-13: the question named
; the last entry read, another file). C set when there is none.
WhatGoes:
        lda #0
        sta n
        sta n+1
        sta goes
        sta goes+1
@entry: lda n
        cmp count
        bne :+
        lda n+1
        cmp count+1
        beq @done
:       lda n
        ldx n+1
        jsr Wanted
        bcs @next
        lda n
        ldx n+1
        jsr Fetch
        jsr IsDotDot
        beq @next
        lda goes                ; the first one kept
        ora goes+1
        bne :+
        lda n
        sta first
        lda n+1
        sta first+1
:       inc goes
        bne @next
        inc goes+1
@next:  inc n
        bne @entry
        inc n+1
        bne @entry
@done:  lda goes
        ora goes+1
        bne :+
        sec                     ; (none)
        rts
:       lda goes+1              ; one: its name
        bne @many
        lda goes
        cmp #1
        bne @many
        lda first
        ldx first+1
        jsr Fetch
        clc
        rts
@many:  ldy #0                  ; several: "N entries"
        ldx #4                  ; (powers 10000 .. 10, then the ones)
        lda #0
        sta lead
@pow:   lda #'0'
        sta digit
@sub:   lda goes
        sec
        sbc PowLo,x
        sta tmpL
        lda goes+1
        sbc PowHi,x
        bcc @dig
        sta goes+1
        lda tmpL
        sta goes
        inc digit
        bne @sub
@dig:   lda digit
        cmp #'0'
        bne :+
        lda lead
        beq @skip
        lda digit
:       sta entryName,y
        sta lead
        iny
@skip:  dex
        bne @pow
        lda goes
        ora #'0'
        sta entryName,y
        iny
        ldx #0
@w:     lda EntriesWord,x
        sta entryName,y
        beq @end
        inx
        iny
        bne @w
@end:   clc
        rts

PowLo:  .byte 0, <10, <100, <1000, <10000
PowHi:  .byte 0, >10, >100, >1000, >10000
EntriesWord:    .byte " entries", 0

; AnySelected: A nonzero when any entry is selected.
AnySelected:
        lda #0
        sta n
        sta n+1
@entry: lda n
        cmp count
        bne :+
        lda n+1
        cmp count+1
        beq @none
:       lda n
        ldx n+1
        jsr IsSelected
        bne @some
        inc n
        bne @entry
        inc n+1
        bne @entry
@none:  lda #0
        sta n
        sta n+1
        rts
@some:  lda #0
        sta n
        sta n+1
        lda #1
        rts

; ClipPlace: r0-r3 for clipboard name A/X (entryName <-> the REU).
ClipPlace:
        sta r1L                 ; n * 64: (n << 6)
        stx r1H
        ldx #6
@shift: asl r1L
        rol r1H
        dex
        bne @shift
        lda #<entryName
        sta r0L
        lda #>entryName
        sta r0H
        lda #CLIP_SIZE
        sta r2L
        lda #0
        sta r2H
        lda #CLIP_BANK
        sta r3L
        rts

; Paste: each clipboard entry copied or moved into the current folder
; (tree.s, PasteItem: folders with everything in them; "Replace it?"
; with Yes / Yes to all / No); after a cut-and-paste the clipboard is
; empty. Stops at RUN/STOP or an error (shown).
Paste:  jsr Busy                ; (the hourglass, the progress line)
        jsr TreeStart
        lda #0
        sta n
        sta n+1
@name:  lda n
        cmp clipCount
        bne :+
        lda n+1
        cmp clipCount+1
        beq @done
:       lda n
        ldx n+1
        jsr ClipPlace
        jsr FetchRAM
        jsr Source              ; srcPath "/" entryName to full
        lda clipMode
        jsr PasteItem
        bcs @reread             ; (stopped)
        inc n
        bne @name
        inc n+1
        jmp @name
@done:  lda clipMode            ; moved: the clipboard is empty
        beq @reread
        lda #0
        sta clipCount
        sta clipCount+1
@reread:
        jsr ListRead
        jsr ListDraw
        jmp Idle

; Source: full = srcPath, "/" (unless it ends in one), entryName.
Source: ldy #0
@p:     lda srcPath,y
        beq @end
        sta full,y
        iny
        bne @p
@end:   jmp Append

; Delete: after one question, each entry taking part deleted (tree.s,
; DeleteItem: a folder that is not empty with everything in it after
; "Delete everything in it?" with Yes / Yes to all / No). Stops at an
; error (shown).
Delete: jsr AnySelected
        sta some
        lda count
        ora count+1
        bne :+
        rts
:       lda deskPrefs           ; (delete=now: no question; a folder with
        and #PREF_NOASK         ; things in it is still asked, tree.s)
        bne :+
        jsr WhatGoes            ; (the question names them: entryName)
        bcs @none               ; (nothing to delete)
        lda #<DeleteText
        ldx #>DeleteText
        jsr Ask
        beq :+
@none:  rts                     ; (NO)
:       jsr Busy
        jsr TreeStart
        lda #0
        sta n
        sta n+1
@entry: lda n
        cmp count
        bne :+
        lda n+1
        cmp count+1
        beq @reread
:       lda n
        ldx n+1
        jsr Wanted
        bcs @next
        lda n
        ldx n+1
        jsr Fetch
        jsr IsDotDot            ; (".." not deleted)
        beq @next
        jsr DeleteItem
        bcs @reread             ; (stopped)
@next:  inc n
        bne @entry
        inc n+1
        bne @entry
@reread:
        jsr ListRead
        jsr ListDraw
        jmp Idle

; Rename: the cursor's entry gets the name asked for.
Rename: lda count
        ora count+1
        beq @end
        lda cur
        ldx cur+1
        jsr Fetch
        jsr IsDotDot            ; (".." not renamed)
        beq @end
        ldy #NAME_MAX           ; the old name as the start of the line
@old:   lda entryName,y
        sta input,y
        dey
        bpl @old
        lda #0
        sta input + NAME_MAX
        lda #<RenameText
        ldx #>RenameText
        jsr AskName
        bne @end
        lda #<entryName
        sta r0L
        lda #>entryName
        sta r0H
        lda #<input
        sta r1L
        lda #>input
        sta r1H
        lda #FE_RENAME
        jsr FileEngine
        txa
        beq @reread
        jsr Error
@reread:
        jsr ListRead
        jmp ListDraw
@end:   rts

; NewFolder: a folder of the name asked for in the current folder.
NewFolder:
        lda #0
        sta input
        lda #<NewText
        ldx #>NewText
        jsr AskName
        bne @end
        lda #<input
        sta r0L
        lda #>input
        sta r0H
        lda #0
        sta r2L                 ; (tracks: the default)
        lda #FE_MKDIR
        jsr FileEngine
        txa
        beq @reread
        ldy #$FF                ; (the dialog names it: entryName)
@name:  iny
        lda input,y
        sta entryName,y
        bne @name
        jsr Error
@reread:
        jsr ListRead
        jmp ListDraw
@end:   rts

; Ask: a question (the text at A/X, entryName on the second line):
; Z set for YES.
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

; AskName: the text at A/X and an input line (input, its start already
; there): Z set for OK or RETURN, with a name.
AskName:
        sta nameLine
        stx nameLine+1
        lda #<input
        sta r5L
        lda #>input
        sta r5H
        lda #<nameDlg
        sta r0L
        lda #>nameDlg
        sta r0H
        jsr Dialog
        lda r0L
        cmp #DBGETSTRING        ; (RETURN in the input line ends the
        beq :+                  ; dialog with DBGETSTRING)
        cmp #OK
        bne @end
:       lda input               ; (an empty name: as CANCEL)
        beq @cancel
        lda #0                  ; (Z set)
@end:   rts
@cancel:
        lda #1
        rts

DeleteText:     .byte BOLDON, "Delete the selection?", PLAINTEXT, 0
RenameText:     .byte BOLDON, "Rename to:", PLAINTEXT, 0
NewText:        .byte BOLDON, "New folder:", PLAINTEXT, 0

        .segment "OV2"                 ; (dialogs, scratch text)

askDlg: .byte DEF_DB_POS | 1
        .byte DBVARSTR, TXT_LN_X, TXT_LN_1_Y + 6, askLine
        .byte DBTXTSTR, TXT_LN_X, TXT_LN_2_Y + 6
        .word entryName
        .byte YES, DBI_X_0, DBI_Y_2
        .byte NO, DBI_X_2, DBI_Y_2
        .byte 0
nameDlg:
        .byte DEF_DB_POS | 1
        .byte DBVARSTR, TXT_LN_X, TXT_LN_1_Y + 6, nameLine
        .byte DBGETSTRING, TXT_LN_X, TXT_LN_2_Y, r5, NAME_MAX
        .byte OK, DBI_X_0, DBI_Y_2
        .byte CANCEL, DBI_X_2, DBI_Y_2
        .byte 0

; WhatGoes's scratch (overlay data: set in each call)
goes:           .word 0         ; the entries Delete takes
first:          .word 0         ; the first of them
tmpL:           .byte 0
lead:           .byte 0
digit:          .byte 0

        .segment "BSS"

srcPath:        .res 256
input:          .res NAME_MAX + 1
clipMode:       .res 1
clipCount:      .res 2
n:              .res 2
some:           .res 1
