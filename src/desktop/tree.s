; GeoUltra Desktop: folders copied, moved and deleted with everything
; in them (the user, 2026-11-11), and the question that keeps it safe:
; "Yes", "Yes to all", "No". Overlay 2 with the actions (actions.s calls
; PasteItem and DeleteItem per clipboard or selected entry).
;
; The walk follows gush's cp -r (src/gush/tree.s, own code of the same
; project): a folder's listing is read whole into the application's REU
; (bank TREE_BANK, one TREE_SLOT slot per entry, each level after the one
; above it) before anything in it is touched, so no listing stays open
; (the engine has few handles) and folders can nest TREE_DEPTH deep. One
; walk for both jobs: copying (each folder made first, then its
; entries) and deleting (the entries first, then the folder). A move of
; a folder tries FE_MOVE first (one step on the same drive), else copies
; and deletes. A file that exists is replaced only after "Yes" (or "Yes
; to all" earlier in the same paste); a folder that is not empty is
; deleted with its contents only after "Yes" (or "Yes to all"). RUN/STOP
; during a copy stops everything (ProgressBlock, FE_CANCELLED); an error
; is shown (Error) and stops it too. Own code.

        .include "geos.inc"
        .include "desktop.inc"

        .import FileEngine, Error, Dialog, ProgressStart, ProgressBlock
        .import progN, progTotal, entryName, entryInfo, path, text
        .export TreeStart, PasteItem, DeleteItem, Ask3

full = text                     ; (actions.s, Source: the item's path)

TREE_BANK       = 7             ; (1-4 the entry table, 5 the clipboard,
                                ; 6 the overlays)
TREE_SLOT       = 64            ; the kind, the name (61 bytes), tracks
TREE_DEPTH      = 8
TREE_SLOTS      = $10000 / TREE_SLOT
OP_COPY         = 0             ; Walk's jobs
OP_DELETE       = 1
ANS_ALL         = 20            ; Ask3: YES, NO or this
VERB_DELETING   = 2             ; (list.s, ProgressStart)
FILE_EXISTS     = $40           ; the engine's errors
DIR_NOT_EMPTY   = $41
FE_CANCELLED    = $47
FE_BAD_PATH     = $49
FE_IS_FOLDER    = $4B
FE_NOT_SUPPORTED = $4E
PATH_END        = 254           ; a path's last place (with its zero)

        .segment "ZEROPAGE"

qLine:          .res 2          ; Ask3's question (DBVARSTR)

        .segment "OV2"

; TreeStart: a new paste or delete: no "Yes to all" given yet, no file
; counted.
TreeStart:
        lda #0
        sta repAll
        sta delAll
        sta fileNo
        sta fileNo+1
        rts

; PasteItem: the clipboard entry at full (its name in entryName) copied
; (A = 0) or moved (A = 1) into the current folder (path). C set when
; the paste stops (RUN/STOP, or an error shown).
PasteItem:
        sta mode
        ldy #$FF                ; tSrc = full
@src:   iny
        lda full,y
        sta tSrc,y
        bne @src
        sty srcLen
        ldy #$FF                ; tDst = path "/" entryName
@dst:   iny
        lda path,y
        sta tDst,y
        bne @dst
        sty dstLen
        jsr NameToDst
        bcs Fail
        jsr StatSrc             ; a folder?
        bcs @folder
        jmp OneCopy
@folder:
        jsr Inside              ; (into itself: refused)
        bcs Fail
        lda mode
        beq @copy
        jsr Paths               ; a move: in one step when the engine can
        lda #0
        sta r2L
        sta r3L
        sta r3H
        lda #FE_MOVE
        jsr FileEngine
        txa
        bne :+
        clc
        rts
:       cpx #FE_IS_FOLDER       ; (else: copied, then deleted)
        beq @copyDel
        cpx #FE_NOT_SUPPORTED
        bne Fail
@copyDel:
        jsr BothUlt             ; (not on the Ultimate alone: refused)
        bcs Fail
        jsr TreeCopy
        bcs @end
        lda #OP_DELETE
        jmp WalkTop
@copy:  jsr BothUlt
        bcs Fail
        jmp TreeCopy
@end:   rts

; BothUlt: C set, X = FE_NOT_SUPPORTED, when tSrc and tDst both lie on
; the Ultimate's file system: the engine copies no files from one
; Ultimate path to another yet (FILE_ENGINE.md), so a folder is refused
; there before anything is made (no empty tree left behind).
BothUlt:
        lda #<tSrc
        ldx #>tSrc
        jsr IsUlt
        bcc @no
        lda #<tDst
        ldx #>tDst
        jsr IsUlt
        bcc @no
        ldx #FE_NOT_SUPPORTED
        sec
        rts
@no:    clc
        rts

; IsUlt: C set when the path at A/X lies on the Ultimate (its first
; part longer than a drive's letter: "/usb0", "/sd").
IsUlt:  sta r5L
        stx r5H
        ldy #2
        lda (r5),y
        beq @no                 ; ("/b")
        cmp #'/'
        beq @no                 ; ("/b/...")
        sec
        rts
@no:    clc
        rts

; Fail: error X shown (entryName: the entry), C set: stop.
Fail:   cpx #FE_CANCELLED       ; (RUN/STOP: no error to show)
        beq :+
        jsr Error
:       sec
        rts

; DeleteItem: the entry entryName (entryInfo its kind) in the current
; folder deleted; a folder that is not empty with everything in it
; after "Yes" (or "Yes to all"). C set when the delete stops.
DeleteItem:
        lda entryInfo + FI_KIND
        cmp #K_FOLDER
        beq @folder
        cmp #K_UDIR
        beq @folder
        jsr Counted             ; "Deleting 5: name"
        lda #<entryName
        sta r0L
        lda #>entryName
        sta r0H
        lda #FE_DELETE
        jsr FileEngine
        txa
        bne Fail
        clc
        rts
@folder:
        lda #<entryName         ; empty: in one step
        sta r0L
        lda #>entryName
        sta r0H
        lda #FE_RMDIR
        jsr FileEngine
        txa
        bne :+
        clc
        rts
:       cpx #DIR_NOT_EMPTY
        bne Fail
        lda delAll              ; asked: "Delete everything in it?"
        bne @all
        lda #<EverythingText
        ldx #>EverythingText
        jsr Ask3
        cmp #NO
        bne :+
        clc                     ; (No: left as it is)
        rts
:       cmp #ANS_ALL
        bne @all
        sta delAll
@all:   ldy #$FF                ; tSrc = path "/" entryName
@p:     iny
        lda path,y
        sta tSrc,y
        bne @p
        sty srcLen
        lda #0
        sta dstLen
        jsr NameToSrc
        bcs Fail
        lda #OP_DELETE
        jmp WalkTop

; Stop: C set (the walk stops; already said). Here, not between
; WalkTop and Walk: WalkTop runs on into Walk.
Stop:   sec
        rts

; TreeCopy: the folder at tSrc copied as tDst (made the same size when
; it is a 1581 partition). C set: stop.
TreeCopy:
        jsr StatSrc
        jsr Tracks
        sta mkTracks
        lda #OP_COPY
; WalkTop: the walk A (OP_COPY, OP_DELETE) from tSrc (and tDst) down.
WalkTop:
        sta op
        lda #0
        sta depth
        sta lvSlotLo
        sta lvSlotHi
; Walk: one level: tDst made (copying), tSrc's listing read, each entry
; copied or deleted (folders one level deeper), tSrc removed afterwards
; (deleting). C set: stop.
Walk:   lda op
        bne :+
        jsr MakeDst
        bcs Stop
:       jsr List
        bcs Stop
        ldx depth
        lda #0
        sta lvIndex,x
@entry: ldx depth
        lda lvIndex,x
        cmp lvCount,x
        bcs @end
        jsr Fetch
        ldx depth
        lda srcLen
        sta lvSrcLen,x
        lda dstLen
        sta lvDstLen,x
        jsr Extend              ; the paths one part longer
        bcs @fail
        lda entry
        cmp #K_FOLDER
        beq @sub
        cmp #K_UDIR
        beq @sub
        jsr OneFile
        bcs @fail
        jmp @next
@sub:   ldx depth
        cpx #TREE_DEPTH - 1
        bcc :+
        ldx #FE_BAD_PATH        ; (deeper than the walk goes)
        jmp Fail
:       lda lvSlotLo,x          ; the next level's slots after this one's
        clc
        adc lvCount,x
        sta lvSlotLo + 1,x
        lda lvSlotHi,x
        adc #0
        sta lvSlotHi + 1,x
        lda entry + TREE_SLOT - 1
        sta mkTracks
        inc depth
        jsr Walk
        php
        dec depth
        plp
        bcs @fail
@next:  ldx depth               ; the paths as they were, the next entry
        ldy lvSrcLen,x
        sty srcLen
        lda #0
        sta tSrc,y
        ldy lvDstLen,x
        sty dstLen
        sta tDst,y
        inc lvIndex,x
        jmp @entry
@end:   lda op                  ; deleting: the folder itself, now empty
        beq @ok
        lda #<tSrc
        sta r0L
        lda #>tSrc
        sta r0H
        lda #FE_RMDIR
        jsr FileEngine
        txa
        beq @ok
        jsr LastToEntry
        jmp Fail
@ok:    clc
        rts
@fail:  sec
        rts

; OneFile: the file at tSrc copied to tDst (copying) or deleted.
OneFile:
        lda op
        bne @del
        jmp OneCopy
@del:   jsr Counted
        lda #<tSrc
        sta r0L
        lda #>tSrc
        sta r0H
        lda #FE_DELETE
        jsr FileEngine
        txa
        bne :+
        clc
        rts
:       jmp Fail

; OneCopy: the file at tSrc copied (mode 0) or moved to tDst; when tDst
; exists, replaced after "Yes" or "Yes to all", left after "No". C set:
; stop.
OneCopy:
        jsr LastToEntry         ; "Copying 14: name"
        inc fileNo
        bne :+
        inc fileNo+1
:       lda fileNo
        sta progN
        lda fileNo+1
        sta progN+1
        lda #0
        sta progTotal
        sta progTotal+1
        lda mode
        jsr ProgressStart
        lda #0                  ; (Yes to all given: replace at once)
        ldx repAll
        beq :+
        lda #FC_OVERWRITE
:       sta flags
@try:   jsr Paths
        lda flags
        sta r2L
        lda #<ProgressBlock     ; (list.s: the blocks; RUN/STOP stops)
        sta r3L
        lda #>ProgressBlock
        sta r3H
        lda mode
        clc
        adc #FE_COPY            ; (FE_MOVE = FE_COPY + 1)
        jsr FileEngine
        txa
        bne :+
        clc
        rts
:       cpx #FILE_EXISTS
        bne @fail
        lda flags               ; (asked already: an error)
        bne @fail
        lda #<ReplaceText
        ldx #>ReplaceText
        jsr Ask3
        cmp #NO
        bne :+
        clc                     ; (No: this one left out)
        rts
:       cmp #ANS_ALL
        bne :+
        sta repAll
:       lda #FC_OVERWRITE
        sta flags
        bne @try
@fail:  jmp Fail

; Counted: "Deleting 5: name" (the entry in entryName; the files counted).
Counted:
        inc fileNo
        bne :+
        inc fileNo+1
:       lda fileNo
        sta progN
        lda fileNo+1
        sta progN+1
        lda #0
        sta progTotal
        sta progTotal+1
        lda #VERB_DELETING
        jmp ProgressStart

; MakeDst: tDst made (FE_MKDIR; there already: used). C set: stop.
MakeDst:
        lda #<tDst
        sta r0L
        lda #>tDst
        sta r0H
        lda mkTracks            ; (a 1581 partition: the source's size)
        sta r2L
        lda #FE_MKDIR
        jsr FileEngine
        txa
        beq @ok
        cpx #FILE_EXISTS
        beq @ok
        jmp Fail
@ok:    clc
        rts

; List: tSrc's entries (kind, name, tracks) into this level's slots;
; lvCount their number (at most 255). C set: stop.
List:   lda #<tSrc
        sta r0L
        lda #>tSrc
        sta r0H
        lda #FE_OPENDIR
        jsr FileEngine
        sta handle              ; (A: the handle; txa would lose it)
        txa
        beq :+
        jsr LastToEntry
        jmp Fail
:       ldx depth
        sta lvCount,x
@read:  lda #<tinfo
        sta r1L
        lda #>tinfo
        sta r1H
        lda #<(entry + 1)
        sta r2L
        lda #>(entry + 1)
        sta r2H
        lda #0
        sta r3L
        sta r3H
        ldy handle
        lda #FE_READDIR
        jsr FileEngine
        txa
        bne @close
        ldx depth               ; room: 255 here, the bank's slots in all
        lda lvCount,x
        cmp #255
        bcs @full
        clc
        adc lvSlotLo,x
        lda lvSlotHi,x
        adc #0
        cmp #>TREE_SLOTS
        bcs @full
        lda tinfo + FI_KIND
        sta entry
        jsr Tracks
        sta entry + TREE_SLOT - 1
        ldx depth
        lda lvCount,x
        jsr SlotRegs
        jsr StashRAM
        ldx depth
        inc lvCount,x
        jmp @read
@close: ldy handle
        lda #FE_CLOSE
        jsr FileEngine
        clc
        rts
@full:  ldy handle              ; (too many entries: the walk stops)
        lda #FE_CLOSE
        jsr FileEngine
        jsr LastToEntry
        ldx #FE_BAD_PATH
        jmp Fail

; Fetch: this level's entry lvIndex into entry.
Fetch:  ldx depth
        lda lvIndex,x
        jsr SlotRegs
        jmp FetchRAM

; SlotRegs: r0-r3L for slot A of this level (lvSlotLo/Hi + A) <-> entry
; (slot * 64: the slot number's bytes shifted right by two).
SlotRegs:
        ldx depth
        clc
        adc lvSlotLo,x
        sta r1H
        lda lvSlotHi,x
        adc #0
        sta r2L
        lda #0
        lsr r2L
        ror r1H
        ror a
        lsr r2L
        ror r1H
        ror a
        sta r1L
        lda #<entry
        sta r0L
        lda #>entry
        sta r0H
        lda #TREE_SLOT
        sta r2L
        lda #0
        sta r2H
        lda #TREE_BANK
        sta r3L
        rts
        .assert TREE_SLOT = 64, error, "SlotRegs: 64 bytes a slot"

; Tracks: A = tinfo's size in blocks / 40 (a 1581 partition's tracks;
; at most 255). Destroys X, Y.
Tracks: lda tinfo + FI_SIZE
        sta r2L
        lda tinfo + FI_SIZE + 1
        sta r2H
        ldx #0
@sub:   lda r2L
        sec
        sbc #40
        tay
        lda r2H
        sbc #0
        bcc @end
        sta r2H
        sty r2L
        inx
        bne @sub
        dex
@end:   txa
        rts

; StatSrc: FE_STAT of tSrc into tinfo. C set: a folder (or a drive).
StatSrc:
        lda #<tSrc
        sta r0L
        lda #>tSrc
        sta r0H
        lda #<tinfo
        sta r1L
        lda #>tinfo
        sta r1H
        lda #0
        sta r2L
        sta r2H
        lda #FE_STAT
        jsr FileEngine
        txa
        bne @no
        lda tinfo + FI_KIND
        cmp #K_FOLDER
        beq @yes
        cmp #K_UDIR
        beq @yes
@no:    clc
        rts
@yes:   sec
        rts

; Inside: C set (and the error FE_BAD_PATH shown) when tDst is tSrc or
; lies in it (a folder pasted into itself).
Inside: ldy #0
@ch:    lda tSrc,y
        beq @end
        cmp tDst,y              ; (as written)
        bne @no
        iny
        bne @ch
@end:   lda tDst,y              ; tSrc ends here: tDst too, or a "/"
        beq @yes
        cmp #'/'
        bne @no
@yes:   ldx #FE_BAD_PATH
        jmp Fail
@no:    clc
        rts

; Paths: r0 = tSrc, r1 = tDst.
Paths:  lda #<tSrc
        sta r0L
        lda #>tSrc
        sta r0H
        lda #<tDst
        sta r1L
        lda #>tDst
        sta r1H
        rts

; Extend: "/" and entry's name after tSrc and (copying) tDst; entryName
; = the name. C set: a path too long (the error shown).
Extend: ldy #$FF                ; entryName = the name
@n:     iny
        lda entry + 1,y
        sta entryName,y
        bne @n
        jsr NameToSrc
        bcs @end
        lda op
        bne @end                ; (deleting: no target)
        jmp NameToDst
@end:   rts

; NameToSrc, NameToDst: "/" (unless the path ends in one) and entryName
; after tSrc / tDst. C set: too long (FE_BAD_PATH shown).
NameToSrc:
        ldx srcLen
        ldy #0
@s:     lda tSrc - 1,x          ; ("/" unless it ends in one)
        cmp #'/'
        beq @name
        lda #'/'
        sta tSrc,x
        inx
@name:  lda entryName,y
        sta tSrc,x
        beq @done
        inx
        iny
        cpx #PATH_END
        bcc @name
        jmp Long
@done:  stx srcLen
        clc
        rts
NameToDst:
        ldx dstLen
        ldy #0
        lda tDst - 1,x
        cmp #'/'
        beq @name
        lda #'/'
        sta tDst,x
        inx
@name:  lda entryName,y
        sta tDst,x
        beq @done
        inx
        iny
        cpx #PATH_END
        bcc @name
        jmp Long
@done:  stx dstLen
        clc
        rts
Long:   ldx #FE_BAD_PATH
        jmp Fail

; LastToEntry: entryName = tSrc's last part (for the progress line, a
; question or an error).
LastToEntry:
        ldy #0
        ldx #0
@find:  lda tSrc,y
        beq @copy
        iny
        cmp #'/'
        bne @find
        tya
        tax
        jmp @find
@copy:  ldy #0
@c:     lda tSrc,x
        sta entryName,y
        beq @end
        inx
        iny
        cpy #NAME_LEN - 1
        bcc @c
        lda #0
        sta entryName,y
@end:   rts

; Ask3: the question at A/X (entryName on its second line) with "Yes",
; "Yes to all", "No". A = YES, ANS_ALL or NO.
Ask3:   sta qLine
        stx qLine+1
        lda #<ask3Dlg
        sta r0L
        lda #>ask3Dlg
        sta r0H
        jsr Dialog
        lda r0L
        rts

; YesAll (the "Yes to all" button, DBUSRICON): the dialog ended so.
YesAll: lda #ANS_ALL
        sta sysDBData
        jmp RstrFrmDialogue

ask3Dlg:
        .byte DEF_DB_POS | 1
        .byte DBVARSTR, TXT_LN_X, TXT_LN_1_Y + 6, qLine
        .byte DBTXTSTR, TXT_LN_X, TXT_LN_2_Y + 6
        .word entryName
        .byte YES, DBI_X_0, DBI_Y_2
        .byte DBUSRICON, YESALL_X, DBI_Y_2
        .word yesAllRec
        .byte NO, DBI_X_2, DBI_Y_2
        .byte 0
YESALL_X        = 8             ; (8 cards wide: between Yes and No)
yesAllRec:
        .word YesAllIcon
        .byte 0, 0, 8, 16
        .word YesAll

ReplaceText:    .byte BOLDON, "Replace it?", PLAINTEXT, 0
EverythingText: .byte BOLDON, "Delete everything in it?", PLAINTEXT, 0

        .include "yesall.inc"

; The walk's state and paths (overlay data: kept while the walk runs,
; nothing else fetches an overlay meanwhile).
op:             .byte 0
mode:           .byte 0         ; 0 copy, 1 move
depth:          .byte 0
handle:         .byte 0
flags:          .byte 0
mkTracks:       .byte 0
srcLen:         .byte 0
dstLen:         .byte 0
lvIndex:        .res TREE_DEPTH
lvCount:        .res TREE_DEPTH
lvSlotLo:       .res TREE_DEPTH
lvSlotHi:       .res TREE_DEPTH
lvSrcLen:       .res TREE_DEPTH
lvDstLen:       .res TREE_DEPTH
tinfo:          .res 16
entry:          .res TREE_SLOT
tSrc:           .res 256
tDst:           .res 256

        .segment "BSS"

repAll:         .res 1          ; "Yes to all" for replacing (this paste)
delAll:         .res 1          ; and for deleting folders (this delete)
fileNo:         .res 2          ; the files done (the progress line)
