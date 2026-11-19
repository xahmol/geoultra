; File engine paths (docs/design/FILE_ENGINE.md "Paths"; engine.s has the module
; list): module 23 makes a path absolute, module 24 walks it. Own code.
;
; A path: parts separated by "/"; "/" first: from the top, else from the
; current directory (FE_CD); "." and ".." anywhere, ".." at the top stays
; there; at most FE_PATH_MAX bytes after that. The top: "a"-"d" (GEOS
; drives A-D), "e" (drive E), "usb0", "usb1", "sd" (the Ultimate). On a
; GEOS drive every part but the last must be a folder (native folder or
; 1581 partition); the last part is left in feName for the function.

        .include "geos.inc"
        .include "hw.inc"
        .include "kcalls.inc"
        .include "engine.inc"
        .include "sysdrive.inc"

        .import OvlCall, SysRAMOp, folderT, folderS, FindFile, fontsOn, sysShow

        .segment "OVL23"
        .scope Mod23

        jmp OvResolve           ; entry 0

        .include "fereu.inc"

Walk:   jsr OvlCall             ; (a stub: the return goes to the caller
        .byte 24, 0             ; of this module)

; OvResolve: r0 = a path: fePath absolute, then the walk (module 24).
; r4 the path, r5L the place in fePath, r5H in the path, r6L the start of
; a part, r6H its length.
OvResolve:
        lda r0L
        sta r4L
        lda r0H
        sta r4H
        ldx #0
        ldy #0
        lda (r4),y
        cmp #'/'
        beq @abs
        jsr Cwd                 ; relative: from the current directory
@abs:   stx r5L
        lda #0
        sta r5H
@part:  ldy r5H                 ; the next part: past the "/"s
@skip:  lda (r4),y
        beq @done
        cmp #'/'
        bne @start
        iny
        bne @skip
        beq @long
@start: sty r6L
@scan:  iny                     ; to its end
        beq @long
        lda (r4),y
        beq @eoc
        cmp #'/'
        bne @scan
@eoc:   sty r5H
        tya
        sec
        sbc r6L
        sta r6H
        ldy r6L
        lda (r4),y
        cmp #'.'
        bne @add
        lda r6H
        cmp #1
        beq @part               ; ".": nothing
        cmp #2
        bne @add
        iny
        lda (r4),y
        cmp #'.'
        bne @add
        ldx r5L                 ; "..": the last part off (fePath starts
        beq @part               ; with "/", so the search ends there)
@up:    dex
        lda fePath,x
        cmp #'/'
        bne @up
        stx r5L
        jmp @part
@add:   lda r5L                 ; "/" and the part, if they fit (the
        sec                     ; new length: at most FE_PATH_MAX)
        adc r6H
        bcs @long
        ldx r5L
        lda #'/'
        sta fePath,x
        inx
        ldy r6L
@copy:  lda (r4),y
        sta fePath,x
        inx
        iny
        cpy r5H
        bne @copy
        stx r5L
        jmp @part
@done:  ldx r5L                 ; nothing left: "/"
        bne @end
        lda #'/'
        sta fePath
        inx
@end:   lda #0
        sta fePath,x
        jmp Walk
@long:  ldx #FE_BAD_PATH
        rts
        .assert FE_PATH_MAX = 255, error, "OvResolve: lengths by the carry"

; Cwd: the current directory to fePath; X = its length, 0 for "/" (the
; parts are added after it). Destroys A, Y, r0-r3L.
Cwd:    lda #<fePath
        sta r0L
        lda #>fePath
        sta r0H
        lda #<FE_CWD
        sta r1L
        lda #>FE_CWD
        sta r1H
        lda #<(FE_PATH_MAX + 1)
        sta r2L
        lda #>(FE_PATH_MAX + 1)
        sta r2H
        ldy #REU_FETCH
        jsr ReuOp
        ldx #0
@len:   lda fePath,x
        beq @got
        inx
        bne @len                ; (no end: taken as "/")
@got:   cpx #1
        bne @end
        dex
@end:   rts

        .endscope

        .segment "OVL24"
        .scope Mod24

        jmp OvWalk              ; entry 0

        .include "feresolve.inc"

