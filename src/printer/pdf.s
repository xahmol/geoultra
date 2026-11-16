; GU PDF A4, GU PDF Letter: GeoUltra's printer drivers that print into
; PDF files on the Ultimate (docs/DESIGN.md "Printing", the user's
; decisions of 2026-11-16: a folder "print" in GEOULTRA, a file per
; document named after the program that printed and the date and time,
; A4 with a Letter choice). One source: assembled with LETTER defined,
; the driver reads the Letter scripts (pdfletter) instead of pdfa4. Loaded at PRINTBASE
; ($7900, up to $7F3F) with the GEOS 2.0 printer driver interface (HG2G
; chapter 11). Own code, written from Adobe's PDF Reference (1.4: the
; file structure, image masks, incremental updates); no code taken from
; anywhere.
;
; A page is one image mask, 640 x 752 dots (GetDimensions: 80 x 94
; cards, as the Epson drivers), its rows as they are (60160 bytes, the
; length known before; no filter: a coder did not fit the 1600 bytes),
; drawn 8" x 9.4" centred on the paper (the scripts'). The file is a whole PDF after every
; page: the first page writes the header, the catalog (object 1), the
; image, the page's content and the page, the page tree (object 2), an
; xref and a trailer; each further page is an incremental update (its
; three objects and the page tree again, an xref for them, a trailer
; with /Prev). GEOS gives a printer driver no "end of document", so
; nothing is left to finish. Objects: 1 catalog, 2 page tree, per page k
; from 0: 3 + 3k the image, 4 + 3k the content, 5 + 3k the page.
;
; The PDF's text is written by Emit from scripts (pdfdata.s, the file
; pdfa4 or pdfletter on drive E, read for StartPrint and StopPrint):
; text with codes (C_*) for the numbers and offsets. Files through GeoUltra's file engine
; (guExtTable + FE_ENTRY): opened for each call (FO_WRITE for the first
; page, else FO_APPEND), written through a buffer in the work area (r1),
; closed again, so no Ultimate file stays open while other programs run.
; The program's name from FE_SPOOL 5 (the job's when the spooler plays
; it), the time from GEOS's clock. ASCII printing is not offered:
; StartASCII answers an error. The driver's own variables last through a
; job (GEOS keeps a driver loaded; the spooler puts it back into its
; slot after each call).

        .include "geos.inc"

guExtTable      = $C0E4         ; GeoUltra: the extension table
FE_ENTRY        = 30            ; its file engine entry
FE_CLOSE        = 4
FE_MKDIR        = 8
FE_OPEN         = 13
FE_READ         = 14
FE_WRITE        = 15
FE_HOME         = 26
FE_SPOOL        = 33
FO_READ         = 0
FO_WRITE        = 1
FO_APPEND       = 2
CLOCK           = $8516         ; GEOS's year (two digits), month, day,
                                ; hour, minutes, seconds

CARDS           = 80            ; GetDimensions
ROWS            = 94
LINES           = ROWS * 8      ; the image's rows (752)
ROW_BYTES       = CARDS         ; 640 dots
FLUSH_AT        = 1000          ; the buffer written from here; the
DATA_AT         = 1010          ; scripts read to here (r1: 1920)
DATA_MAX        = 1920 - DATA_AT
NAME_LEN        = 13            ; FE_SPOOL 5's name
PATH_MAX        = 64

; zero page (every entry may destroy r0-r15; kept over the file engine)
wb              = r3            ; the buffer's next byte
dat             = r4            ; the row's cards
sp              = r5            ; the script being written
tp              = r6            ; a text being written
ZP_FIRST        = r3
ZP_N            = 8

        .include "pdfscript.inc"

        .segment "CODE"

        jmp InitForPrint
        jmp StartPrint
        jmp PrintBuffer
        jmp StopPrint
        jmp GetDimensions
        jmp PrintASCII
        jmp StartASCII
        jmp SetNLQ

