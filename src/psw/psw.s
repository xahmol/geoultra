; GU PostScript (docs/design/DESIGN.md "PostScript writer", step P1): a geoWrite
; 2.x document as a PostScript file in GEOULTRA/print, laid out as
; geoWrite lays it out, written as tools/gwps.py (gwtool ps) writes it.
; Started with a document (ST_LD_DATA: the desktop's "make PostScript",
; gush) or on its own (a file box of geoWrite documents). Step P1: the
; system font for every font (other bitmap fonts: P2; real text: P3),
; A4. Own code (GeoUltra, 2026).

        .include "psw.inc"

        .export docName, paperW, paperH, ShowPage
        .import FontInit, Prescan, Prolog, Pages, OutOpen, OutClose, OutDelete, outErr, FindFonts
        .import docWidth, hdrFlags, headH, footH, pageH, docV20
        .import __BSS_RUN__, __BSS_SIZE__, real, Defaults, Options

FindFile        = $C20B
SetDevice       = $C2B0
OpenDisk        = $C2A1
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
        lda #ST_WR_FORE         ; (the background screen's memory is the
        sta dispBufferOn        ; picture buffer)
        jsr Defaults            ; paper and look from SETTINGS.INI
        jsr Choose
        bcs @quit
        jsr Options             ; the box: paper, look; OK or Cancel
        bcs @quit
        jsr Busy                ; (the progress box: the user's hand test,
        jsr Write               ; 2026-11-21: nothing showed while it wrote)
        jsr Report
@quit:  jmp EnterDeskTop

; Busy: a box in the middle of the screen, "Writing PostScript:", the
; document's name and the progress line ("reading", then ShowPage's
; "page n"). Destroys A, X, Y, r0-r4, r11, r1H.
BOX_T = 64
BOX_B = 111
BOX_L = 72
BOX_R = 247
TEXT_X = BOX_L + 8
LINE_Y = 102                    ; the progress line's baseline
Busy:   lda #0
        jsr SetPattern
        jsr i_Rectangle
        .byte BOX_T, BOX_B
        .word BOX_L, BOX_R
        jsr i_FrameRectangle
        .byte BOX_T, BOX_B
        .word BOX_L, BOX_R
        .byte $FF
        jsr UseSystemFont
        jsr i_PutString
        .word TEXT_X
        .byte BOX_T + 13
        .byte "Writing PostScript:", 0
        lda #<docName
        sta r0L
        lda #>docName
        sta r0H
        lda #<TEXT_X
        sta r11L
        lda #>TEXT_X
        sta r11H
        lda #BOX_T + 25
        sta r1H
        jsr PutString
        jsr i_PutString
        .word TEXT_X
        .byte LINE_Y
        .byte "reading", 0
        rts

; ShowPage (emit.s Pages, each page): "page n" (A = n) on the progress
; line. The layout's state is kept: r0-r11 and the font ($26-$2E: it
; measures text with the document's fonts loaded).
ShowPage:
        sta shown
        ldx #SAVE_LEN - 1
@save:  lda $02,x
        sta saved,x
        dex
        bpl @save
        lda #0                  ; the line cleared
        jsr SetPattern
        jsr i_Rectangle
        .byte LINE_Y - 8, BOX_B - 1
        .word BOX_L + 1, BOX_R - 1
        jsr UseSystemFont
        jsr i_PutString
        .word TEXT_X
        .byte LINE_Y
        .byte "page ", 0
        lda shown
        sta r0L
        lda #0
        sta r0H
        lda #%11000000          ; left-aligned, no leading zeros
        jsr PutDecimal
        ldx #SAVE_LEN - 1
@back:  lda saved,x
        sta $02,x
        dex
        bpl @back
        rts
SAVE_LEN = $2F - $02            ; r0-r15, a0... up to the font's $26-$2E

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

; Choose: docName = the document (dataFileName when started with one:
; its drive made current, DocDrive; else from a file box of geoWrite
; documents). C set: none.
Choose: lda options
        and #ST_LD_DATA
        beq @box
        lda dataFileName
        beq @box
        jsr DocDrive
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

; DocDrive: the drive whose disk is dataDiskName (A-D: the disk names
; GEOS keeps per drive, which GetFile copied the document's from) made
; current and opened, as geoWrite finds its document's drive (started
; from drive E, E is current). None: the current drive stays.
DocDrive:
        ldx #0
@drive: lda NameLo,x
        sta op
        lda NameHi,x
        sta op + 1
        ldy #15
:       lda (op),y
        cmp dataDiskName,y
        bne @next
        dey
        bpl :-
        txa                     ; this one: 8 + X
        clc
        adc #8
        jsr SetDevice
        jmp OpenDisk
@next:  inx
        cpx #4
        bcc @drive
        rts
NameLo: .byte <$841E, <$8430, <$88DC, <$88EE    ; DrACurDkNm .. DrDCurDkNm
NameHi: .byte >$841E, >$8430, >$88DC, >$88EE

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
        bne @outDel             ; (not all written: the partial file goes)
        lda #0
        sta status
        rts
@read2: jsr OutClose            ; (the document not read again: the
        jsr OutDelete           ; partial file goes)
@read:  lda #MSG_READ
        sta status
        rts
@outDel:
        jsr OutDelete
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
shown:  .res 1                  ; (ShowPage)
saved:  .res $2F - $02
docName: .res 17
paperW: .res 3
paperH: .res 3