FreeSlot:                       ; (module 81: an empty slot's device)
        jsr OvlCall
        .byte 81, 15
ShowE:  jsr OvlCall             ; (module 81: drive E shown in slot A)
        .byte 81, 9

; OvWalk: fePath (absolute) to feKind, feDrive, feName; on a GEOS drive
; that drive current, from its root into every folder but the last part.
; X = 0 or an error. fePos, feEnd: the part being looked at (work area:
; the folder calls fetch this module anew).
OvWalk: lda #0
        sta feName
        sta feKind              ; FE_P_ROOT
        tax
        lda fePath+1
        beq @ret                ; "/"
        jsr Top
        bcs @ret
        lda feEnd
        sta fePos
@next:  ldx fePos               ; fePos: at the "/" before a part, or at
        lda fePath,x            ; the end
        beq @ok                 ; (the drive itself: feName empty)
        inx
        stx fePos
@scan:  lda fePath,x
        beq @last
        cmp #'/'
        beq @mid
        inx
        bne @scan
@mid:   stx feEnd               ; a folder on the way: entered (by its
        lda #0                  ; short name; the part ends here meanwhile)
        sta fePath,x
        jsr Part
        ldy feEnd
        lda #'/'
        sta fePath,y
        txa
        bne @ret
        lda #<feShort
        sta r0L
        lda #>feShort
        sta r0H
        jsr EnterR0
        txa
        bne @ret
        lda feEnd
        sta fePos
        jmp @next
@last:  jsr Part                ; the last part: feName, feShort (none
        cpx #FE_BAD_PATH        ; found: feShort 0, for a new name)
        beq @ret
@ok:    ldx #0
@ret:   rts

; Part: the part from fePos (zero-ended) to feName; its short name to
; feShort: itself (at most FE_NAME_MAX characters), else the file with
; that long name (module 48; none: feShort 0, X = FILE_NOT_FOUND). X = 0,
; FILE_NOT_FOUND or FE_BAD_PATH (more than FE_LONG_MAX characters).
Part:   ldx fePos
        ldy #0
@copy:  lda fePath,x
        sta feName,y
        beq @len
        inx
        iny
        cpy #FE_LONG_MAX + 1
        bne @copy
        ldx #FE_BAD_PATH
        rts
@len:   cpy #FE_NAME_MAX + 1
        bcs LnFind
@short: lda feName,y
        sta feShort,y
        dey
        bpl @short
        ldx #0
        rts

LnFind: jsr OvlCall             ; (module 48: a long name looked up)
        .byte 48, 0

; Top: the path's top part (fePath+1 up to feEnd). A GEOS drive: made
; current at its root (C clear). Else C set and X = the error.
Top:    ldy #1
@t:     lda fePath,y
        beq @tend
        cmp #'/'
        beq @tend
        iny
        bne @t
@tend:  sty feEnd
        cpy #2
        bne Ultimate
        lda fePath+1            ; one letter: a drive
        cmp #'e'
        beq @later
        cmp #'f'                ; /f: the system fonts (FONTS.DNP), shown
        beq @fonts              ; as E is, read-only (module 125, HideE)
        sec
        sbc #'a'
        cmp #4
        bcs @nf
        tax
        lda driveType,x
        beq @nodev
        txa
        clc
        adc #8
        sta feDrive
        lda #FE_P_GEOS
        sta feKind
        sta feTouched
        lda #1                  ; its root (folders.s: 1/1, also for a
        sta folderT,x           ; 1581); restored at the engine's end
        sta folderS,x
        lda feDrive
        jsr SetDevice
        jsr OpenDisk
        cpx #1                  ; (C set on an error)
        rts
@fonts: bit fontsOn              ; (not loaded: no such drive)
        bpl @nf
        lda #FONT_BANK
        sta sysShow
@later: jsr FreeSlot            ; drive E: shown in an empty slot for
        cpx #0                  ; this call (module 81, sysenter.s; the
        bne @eNo                ; dispatcher hides it again), its root
        sta feDrive             ; current; read-only
        jsr ShowE
        cpx #0
        bne @eNo
        lda #FE_P_GEOS
        sta feKind
        sta feTouched
        clc
        rts
@eNo:   sec
        rts
@nodev: ldx #DEV_NOT_FOUND
        sec
        rts
@nf:    ldx #FILE_NOT_FOUND
        sec
        rts

; Ultimate: is the top part one of the Ultimate's (Tops)? Then C set
; and, for a function that takes Ultimate paths (feUlt), X = 0 with
; fePos at the "/" before the last part and feName nonzero, or at the
; path's end for the top itself (feName 0); else X = FE_NOT_SUPPORTED.
; Not one: C set, X = FILE_NOT_FOUND.
Ultimate:
        ldx #0
@name:  lda Tops,x
        beq @nf
        ldy #1
@ch:    lda Tops,x
        beq @endT
        lda fePath,y            ; (either case: FAT's names are not exact)
        cmp #'A'
        bcc :+
        cmp #'Z' + 1
        bcs :+
        ora #$20
:       cmp Tops,x
        bne @skipT
        inx
        iny
        bne @ch
@endT:  cpy feEnd
        bne @nextT
        jsr ImgProbe            ; (module 88: a disk image on the way:
        bcc @img                ; gone into, the walk goes on in it)
        txa
        bne @ret
        lda #FE_P_ULTIMATE
        sta feKind
        ldx #FE_NOT_SUPPORTED
        lda feUlt
        beq @ret
        ldx #$FF                ; the last "/"
@last:  inx
        lda fePath,x
        beq @end
        cmp #'/'
        bne @last
        stx fePos
        bcs @last
@end:   ldy fePos               ; the top itself: no name
        cpy feEnd
        bcs @named
        stx fePos
        lda #0
        beq @top
@named: txa                     ; the last part: at most FE_UPART_MAX
        clc
        sbc fePos
        cmp #FE_UPART_MAX + 1
        ldx #FE_BAD_PATH
        bcs @ret
        lda #1
@top:   sta feName
        ldx #0
@ret:   sec
        rts
@skipT: inx
        lda Tops,x
        bne @skipT
@nextT: inx
        bne @name
@nf:    ldx #FILE_NOT_FOUND
        sec
@img:   rts

ImgProbe:
        jsr OvlCall
        .byte 88, 0

Tops:   .byte "usb0", 0, "usb1", 0, "sd", 0, 0

        .endscope