; GetDimensions: X cards across, Y card rows, A 0. Destroys nothing else.
GetDimensions:
        ldx #CARDS
        ldy #ROWS
        lda #0
        rts

; InitForPrint: a new document (its first StartPrint makes the file).
InitForPrint:
        lda #0
        ldx #VALS - 1
:       sta vals,x
        dex
        bpl :-
SetNLQ:
PrintASCII:
        rts

; StartASCII: not offered (X = an error, carry set).
StartASCII:
        ldx #DEV_NOT_FOUND
        sec
        rts

; StartPrint (r1 the work area): the file made (the first page) or
; opened at its end; the page's image begun. X = 0, or the file engine's
; error with carry set.
StartPrint:
        jsr Begin
        jsr Scripts
        bcs @err
        lda pages
        bne @more
        jsr MakeName
        lda #0
        ldx #3
:       sta pos,x
        dex
        bpl :-
        lda #FO_WRITE
        jsr Open
        bcs @err
        lda #0                  ; SFirst
        beq @go                 ; (always)
@more:  lda #FO_APPEND
        jsr Open
        bcs @err
        lda #1                  ; SImage
@go:    jsr Script
        lda #0
        sta lines
        sta lines+1
        jmp End
@err:   rts

; PrintBuffer (r0 the cards, r1 the work area): the 8 rows (as many as
; the page still takes).
PrintBuffer:
        lda r0L
        sta dat0
        lda r0H
        sta dat0+1
        jsr Begin
        lda #FO_APPEND
        jsr Open
        bcs @err
        ldx #0
@row:   stx row
        jsr Full
        bcs @end
        clc                     ; dat: the row's byte in the first card
        lda dat0
        adc row
        sta dat
        lda dat0+1
        adc #0
        sta dat+1
        ldx #CARDS
@card:  ldy #0
        lda (dat),y
        jsr Put
        lda dat
        clc
        adc #8
        sta dat
        bcc :+
        inc dat+1
:       dex
        bne @card
        jsr Line
        ldx row
        inx
        cpx #8
        bcc @row
@end:   jmp End
@err:   rts

; StopPrint (r1 the work area): the page's rows to its height (paper),
; the stream ended, the content, the page, the page tree, the xref and
; the trailer. X as StartPrint.
StopPrint:
        jsr Begin
        jsr Scripts
        bcs @err
        lda #FO_APPEND
        jsr Open
        bcs @err
@blank: jsr Full
        bcs @text
        ldx #ROW_BYTES
        lda #0
:       jsr Put
        dex
        bne :-
        jsr Line
        jmp @blank
@text:  lda #2                  ; SStop
        jsr Script
        ldx #3                  ; the next update's /Prev
:       lda vals + V_XREF,x
        sta vals + V_PREV,x
        dex
        bpl :-
        jmp End
@err:   rts

; Full: C set when the page has all its rows. Line: a row counted.
Full:   lda lines+1
        cmp #>LINES
        bne :+
        lda lines
        cmp #<LINES
:       rts
Line:   inc lines
        bne :+
        inc lines+1
:       rts

; End: the buffer written, the file closed. X = 0 or the error, carry
; set with an error.
End:    jsr Flush
        ldy handle
        lda #FE_CLOSE
        jsr Fe
        ldx error
        cpx #1
        rts

; Begin: the buffer at r1 (empty), no error, the file engine's entry.
Begin:  lda r1L
        sta wb0
        lda r1H
        sta wb0+1
        lda #0
        sta used
        sta used+1
        sta error
        sta inPage
        lda guExtTable
        clc
        adc #FE_ENTRY
        sta feVec
        lda guExtTable+1
        adc #0
        sta feVec+1
Wb:     lda wb0
        sta wb
        lda wb0+1
        sta wb+1
        rts

