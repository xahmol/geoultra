; GU PostScript (docs/DESIGN.md "PostScript writer", step P1): a geoWrite
; 2.x document as a PostScript file in GEOULTRA/print, laid out as
; geoWrite lays it out, written as tools/gwps.py (gwtool ps) writes it.
; Started with a document (ST_LD_DATA: the desktop's "make PostScript",
; gush) or on its own (a file box of geoWrite documents). Step P1: the
; system font for every font (other bitmap fonts: P2; real text: P3),
; A4. Own code (GeoUltra, 2026).

        .include "psw.inc"

        .export docName, paperW, paperH
        .import FontInit, Prescan, Prolog, Pages, OutOpen, OutClose, outErr, FindFonts
        .import docWidth, hdrFlags, headH, footH, pageH, docV20
        .import __BSS_RUN__, __BSS_SIZE__, real

FindFile        = $C20B
GetFHdrInfo     = $C229
dirEntryBuf     = $8400
dispBufferOn    = $2F
ST_WR_FORE      = $80
ST_LD_DATA      = $80
OPEN            = 5
DISK            = 6
r6L             = $0E
r6H             = $0F
r9L             = $14
r9H             = $15

        .segment "ZEROPAGE"

msgLine:  .res 2                ; (DBVARSTR: zero page pointers)
nameLine: .res 2

        .segment "CODE"

; Start (GEOS: r0L the load options, dataFileName the document): the
; document chosen, written, a word about it; back to the desktop.
Start:  lda r0L                 ; (before ClearBss: options is in BSS)
        pha
        jsr ClearBss
        pla
        sta options
        lda #$80                ; real text (step P5: the options box)
        sta real
        lda #ST_WR_FORE         ; (the background screen's memory is the
        sta dispBufferOn        ; picture buffer)
        jsr Choose
        bcs @quit
        jsr Write
        jsr Report
@quit:  jmp EnterDeskTop

; ClearBss: the BSS segment zeroed (GEOS loads the file only: tables
; and counts there start as whatever the memory held). Destroys A, X, Y.
ClearBss:
        lda #<__BSS_RUN__
        sta op
        lda #>__BSS_RUN__
        sta op + 1
        ldx #>__BSS_SIZE__      ; whole pages, then the rest
        lda #0
        tay
@page:  cpx #0
        beq @rest
:       sta (op),y
        iny
        bne :-
        inc op + 1
        dex
        jmp @page
@rest:  ldy #<__BSS_SIZE__
        beq @end
:       dey
        sta (op),y
        cpy #0
        bne :-
@end:   rts

; Choose: docName = the document (dataFileName when started with one,
; else from a file box of geoWrite documents). C set: none.
Choose: lda options
        and #ST_LD_DATA
        beq @box
        lda dataFileName
        beq @box
        ldx #0
:       lda dataFileName,x
        sta docName,x
        beq :+
        inx
        cpx #16
        bcc :-
        lda #0
        sta docName,x
:       clc
        rts
@box:   lda #<docName
        sta r5L
        lda #>docName
        sta r5H
        lda #APPL_DATA
        sta r7L
        lda #<Class
        sta r10L
        lda #>Class
        sta r10H
        lda #<filesDlg
        sta r0L
        lda #>filesDlg
        sta r0H
        jsr DoDlgBox
        lda r0L
        cmp #OPEN
        bne @none
        lda docName
        beq @none
        clc
        rts
@none:  sec
        rts

; Write: the document's file header read (version, title page, header,
; footer and page heights), the record file opened, the PostScript
; written (two passes), closed. status: 0 done, else a message number.
Write:  lda #<docName
        sta r6L
        lda #>docName
        sta r6H
        jsr FindFile
        txa
        bne @read
        lda #<dirEntryBuf
        sta r9L
        lda #>dirEntryBuf
        sta r9H
        jsr GetFHdrInfo
        txa
        bne @read
        jsr Header
        jsr Open
        txa
        bne @read
        jsr FontInit
        lda #<59528             ; A4 (step P5: Letter, the options box)
        sta paperW
        lda #>59528
        sta paperW + 1
        lda #^59528
        sta paperW + 2
        lda #<84189
        sta paperH
        lda #>84189
        sta paperH + 1
        lda #^84189
        sta paperH + 2
        jsr Prescan             ; the first pass, then the document closed:
        jsr CloseRecordFile     ; the fonts' files are record files too
        jsr FindFonts           ; (one open at a time)
        jsr OutOpen
        txa
        bne @out
        jsr Prolog              ; (the fonts' images read for the glyphs)
        jsr Open                ; the document again for the pages
        txa
        bne @read2
        jsr Pages
        jsr CloseRecordFile
        jsr OutClose
        txa
        bne @out
        lda #0
        sta status
        rts
@read2: jsr OutClose
@read:  lda #MSG_READ
        sta status
        rts
@out:   lda #MSG_OUT
        sta status
        rts

; Open: the document's record file opened. X = 0 or the error.
Open:   lda #<docName
        sta r0L
        lda #>docName
        sta r0H
        jmp OpenRecordFile

; Header: from the file header (fileHeader, as on disk): docV20 ("Write
; Image V2.0": printed as a 480-dot page), hdrFlags ($8B: $80 a title
; page), headH, footH ($8C, $8E), pageH ($90; 0: 752, geoWrite's
; default).
Header: lda #0
        sta docV20
        lda fileHeader + $4D + 13       ; "V2.0": '2' '.' '0'
        cmp #'2'
        bne :+
        lda fileHeader + $4D + 15
        cmp #'0'
        bne :+
        dec docV20
:       lda fileHeader + $8B
        sta hdrFlags
        lda fileHeader + $8C
        sta headH
        lda fileHeader + $8D
        sta headH + 1
        lda fileHeader + $8E
        sta footH
        lda fileHeader + $8F
        sta footH + 1
        lda fileHeader + $90
        sta pageH
        lda fileHeader + $91
        sta pageH + 1
        ora pageH
        bne :+
        lda #<752
        sta pageH
        lda #>752
        sta pageH + 1
:       rts

; Report: what was done, in a box with OK.
Report: ldx status
        lda MsgLo,x
        sta msgLine
        lda MsgHi,x
        sta msgLine + 1
        lda #<docName
        sta nameLine
        lda #>docName
        sta nameLine + 1
        lda #<msgDlg
        sta r0L
        lda #>msgDlg
        sta r0H
        jmp DoDlgBox

MSG_DONE        = 0
MSG_READ        = 1
MSG_OUT         = 2
MsgLo:  .byte <TDone, <TRead, <TOut
MsgHi:  .byte >TDone, >TRead, >TOut
TDone:  .byte "Written to GEOULTRA/print:", 0
TRead:  .byte "This document cannot be read:", 0
TOut:   .byte "No file in GEOULTRA/print for:", 0
Class:  .byte "Write Image V2", 0

filesDlg:
        .byte DEF_DB_POS | 1
        .byte DBGETFILES, 4, 4
        .byte OPEN, 17, 4
        .byte DISK, 17, 21
        .byte CANCEL, 17, 38
        .byte 0
msgDlg: .byte DEF_DB_POS | 1
        .byte DBVARSTR, TXT_LN_X, TXT_LN_1_Y + 6, msgLine
        .byte DBVARSTR, TXT_LN_X, TXT_LN_2_Y + 6, nameLine
        .byte OK, DBI_X_2, DBI_Y_2
        .byte 0

        .segment "BSS"

options: .res 1
status: .res 1
docName: .res 17
paperW: .res 3
paperH: .res 3
