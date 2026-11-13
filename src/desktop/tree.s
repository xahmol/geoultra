; GeoUltra Desktop: folders copied, moved and deleted with everything
; in them (the user, 2026-11-11), and the question that keeps it safe:
; "Yes", "Yes to all", "No". Overlay 2 with the actions (actions.s calls
; PasteItem and DeleteItem per clipboard or selected entry).
;
; The walk is src/inc/treewalk.inc, shared with gush's cp -r: each
; folder's listing read whole into the application's REU (bank
; TREE_BANK) before anything in it is touched, TREE_DEPTH deep; copying
; makes each folder first, deleting removes the entries first. A move of
; a folder tries FE_MOVE first (one step on the same drive), else copies
; and deletes. A file that exists is replaced only after "Yes" (or "Yes
; to all" earlier in the same paste); a folder that is not empty is
; deleted with its contents only after "Yes" (or "Yes to all"). On the
; Ultimate a folder move is one rename and files copy with the
; Ultimate's own COPY (engine modules 83 and 84). RUN/STOP
; during a copy stops everything (ProgressBlock, FE_CANCELLED); an error
; is shown (Error) and stops it too. Own code.

        .include "geos.inc"
        .include "desktop.inc"

        .import FileEngine, Error, Dialog, ProgressStart, ProgressBlock
        .import deskPrefs
        .import progN, progTotal, entryName, entryInfo, path, text
        .export TreeStart, PasteItem, DeleteItem, Ask3

full = text                     ; (actions.s, Source: the item's path)

TREE_BANK       = 7             ; (1-4 the entry table, 5 the clipboard,
                                ; 6 the overlays)
TREE_SLOT       = 64            ; the kind, the name (61 bytes), tracks
TREE_DEPTH      = 8
TREE_TOO_MANY   = FE_BAD_PATH   ; (treewalk.inc: a level too long)
ANS_ALL         = 20            ; Ask3: YES, NO or this
VERB_DELETING   = 2             ; (list.s, ProgressStart)
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
        jsr TreeCopy
        bcs @end
        lda #OP_DELETE
        jmp WalkTop
@copy:  jmp TreeCopy
@end:   rts

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

; TreeCopy: the folder at tSrc copied as tDst (made the same size when
; it is a 1581 partition). C set: stop.
TreeCopy:
        jsr StatSrc
        jsr WalkTracks
        sta mkTracks
        lda #OP_COPY
        jmp WalkTop

; The walk (src/inc/treewalk.inc, shared with gush's cp -r) and its
; hooks: WalkFile does a file (OneFile); WalkFail and WalkSkip show the
; error about the entry (entryName: tSrc's last part) and stop the walk.
WalkFile = OneFile
WalkFailDst:
WalkFail:
WalkSkip:
        stx errX                ; (LastToEntry uses X)
        jsr LastToEntry
        ldx errX
        jmp Fail

        .include "treewalk.inc"

; OneFile: the file at tSrc copied to tDst (copying) or deleted.
OneFile:
        lda op
        bne @del
        jmp OneCopy
@del:   jsr LastToEntry         ; ("Deleting 5: name")
        jsr Counted
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
; stop. The engine gets tDst's folder, not its full path, so it names
; the copy as gush's cp does (the user, 2026-11-11: GeoWrite pasted onto
; the Ultimate came without ".cvt"): name.cvt on the Ultimate, the name
; without it back on a GEOS drive, .prg/.seq/.usr for CBM files.
OneCopy:
        jsr ImageToGeos         ; a disk image onto a GEOS drive: refused
        bcc :+                  ; (the user, 2026-11-13)
        ldx #ERR_IMAGE
        jmp Fail
:       ldy #$FF                ; tDst cut at its last "/" (its folder)
@end:   iny
        lda tDst,y
        bne @end
@slash: dey
        lda tDst,y
        cmp #'/'
        bne @slash
        sty cutAt
        lda #0
        sta tDst,y
        jsr CopyFile
        php                     ; (its result kept)
        ldy cutAt               ; tDst as it was
        lda #'/'
        sta tDst,y
        plp
        rts

; ImageToGeos: C set when tSrc is a disk image file (.d64 .d71 .d81
; .dnp .g64, any case) and tDst is on a GEOS drive A-D ("/a" to "/d"):
; disk images stay on the Ultimate's file system (DESIGN.md).
ImageToGeos:
        lda tDst + 1
        ora #$20
        cmp #'a'
        bcc @no
        cmp #'d' + 1
        bcs @no
        lda tDst + 2
        beq :+
        cmp #'/'
        bne @no
:       ldy #$FF                ; tSrc's end
@end:   iny
        lda tSrc,y
        bne @end
        cpy #5
        bcc @no
        lda tSrc - 4,y          ; ".xyz"
        cmp #'.'
        bne @no
        ldx #0
@ext:   stx extNo
        lda tSrc - 3,y
        ora #$20
        cmp ImgExt,x
        bne @next
        lda tSrc - 2,y
        ora #$20
        cmp ImgExt + 1,x
        bne @next
        lda tSrc - 1,y
        ora #$20
        cmp ImgExt + 2,x
        bne @next
        sec
        rts
@next:  ldx extNo
        inx
        inx
        inx
        cpx #IMG_EXTS * 3
        bcc @ext
@no:    clc
        rts
IMG_EXTS = 5
ImgExt: .byte "d64", "d71", "d81", "dnp", "g64"

; CopyFile: OneCopy's copy (tDst holding the target's folder).
CopyFile:
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
        lda deskPrefs           ; copy= (the user, 2026-11-12, after
        and #PREF_COPY          ; GeoDesk64): ask, replace, skip, or
        beq @ask                ; replace only an older one
        cmp #COPY_SKIP
        beq @skip
        cmp #COPY_NEWER
        bne @over
        jsr Newer
        bcc @over
@skip:  clc                     ; (left out; a move leaves it in place)
        rts
@over:  lda #FC_OVERWRITE
        sta flags
        bne @try
@ask:   lda #<ReplaceText
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

; Newer (CopyFile, copy=newer): C clear when the source (tinfo, from
; StatSrc) has a later date than the file at the target (tDst + "/" +
; its name: tDst's cut at cutAt undone for the FE_STAT); dates as year
; (80-99 before 0-79), month, day, hour, minute. Equal, older or no
; target info: C set (kept).
Newer:  ldy cutAt
        lda #'/'
        sta tDst,y
        lda #<tDst
        sta r0L
        lda #>tDst
        sta r0H
        lda #<dinfo
        sta r1L
        lda #>dinfo
        sta r1H
        lda #0
        sta r2L
        sta r2H
        lda #FE_STAT
        jsr FileEngine
        ldy cutAt
        lda #0
        sta tDst,y
        txa
        bne @old
        ldx #0
@cmp:   lda tinfo + FI_DATE,x
        jsr Century
        sta tmpA
        lda dinfo + FI_DATE,x
        jsr Century
        cmp tmpA                ; target - source: borrow when the source
        bcc @new                ; is later
        bne @old
        inx
        cpx #5
        bcc @cmp
@old:   sec
        rts
@new:   clc
        rts

; Century: A (a date byte X) made comparable: the year (X 0) 80-99 below
; 0-79 (+ 100 for 0-79).
Century:
        cpx #0
        bne @end
        cmp #80
        bcs @end
        adc #100
@end:   rts

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
extNo:          .byte 0         ; ImageToGeos: the extension tried
mode:           .byte 0         ; 0 copy, 1 move
errX:           .byte 0         ; WalkFail: the error meanwhile
cutAt:          .byte 0         ; OneCopy: where tDst's last "/" was
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
dinfo:          .res 16         ; Newer: the target's info
tmpA:           .res 1
entry:          .res TREE_SLOT
tSrc:           .res 256
tDst:           .res 256

        .segment "BSS"

repAll:         .res 1          ; "Yes to all" for replacing (this paste)
delAll:         .res 1          ; and for deleting folders (this delete)
fileNo:         .res 2          ; the files done (the progress line)