; Scripts: the file pdfdata on drive E read into the work area (DATA_AT).
; Carry set and X the error when it cannot be read.
Scripts:
        lda #<DataPath
        sta r0L
        lda #>DataPath
        sta r0H
        lda #FO_READ
        sta r2L
        lda #FE_OPEN
        jsr Fe
        stx error
        cpx #1
        bcs @end
        pha
        tay
        jsr Data
        sta r1L
        stx r1H
        lda #<DATA_MAX
        sta r2L
        lda #>DATA_MAX
        sta r2H
        lda #FE_READ
        jsr Fe
        stx error
        pla
        tay
        lda #FE_CLOSE
        jsr Fe
        ldx error
        cpx #1
@end:   rts

; Data: A/X = the scripts in the work area.
Data:   lda wb0
        clc
        adc #<DATA_AT
        pha
        lda wb0+1
        adc #>DATA_AT
        tax
        pla
        rts

; Script: script A (0 SFirst, 1 SImage, 2 SStop) written: its offset
; from the file's first words (SFirst: 4).
Script: asl a
        tay
        jsr Data
        sta tp
        stx tp+1
        lda #4
        ldx #0
        dey
        bmi @at
        lda (tp),y
        dey
        tax                     ; (high byte)
        lda (tp),y
@at:    clc
        adc tp
        pha
        txa
        adc tp+1
        tax
        pla
        jmp Emit

; Fe: the file engine (A function, Y handle, r0-r2), the driver's zero
; page kept. X = its error, A its A (FE_OPEN: the handle).
Fe:     pha
        ldx #ZP_N - 1
:       lda ZP_FIRST,x
        sta zpKeep,x
        dex
        bpl :-
        pla
        jsr @go
        stx feX
        sta feA
        ldx #ZP_N - 1
:       lda zpKeep,x
        sta ZP_FIRST,x
        dex
        bpl :-
        ldx feX
        lda feA
        rts
@go:    jmp (feVec)

; Open: path opened, A the mode. Carry set and X the error.
Open:   sta r2L
        lda #<path
        sta r0L
        lda #>path
        sta r0H
        lda #FE_OPEN
        jsr Fe
        sta handle
        stx error
        cpx #1
        rts

; Flush: the buffer written (an error kept; nothing written after one).
Flush:  lda used
        ora used+1
        beq @end
        lda error
        bne @none
        lda wb0
        sta r1L
        lda wb0+1
        sta r1H
        lda used
        sta r2L
        lda used+1
        sta r2H
        ldy handle
        lda #FE_WRITE
        jsr Fe
        stx error
@none:  lda #0
        sta used
        sta used+1
        jsr Wb
@end:   rts

; Put: A into the buffer, pos counted, written out when full. A, X, Y
; kept.
Put:    sty putY
        ldy #0
        sta (wb),y
        inc wb
        bne :+
        inc wb+1
:       inc pos
        bne :+
        inc pos+1
        bne :+
        inc pos+2
        bne :+
        inc pos+3
:       inc used
        bne :+
        inc used+1
:       ldy used+1
        cpy #>FLUSH_AT
        bcc @ok
        ldy used
        cpy #<FLUSH_AT
        bcc @ok
        pha
        txa
        pha
        jsr Flush
        pla
        tax
        pla
@ok:    ldy putY
        rts

; ----------------------------------------------------------------------
; Emit: the script at A/X: text as it is (a byte of 10 or from 32 on),
; codes (C_*, each with one argument byte) for what is computed, 0 at
; its end. A code's routine gets its argument in A and goes on with
; EmitNext (sp past the code).
Emit:   sta sp
        stx sp+1
EmitNext:
        ldy #0
        lda (sp),y
        beq @end
        tax
        cpx #10
        beq @text
        cpx #32
        bcs @text
        iny
        lda (sp),y              ; the argument
        pha
        lda sp                  ; past the code and its argument
        clc
        adc #2
        sta sp
        bcc :+
        inc sp+1
:       lda CodeHi-1,x
        sta vec+1
        lda CodeLo-1,x
        sta vec
        pla
        jmp (vec)
@text:  txa
        jsr Put
        inc sp
        bne EmitNext
        inc sp+1
        bne EmitNext            ; (always)
