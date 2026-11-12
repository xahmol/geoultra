; INI files in and out (docs/SETTINGS.md, "Structure"): a file in the
; home folder (GEOULTRA on the Ultimate) read whole into ini.inc's
; buffer, and written back through a temporary file that then takes the
; old one's place, so a failed write never leaves half a file. Shared
; code, own design (the same steps as the desktop's inifile.s and gush's
; turbo -s, which move onto this later).
;
; The includer includes engine.inc and ini.inc first (INI_BUF, INI_MAX,
; iniLen) and provides FileEngine (A = the function, X = the error
; after it). Exports IniPaths, IniLoad, IniSave. All destroy A, X, Y,
; r0-r2.

        .export IniPaths, IniLoad, IniSave

INI_PATH_MAX    = 48            ; the home folder (FE_HOME: up to 32) and
                                ; a name

; IniPaths: r0 = the file's name ("SETTINGS.INI"), r1 = its temporary
; name ("SETTINGS.TMP"): iniPath and iniTmp in the home folder. C set
; when there is no home folder (no Ultimate: nothing to read or write).
IniPaths:
        lda r0L
        sta iniName
        lda r0H
        sta iniName+1
        lda r1L
        sta iniTName
        lda r1H
        sta iniTName+1
        lda #<iniPath
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
:       ldx #0                  ; iniTmp = the home folder too
@home:  lda iniPath,x
        sta iniTmp,x
        beq @names
        inx
        cpx #32
        bne @home
@names: lda iniName
        sta r0L
        lda iniName+1
        sta r0H
        lda iniTName
        sta r1L
        lda iniTName+1
        sta r1H
        ldy #0                  ; the names after it (both the same length
@ch:    lda (r0),y              ; at most: INI_PATH_MAX)
        sta iniPath,x
        lda (r1),y
        sta iniTmp,x
        lda (r0),y
        beq @end
        inx
        iny
        cpx #INI_PATH_MAX - 1
        bcc @ch
        lda #0
        sta iniPath,x
        sta iniTmp,x
@end:   clc
        rts

; IniLoad (after IniPaths): the file into INI_BUF, iniLen its length,
; the zero after it; a file not there: an empty text. X = 0 or the
; error (FE_ULTIMATE: larger than INI_MAX, not to be rewritten).
IniLoad:
        lda #0
        sta iniLen
        sta iniLen+1
        sta INI_BUF
        lda #<iniPath
        sta r0L
        lda #>iniPath
        sta r0H
        lda #FO_READ
        sta r2L
        lda #FE_OPEN
        jsr FileEngine
        sta iniHandle           ; (A: the handle; txa would lose it)
        cpx #FILE_NOT_FOUND
        beq @none
        txa
        bne @end
        lda #<INI_BUF
        sta r1L
        lda #>INI_BUF
        sta r1H
        lda #<(INI_MAX + 1)     ; (one more than fits: too large is seen)
        sta r2L
        lda #>(INI_MAX + 1)
        sta r2H
        lda #FE_READ
        ldy iniHandle
        jsr FileEngine
        lda r2L
        sta iniLen
        lda r2H
        sta iniLen+1
        txa
        pha
        lda #FE_CLOSE
        ldy iniHandle
        jsr FileEngine
        pla
        tax
        bne @fail
        lda iniLen              ; larger than INI_MAX?
        cmp #<(INI_MAX + 1)
        lda iniLen+1
        sbc #>(INI_MAX + 1)
        bcc @zero
        ldx #FE_ULTIMATE
@fail:  lda #0                  ; (an error: an empty text, not written)
        sta iniLen
        sta iniLen+1
        sta INI_BUF
        rts
@zero:  lda #<INI_BUF           ; the zero after the text
        clc
        adc iniLen
        sta r0L
        lda #>INI_BUF
        adc iniLen+1
        sta r0H
        lda #0
        tay
        sta (r0),y
@none:  ldx #0
@end:   rts

; IniSave (after IniPaths): the text written as iniTmp, then the old
; file deleted and iniTmp renamed to its name. X = 0 or the error (a
; failed write: iniTmp deleted, the old file kept).
IniSave:
        lda #<iniTmp
        sta r0L
        lda #>iniTmp
        sta r0H
        lda #FO_WRITE
        sta r2L
        lda #FE_OPEN
        jsr FileEngine
        sta iniHandle
        txa
        bne @end
        lda #<INI_BUF
        sta r1L
        lda #>INI_BUF
        sta r1H
        lda iniLen
        sta r2L
        lda iniLen+1
        sta r2H
        lda #FE_WRITE
        ldy iniHandle
        jsr FileEngine
        stx iniFail
        lda #FE_CLOSE
        ldy iniHandle
        jsr FileEngine
        txa                     ; (a failed close: the file may be short)
        ora iniFail
        beq @swap
        sta iniFail
        lda #<iniTmp            ; failed: the new one away, the old kept
        sta r0L
        lda #>iniTmp
        sta r0H
        lda #FE_DELETE
        jsr FileEngine          ; (its own error: nothing more to do)
        ldx iniFail
@end:   rts
@swap:  lda #<iniPath           ; the old one away (FILE_NOT_FOUND: there
        sta r0L                 ; was none), the new one in its place
        lda #>iniPath
        sta r0H
        lda #FE_DELETE
        jsr FileEngine
        lda #<iniTmp
        sta r0L
        lda #>iniTmp
        sta r0H
        lda iniName
        sta r1L
        lda iniName+1
        sta r1H
        lda #FE_RENAME
        jmp FileEngine

        .pushseg
        .segment "BSS"
iniPath:        .res INI_PATH_MAX
iniTmp:         .res INI_PATH_MAX
iniName:        .res 2
iniTName:       .res 2
iniHandle:      .res 1
iniFail:        .res 1
        .popseg
