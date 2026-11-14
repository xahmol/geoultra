; File engine: long names on GEOS drives (docs/FILE_ENGINE.md, "Long
; names"; engine.s has the module list): module 48 looks them up (a long
; name to its file, a file to its long name, FE_GETLONG), module 49 keeps
; GU.LONGNAMES (a record set, dropped; module 53 makes the file), module
; 50 makes short names, module 51 uses them for the functions (a
; listing's entries, rename, mkdir, FE_GETLONG), module 52 writes a copy's
; new entry. Own code. All work in the current folder of the current
; drive.

        .include "geos.inc"
        .include "hw.inc"
        .include "kcalls.inc"
        .include "engine.inc"
        .include "drvflags.inc"

        .import drvFlags
        .import OvlCall, SysRAMOp, folderT, folderS, FindFile

OFF_FNAME       = 3
OFF_DATE        = 23
CBM_USR_CLOSED  = $83

        .segment "OVL48"
        .scope Mod48

        jmp OvLnFind            ; entry 0
        jmp OvLnGet             ; entry 3

        .include "felong.inc"

; OvLnFind: the file whose long name is feName: its short name to feShort
; (zero-ended), its key to lnKey*; only while its slot still holds that
; short name. X = 0, or FILE_NOT_FOUND (feShort 0).
OvLnFind:
        jsr LnOpen
        txa
        bne @none
@rec:   ldy lnOff
        lda diskBlkBuf + LN_T,y
        beq @next               ; (a free record)
        ldx #0
@cmp:   lda diskBlkBuf + LN_LONG,y
        cmp feName,x
        bne @next
        iny
        inx
        cmp #0
        bne @cmp
        jsr Take
        jsr Valid               ; (reads the directory block)
        bcc @found
        jsr LnRead              ; (back to the records)
        txa
        bne @none
@next:  jsr LnNext
        bcc @rec
@none:  lda #0
        sta feShort
        ldx #FILE_NOT_FOUND
        rts
@found: ldx #0
        rts

; OvLnGet: the long name of the file lnKey* named feShort to feTmp. X = 0,
; or FILE_NOT_FOUND (it has none; feTmp unchanged).
OvLnGet:
        jsr LnOpen
        txa
        bne @none
@rec:   jsr LnKeyIs
        bne @next
        lda lnOff
        clc
        adc #LN_SHORT
        tay
        jsr ShortIs
        bne @next
        ldy lnOff
        ldx #0
@copy:  lda diskBlkBuf + LN_LONG,y
        sta feTmp,x
        beq @found
        iny
        inx
        cpx #FE_LONG_MAX + 1
        bne @copy
@found: ldx #0
        rts
@next:  jsr LnNext
        bcc @rec
@none:  ldx #FILE_NOT_FOUND
        rts

; Take: the record's key to lnKey*, its short name to feShort.
Take:   ldy lnOff
        lda diskBlkBuf + LN_T,y
        sta lnKeyT
        lda diskBlkBuf + LN_S,y
        sta lnKeyS
        lda diskBlkBuf + LN_O,y
        sta lnKeyO
        ldx #0
@ch:    lda diskBlkBuf + LN_SHORT,y
        cmp #$A0
        beq @end
        sta feShort,x
        iny
        inx
        cpx #FE_NAME_MAX
        bne @ch
@end:   lda #0
        sta feShort,x
        rts

; Valid: C clear when directory block lnKey* holds, at lnKeyO, a file
; named feShort.
Valid:  lda lnKeyT
        sta r1L
        lda lnKeyS
        sta r1H
        jsr ReadBuff
        txa
        bne @no
        ldy lnKeyO
        lda diskBlkBuf,y        ; (0: deleted)
        beq @no
        tya
        clc
        adc #OFF_FNAME
        tay
        jsr ShortIs
        bne @no
        clc
        rts
@no:    sec
        rts

; ShortIs: Z set when the 16-byte name at diskBlkBuf + Y ($A0-padded) is
; feShort. Destroys A, X, Y, r2L.
ShortIs:
        ldx #0
        lda #FE_NAME_MAX
        sta r2L
@ch:    lda feShort,x
        beq @pad
        inx
        bne @cmp
@pad:   lda #$A0
@cmp:   cmp diskBlkBuf,y
        bne @end
        iny
        dec r2L
        bne @ch
@end:   rts

        .endscope

        .segment "OVL49"
        .scope Mod49

        jmp OvLnSet             ; entry 0
        jmp OvLnDel             ; entry 3

        .include "felong.inc"

Create: jsr OvlCall             ; (module 53: GU.LONGNAMES made)
        .byte 53, 0
Clear:  jsr OvlCall             ; (module 53: diskBlkBuf an empty block)
        .byte 53, 3

; OvLnSet: the long name feTmp for the file lnKey* named feShort: its
; record replaced, or a free one taken, or GU.LONGNAMES grown by a block
; (made when the folder has none). X = 0 or the error.
OvLnSet:
        lda #0
        sta lnFreeT
        jsr LnOpen
        txa
        beq @rec
        cpx #FILE_NOT_FOUND
        bne @end
        jsr Create
        txa
        bne @end
@rec:   jsr LnKeyIs             ; this file's own record
        beq @put
        ldy lnOff
        lda diskBlkBuf + LN_T,y
        bne @next
        lda lnFreeT             ; the first free one
        bne @next
        lda lnBlkT
        sta lnFreeT
        lda lnBlkS
        sta lnFreeS
        lda lnOff
        sta lnFreeO
@next:  jsr LnNext
        bcc @rec
        lda lnFreeT
        beq Grow
        sta lnBlkT
        lda lnFreeS
        sta lnBlkS
        lda lnFreeO
        sta lnOff
        jsr LnRead
        txa
        bne @end
@put:   jsr Put
        jmp LnWrite
@end:   rts

; Grow: a new last block (the last one in diskBlkBuf) with the record;
; the entry's size and the BAM. X = 0 or the error.
Grow:   lda lnBlkT
        sta r3L
        lda lnBlkS
        sta r3H
        jsr SetNextFree
        txa
        bne @end
        lda r3L
        sta diskBlkBuf
        sta lnFreeT             ; (the new block, meanwhile)
        lda r3H
        sta diskBlkBuf+1
        sta lnFreeS
        jsr LnWrite             ; the old last block, linked
        txa
        bne @end
        lda lnFreeT
        sta lnBlkT
        lda lnFreeS
        sta lnBlkS
        jsr Clear
        lda #2
        sta lnOff
        jsr Put
        jsr LnWrite
        txa
        bne @end
        lda lnDirT              ; one block more in its entry
        sta r1L
        lda lnDirS
        sta r1H
        jsr ReadBuff
        txa
        bne @end
        lda lnDirO
        clc
        adc #OFF_SIZE
        tay
        lda diskBlkBuf,y
        clc
        adc #1
        sta diskBlkBuf,y
        bcc :+
        lda diskBlkBuf+1,y
        adc #0
        sta diskBlkBuf+1,y
:       jsr WriteBuff
        txa
        bne @end
        jmp PutDirHead
@end:   rts

; OvLnDel: the record of the file lnKey* dropped (none: nothing). X = 0 or
; the error.
OvLnDel:
        jsr LnOpen
        txa
        bne @none
@rec:   jsr LnKeyIs
        bne @next
        ldy lnOff
        lda #0
        sta diskBlkBuf + LN_T,y
        jmp LnWrite
@next:  jsr LnNext
        bcc @rec
@none:  ldx #0
        rts

; Put: the record at lnOff: the key, feShort ($A0-padded), feTmp. Destroys
; A, X, Y.
Put:    ldy lnOff
        lda lnKeyT
        sta diskBlkBuf + LN_T,y
        lda lnKeyS
        sta diskBlkBuf + LN_S,y
        lda lnKeyO
        sta diskBlkBuf + LN_O,y
        ldx #0
@short: lda feShort,x
        beq @pad
        sta diskBlkBuf + LN_SHORT,y
        iny
        inx
        cpx #FE_NAME_MAX
        bne @short
        beq @long
@pad:   lda #$A0
@fill:  sta diskBlkBuf + LN_SHORT,y
        iny
        inx
        cpx #FE_NAME_MAX
        bne @fill
@long:  ldy lnOff
        ldx #0
@copy:  lda feTmp,x
        sta diskBlkBuf + LN_LONG,y
        beq @end
        iny
        inx
        cpx #FE_LONG_MAX
        bne @copy
        lda #0
        sta diskBlkBuf + LN_LONG,y
@end:   rts

        .endscope

        .segment "OVL50"
        .scope Mod50

        jmp OvShort             ; entry 0

; OvShort: a short name for the long name feTmp to feShort: itself when
; it has at most FE_NAME_MAX characters; else its first 13 characters and
; "~1" to "~9", then 12 and "~10" to "~99", the first that is free in the
; current folder. X = 0, FILE_EXISTS (all taken) or a disk error.
OvShort:
        ldx #$FF
@len:   inx
        lda feTmp,x
        bne @len
        cpx #FE_NAME_MAX + 1
        bcc @copy
        ldy curDrive            ; long names off on this drive (F_NOLONG,
        lda drvFlags-8,y        ; MOUNTS.INI longnames=off): cut to
        and #F_NOLONG           ; FE_NAME_MAX, so no record is made (the
        beq @long               ; callers ask IsLongT)
        ldx #FE_NAME_MAX
        lda #0
        sta feTmp,x