@end:   rts
CodeLo: .byte <CObj, <CRef, <COnum, <CAt, <CEntry, <CNum, <CKids, <CSub, <CPage
CodeHi: .byte >CObj, >CRef, >COnum, >CAt, >CEntry, >CNum, >CKids, >CSub, >CPage

CObj:   jsr Obj
        jsr Num0
        lda #<ObjText
        ldx #>ObjText
        bne Text                ; (always)
CRef:   jsr Obj
        jsr Num0
        lda #<RefText
        ldx #>RefText
Text:   jsr PutText
        jmp EmitNext
COnum:  jsr Obj
        jsr Num0
        jmp EmitNext
CAt:    tax                     ; vals + A = pos
        ldy #0
:       lda pos,y
        sta vals,x
        inx
        iny
        cpy #4
        bne :-
        jmp EmitNext
CEntry: jsr Val                 ; vals + A as 10 digits, " 00000 n "
        lda #10
        jsr Num
        lda #<InUse
        ldx #>InUse
        bne Text                ; (always)
CNum:   jsr Val
        jsr Num0
        jmp EmitNext
CKids:  lda #0                  ; "5 0 R 8 0 R ..." (5 + 3k)
        sta kid
@k:     lda kid
        asl a
        adc kid
        adc #5
        jsr Small
        jsr Num0
        lda #<RefText
        ldx #>RefText
        jsr PutText
        inc kid
        lda kid
        cmp pages
        bcc @k
        jmp EmitNext
CSub:   ldx pages               ; Subs + A within the script: + 2 for an
        cpx #2                  ; update (the second page on)
        bcc :+
        adc #1                  ; (C set: + 2)
:       tax
        lda sp
        pha
        lda sp+1
        pha
        ldy Subs,x
        lda Subs+1,x
        tax
        tya
        jsr Emit
        pla
        sta sp+1
        pla
        sta sp
        jmp EmitNext
CPage:  inc pages               ; the page counted (Obj: one less)
        inc inPage
        jmp EmitNext

; Subs (C_SUB): argument 0 the xref's first part, 4 the trailer's /Prev;
; the first page's, + 2 an update's.
Subs:   .word SXref1, SXrefN, SNone, SPrev

; Val: num = vals + A.
Val:    tax
        ldy #0
:       lda vals,x
        sta num,y
        inx
        iny
        cpy #4
        bne :-
        rts

; PutText: the zero-ended text A/X.
PutText:
        sta tp
        stx tp+1
        ldy #0
:       lda (tp),y
        beq :+
        jsr Put
        iny
        bne :-
:       rts

; Obj: num = the page's object A: 3 + 3 x (the pages before) + A.
Obj:    sta arg
        lda pages
        sec
        sbc inPage
        sta num
        asl a
        adc num
        adc #3
        adc arg
Small:  sta num                 ; num = A
        lda #0
        sta num+1
        sta num+2
        sta num+3
        rts

; Num0: num in decimal. Num: with A digits at least (zeros in front).
; Digits: num's digits into digs, the last first, A at least; X their
; count. All destroy num, Y.
Num0:   lda #0
Num:    jsr Digits
:       lda digs-1,x
        jsr Put
        dex
        bne :-
        rts
Digits: sta width
        ldx #0
@d:     lda #0                  ; num / 10, A the rest
        ldy #32
@b:     asl num
        rol num+1
        rol num+2
        rol num+3
        rol a
        cmp #10
        bcc :+
        sbc #10
        inc num
:       dey
        bne @b
        ora #'0'
        sta digs,x
        inx
        lda num
        ora num+1
        ora num+2
        ora num+3
        bne @d
@w:     cpx width
        bcs :+
        lda #'0'
        sta digs,x
        inx
        bne @w
:       rts