@copy:  lda feTmp,x             ; (with its zero)
        sta feShort,x
        dex
        bpl @copy
        ldx #0
        rts
@long:  lda #1
        sta lnFreeO             ; (the number, meanwhile)
@try:   ldx #13                 ; the first characters
        lda lnFreeO
        cmp #10
        bcc :+
        dex
:       stx lnFreeS             ; (where "~" goes)
        lda #'~'
        sta feShort,x
        inx
        lda lnFreeO             ; the number in decimal
        ldy #'0' - 1
        sec
@tens:  iny
        sbc #10
        bcs @tens
        adc #10 + '0'
        cpy #'0'
        beq :+
        pha
        tya
        sta feShort,x
        inx
        pla
:       sta feShort,x
        inx
        lda #0
        sta feShort,x
        ldx lnFreeS             ; (the characters before "~" are feTmp's)
@base:  dex
        lda feTmp,x
        sta feShort,x
        txa
        bne @base
        lda #<feShort
        sta r6L
        lda #>feShort
        sta r6H
        jsr FindFile
        txa
        beq @taken
        cpx #FILE_NOT_FOUND
        bne @end
        ldx #0
@end:   rts
@taken: inc lnFreeO
        lda lnFreeO
        cmp #100
        bcc @try
        ldx #FILE_EXISTS
        rts

        .endscope

        .segment "OVL52"
        .scope Mod52

        jmp OvEntry             ; entry 0

        .include "fename.inc"
        .include "felen.inc"

LnSet:  jsr OvlCall             ; (module 49: the long name kept)
        .byte 49, 0

; OvEntry: a copy's new entry (cEntry, named feShort) into a free slot of
; the target folder (current), then the BAM; a long name (feTmp, more
; than FE_NAME_MAX characters) into GU.LONGNAMES. X = 0 or an error (the
; long name failing: the file stays, with its short name).
OvEntry:
        lda #0
        sta r10L
        jsr GetFreeDirBlk       ; (diskBlkBuf, r1; Y the slot)
        txa
        bne @end
        lda r1L                 ; its key
        sta lnKeyT
        lda r1H
        sta lnKeyS
        sty lnKeyO
        ldx #0
@copy:  lda cEntry,x
        sta diskBlkBuf,y
        iny
        inx
        cpx #30
        bne @copy
        tya                     ; the name, feShort
        sec
        sbc #30 - OFF_FNAME
        tay
        jsr PutName
        jsr WriteBuff
        txa
        bne @end
        jsr PutDirHead
        txa
        bne @end
        jsr IsLongT             ; a long name: its record
        beq @done
        jsr LnSet
@done:  ldx #0                  ; (best effort: the file stays when the
@end:   rts                     ; long name does not fit, docs "Long names")

        .endscope

        .segment "OVL53"
        .scope Mod53

        jmp OvCreate            ; entry 0
        jmp OvClear             ; entry 3

        .include "felong.inc"