; ----------------------------------------------------------------------
; MakeName: path = the home folder, "print" (made when not there), "/",
; the program's letters and digits ("print" when none), then
; "-20YYMMDD-HHMMSS.pdf" from GEOS's clock.
MakeName:
        lda #<path
        sta r1L
        lda #>path
        sta r1H
        lda #FE_HOME            ; ("/USB0/GEOULTRA/")
        jsr Fe
        ldx #$FF
:       inx
        lda path,x
        bne :-
        stx at
        lda #<Folder
        ldx #>Folder
        jsr Add
        lda #<path              ; (there already: an error, not minded)
        sta r0L
        lda #>path
        sta r0H
        lda #0
        sta r2L
        lda #FE_MKDIR
        jsr Fe
        lda #'/'
        jsr Char
        lda #0                  ; the program's name
        sta prog
        lda #<prog
        sta r0L
        lda #>prog
        sta r0H
        ldy #5
        lda #FE_SPOOL
        jsr Fe
        lda at
        sta mark
        ldy #0
@ch:    lda prog,y
        beq @named
        cmp #'0'
        bcc @skip
        cmp #'9' + 1
        bcc @keep
        ora #$20
        cmp #'a'
        bcc @skip
        cmp #'z' + 1
        bcs @skip
        lda prog,y              ; (its own case)
@keep:  jsr Char
@skip:  iny
        cpy #NAME_LEN - 1
        bcc @ch
@named: lda at
        cmp mark
        bne :+
        lda #<Folder            ; none: "print"
        ldx #>Folder
        jsr Add
:       lda #<Stamp
        ldx #>Stamp
        jsr Add                 ; "-20"
        ldy #0
@t:     cpy #3
        bne :+
        lda #'-'
        jsr Char
:       sty mark
        lda CLOCK,y
        jsr Small
        lda #2
        jsr Digits
        lda digs+1
        jsr Char
        lda digs
        jsr Char
        ldy mark
        iny
        cpy #6
        bcc @t
        lda #<Ext
        ldx #>Ext
; Add: the zero-ended text A/X added to path (its zero too, not
; counted). Char: A added to path. Both keep Y.
Add:    sta tp
        stx tp+1
        sty addY
        ldy #0
:       ldx at
        lda (tp),y              ; (Z: its zero, after ldx)
        sta path,x
        beq :+
        inc at
        iny
        bne :-
:       ldy addY
        rts
Char:   ldx at
        sta path,x
        inc at
        rts

; ----------------------------------------------------------------------
; The small scripts and texts (the large ones: pdfdata.s).
SXref1: .byte "0 6", 10, "0000000000 65535 f ", 10, C_ENTRY, V_CAT, C_ENTRY, V_TREE, 0
SXrefN: .byte "2 1", 10, C_ENTRY, V_TREE, C_ONUM, 0, " 3", 10, 0
SPrev:  .byte " /Prev ", C_NUM, V_PREV
SNone:  .byte 0
ObjText:.byte " 0 obj", 10, 0
RefText:.byte " 0 R ", 0
InUse:  .byte " 00000 n ", 10, 0
Folder: .byte "print", 0
DataPath:
.ifdef LETTER
        .byte "/e/pdfletter", 0
.else
        .byte "/e/pdfa4", 0
.endif
Stamp:  .byte "-20", 0
Ext:    .byte ".pdf", 0

; ----------------------------------------------------------------------
        .segment "BSS"
vals:   .res VALS               ; (V_*)
pages = vals + V_PAGES          ; (its low byte)
pos:    .res 4                  ; bytes in the file
num:    .res 4
digs:   .res 10
lines:  .res 2                  ; the page's rows written
handle: .res 1
error:  .res 1
feVec:  .res 2
feX:    .res 1
feA:    .res 1
vec:    .res 2
wb0:    .res 2
used:   .res 2
dat0:   .res 2
row:    .res 1
at:     .res 1
mark:   .res 1
kid:    .res 1
arg:    .res 1
width:  .res 1
inPage: .res 1
putY:   .res 1
addY:   .res 1
zpKeep: .res ZP_N
prog:   .res NAME_LEN
path:   .res PATH_MAX