; OvCreate: GU.LONGNAMES made in the current folder: one block of two free
; records, its entry (USR, today's date), the BAM; the block read back,
; lnOff at its first record. X = 0 or the error.
OvCreate:
        lda #1                  ; one byte: one block
        sta r2L
        lda #0
        sta r2H
        lda #<dirEntryBuf
        sta r6L
        lda #>dirEntryBuf
        sta r6H
        jsr BlkAlloc
        txa
        beq :+
        rts
:       lda r3L
        sta lnBlkT
        lda r3H
        sta lnBlkS
        jsr OvClear
        jsr LnWrite
        txa
        bne @end
        sta r10L                ; a free entry
        jsr GetFreeDirBlk       ; (diskBlkBuf, r1; Y its offset)
        txa
        bne @end
        lda r1L
        sta lnDirT
        lda r1H
        sta lnDirS
        sty lnDirO
        ldx #30                 ; the entry
        lda #0
@zero:  sta diskBlkBuf,y
        iny
        dex
        bne @zero
        ldy lnDirO
        lda #CBM_USR_CLOSED
        sta diskBlkBuf,y
        lda lnBlkT
        sta diskBlkBuf + OFF_DE_TR_SC,y
        lda lnBlkS
        sta diskBlkBuf + OFF_DE_TR_SC + 1,y
        lda #1
        sta diskBlkBuf + OFF_SIZE,y
@date:  lda year,x              ; (X = 0 from @zero)
        sta diskBlkBuf + OFF_DATE,y
        iny
        inx
        cpx #5
        bne @date
        ldy lnDirO
        ldx #0
@name:  lda LnName,x
        beq @pad
        sta diskBlkBuf + OFF_FNAME,y
        iny
        inx
        bne @name
@pad:   lda #$A0
@fill:  sta diskBlkBuf + OFF_FNAME,y
        iny
        inx
        cpx #FE_NAME_MAX
        bne @fill
        jsr WriteBuff
        txa
        bne @end
        jsr PutDirHead
        txa
        bne @end
        lda #2
        sta lnOff
        jmp LnRead
@end:   rts

; OvClear: diskBlkBuf empty, a last block of 254 bytes (two free records).
OvClear:
        lda #0
        tay
@zero:  sta diskBlkBuf,y
        iny
        bne @zero
        lda #$FF
        sta diskBlkBuf+1
        rts

        .endscope

        .segment "OVL51"
        .scope Mod51

        jmp OvPick              ; entry 0
        jmp OvDrop              ; entry 3
        jmp OvGetLong           ; entry 6
        jmp OvLongOf            ; entry 9

        .include "feresolve.inc"
MATCH_NAME      = feTmp
        .include "fematch.inc"

LnGet:  jsr OvlCall             ; (module 48: a file's long name)
        .byte 48, 3
LnDel:  jsr OvlCall             ; (module 49: its record dropped)
        .byte 49, 3

; OvPick (FE_READDIR on a GEOS folder, for module 28): the entry named
; feTmp (its short name; its key in lnKey*): GU.LONGNAMES is not listed;
; its long name, if any, to feTmp; then the handle's pattern (or, after
; LN_EXACT, the one short name, $A0-padded). C clear: listed (feShort its short name,
; also to the caller's r3 when not 0). diskBlkBuf is changed.
OvPick: ldx #FE_NAME_MAX
@short: lda feTmp,x
        sta feShort,x
        dex
        bpl @short
        ldx #$FF                ; GU.LONGNAMES: hidden
@hide:  inx
        lda feShort,x
        cmp LnName,x
        bne @shown
        cmp #0
        bne @hide
        sec
        rts
@shown: jsr OvLongOf
        lda feH + H_PAT
        cmp #LN_EXACT
        beq @exact
        jsr Match
        bcs @end
        bcc @out
@exact: ldx #0                  ; feShort against the $A0-padded name
        ldy #0
@ex:    lda feShort,y
        beq @pad
        iny
        bne @cmp
@pad:   lda #$A0
@cmp:   cmp feH + H_PAT + 1,x
        bne @no
        inx
        cpx #FE_NAME_MAX
        bne @ex
@out:   lda argR3+1             ; the short name for the caller
        beq @yes
        sta r0H
        lda argR3
        sta r0L
        ldy #$FF
@copy:  iny
        lda feShort,y
        sta (r0),y
        bne @copy
@yes:   clc
@end:   rts
@no:    sec
        rts

; OvLongOf: feTmp = the long name of the file lnKey* named feShort, else
; feShort. Only a short name with "~" can have one (module 50 makes all
; such short names).
OvLongOf:
        ldx #$FF
@tilde: inx
        lda feShort,x
        sta feTmp,x
        beq @end
        cmp #'~'
        bne @tilde
@rest:  inx                     ; (the rest copied too)
        lda feShort,x
        sta feTmp,x
        bne @rest
        jmp LnGet
@end:   rts

; OvDrop: after the file feShort (its key in lnKey*) was deleted: its
; long name's record dropped. X = 0 (a record that cannot be dropped
; stays, ignored when read: its slot no longer holds the name).
OvDrop: ldx #$FF
@tilde: inx
        lda feShort,x
        beq @end
        cmp #'~'
        bne @tilde
        jsr LnDel
@end:   ldx #0
        rts

LnName: .byte LN_NAME, 0

; FE_GETLONG: r0 = a path (by long or short name), r1 = a buffer of
; FE_LONG_MAX + 1 bytes: the file's long name, or its short name when it
; has none.
OvGetLong:
        lda argR0
        sta r0L
        lda argR0+1
        sta r0H
        jsr Resolve
        txa
        bne @end
        ldx #FE_BAD_PATH
        lda feName              ; (a drive, "/")
        beq @end
        jsr FindName
        txa
        bne @end
        lda r1L
        sta lnKeyT
        lda r1H
        sta lnKeyS
        lda r5L
        sta lnKeyO
        jsr OvLongOf            ; the long name, else the short one
        lda argR1
        sta r0L
        lda argR1+1
        sta r0H
        ldy #$FF
@copy:  iny
        lda feTmp,y
        sta (r0),y
        bne @copy
        ldx #0
@end:   rts

        .endscope

        .segment "OVL54"
        .scope Mod54

        jmp OvRename            ; entry 0
        jmp OvMkDir             ; entry 3

        .include "felen.inc"

LnFind: jsr OvlCall             ; (module 48: a long name looked up)
        .byte 48, 0
LnSet:  jsr OvlCall             ; (module 49: a record set)
        .byte 49, 0
LnDel:  jsr OvlCall             ; (module 49: a record dropped)
        .byte 49, 3
Short:  jsr OvlCall             ; (module 50: a short name made)
        .byte 50, 0
MakeDir:
        jsr OvlCall             ; (extension table +20, folders.s)
        .byte 14, 0

; OvRename (FE_RENAME and FE_SETLONG, module 27; a move in one folder,
; module 29): the file feShort (current folder; its key in cSrcE*) gets
; the name feTmp: a short one as it is, a long one with a short name
; made for it (module 50) and its record. Another file of that name
; (short or long): FILE_EXISTS. X = 0 or the error.
OvRename:
        ldx #FE_NAME_MAX        ; the old short name, kept
@old:   lda feShort,x
        sta feOld,x
        dex
        bpl @old
        jsr Taken
        bcs @end
        jsr Short
        txa
        bne @end
        ldx #$FF                ; the short name changes?
@cmp:   inx
        lda feOld,x
        cmp feShort,x
        bne @ren
        cmp #0
        bne @cmp
        beq @names
@ren:   lda #<feOld
        sta r6L
        lda #>feOld
        sta r6H
        lda #<feShort
        sta r0L
        lda #>feShort
        sta r0H
        jsr RenameFile
        txa
        bne @end
@names: lda cSrcET               ; the old record off, the new one on
        sta lnKeyT
        lda cSrcES
        sta lnKeyS
        lda cSrcEO
        sta lnKeyO
        jsr LnDel
        jsr IsLongT
        beq @done
        jsr LnSet
@done:  ldx #0
@end:   rts

; Taken: C set and X = FILE_EXISTS when another file than cSrcE* has the
; name feTmp, as its short or its long name. Destroys feName, feShort.
Taken:  ldx #FE_LONG_MAX
@copy:  lda feTmp,x
        sta feName,x
        dex
        bpl @copy
        jsr IsLongT
        bne @long
        ldx #FE_NAME_MAX
@short: lda feTmp,x
        sta feShort,x
        dex
        bpl @short
        lda #<feShort
        sta r6L
        lda #>feShort
        sta r6H
        jsr FindFile
        txa
        bne @free
        lda r1L
        sta lnKeyT
        lda r1H
        sta lnKeyS
        lda r5L
        sta lnKeyO
        jmp @which
@long:  jsr LnFind
        txa
        bne @free
@which: ldx #FILE_EXISTS        ; the file itself: free for it
        lda lnKeyT
        cmp cSrcET
        bne @taken
        lda lnKeyS
        cmp cSrcES
        bne @taken
        lda lnKeyO
        cmp cSrcEO
        bne @taken
@free:  clc
        rts
@taken: sec
        rts

; OvMkDir (FE_MKDIR, module 27; the walk's feName, feShort): a folder;
; with a long name, a short name made for it and its record. X = 0 or
; the error.
OvMkDir:
        jsr IsLongN
        beq @make               ; (a short name: feShort is it)
        ldx #FILE_EXISTS        ; that long name taken already
        lda feShort
        bne @end
        ldx #FE_LONG_MAX
@copy:  lda feName,x
        sta feTmp,x
        dex
        bpl @copy
        jsr Short
        txa
        bne @end
@make:  lda #<feShort
        sta r0L
        lda #>feShort
        sta r0H
        lda argR2
        sta r2L
        jsr MakeDir
        txa
        bne @end
        jsr IsLongN
        beq @done
        lda #<feShort           ; its key, for the record
        sta r6L
        lda #>feShort
        sta r6H
        jsr FindFile
        txa
        bne @end
        lda r1L
        sta lnKeyT
        lda r1H
        sta lnKeyS
        lda r5L
        sta lnKeyO
        jmp LnSet
@done:  ldx #0
@end:   rts

        .endscope
