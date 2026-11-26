; guinfo: a GEOS application that finds GeoUltra and lists drive E
; through the file engine (docs/reference/DEVELOPER_GUIDE.md). On GEOS
; without GeoUltra it says so. A click anywhere returns to the desktop.
;
; Build (ca65/ld65 and GeoUltra's tools/dev/geosapp.py):
;   ca65 -o guinfo.o guinfo.s
;   ld65 -C guinfo.cfg -o guinfo.bin guinfo.o
;   python3 tools/dev/geosapp.py guinfo.toml guinfo.bin guinfo.cvt
;   python3 tools/geosdisk.py add mydisk.d64 guinfo.cvt

; GEOS 2.0 jump table and variables (HG2G)
Rectangle       = $C124
SetPattern      = $C139
PutString       = $C148
EnterDeskTop    = $C22C
otherPressVec   = $84A9
r0L             = $02
r0H             = $03
r1L             = $04
r1H             = $05
r2L             = $06
r2H             = $07
r3L             = $08
r3H             = $09
r4L             = $0A
r4H             = $0B
r11L            = $18
r11H            = $19

; GeoUltra (docs/reference/TECHNICAL_REFERENCE.md)
guSignature     = $C0E0         ; "GU"
guVersion       = $C0E2         ; major, minor
guExtTable      = $C0E4         ; the extension jump table's address
EXT_FILEENGINE  = 30            ; its entry: the file engine, A = function
FE_OPENDIR      = 2
FE_READDIR      = 3
FE_CLOSE        = 4
INFO_KIND       = 0             ; the info block's kind byte

        .segment "CODE"

Start:  lda #0                  ; the screen cleared (pattern 0)
        jsr SetPattern
        lda #0
        sta r2L
        lda #199
        sta r2H
        lda #0
        sta r3L
        sta r3H
        lda #<319
        sta r4L
        lda #>319
        sta r4H
        jsr Rectangle
        lda #<Quit              ; a click: back to the desktop
        sta otherPressVec
        lda #>Quit
        sta otherPressVec+1
        lda #20
        sta line
        jsr IsGeoUltra
        bcs @found
        lda #<NoGU
        ldx #>NoGU
        jmp Print               ; (and back to MainLoop)
@found: lda guVersion           ; "GeoUltra 0.9"
        ora #'0'
        sta Version + 9
        lda guVersion+1
        ora #'0'
        sta Version + 11
        lda #<Version
        ldx #>Version
        jsr Print
        lda #<PathE             ; FE_OPENDIR "/e": A = a handle
        sta r0L
        lda #>PathE
        sta r0H
        lda #FE_OPENDIR
        jsr FileEngine
        txa
        bne @end
        sta handle
@next:  lda #<Info              ; FE_READDIR: an entry's info and name
        sta r1L
        lda #>Info
        sta r1H
        lda #<Name
        sta r2L
        lda #>Name
        sta r2H
        lda #0
        sta r3L
        sta r3H
        ldy handle
        lda #FE_READDIR
        jsr FileEngine
        txa                     ; FE_END_OF_DIR (or an error): done
        bne @close
        lda line
        cmp #190                ; (the screen is full)
        bcs @close
        lda #<Name
        ldx #>Name
        jsr Print
        jmp @next
@close: ldy handle
        lda #FE_CLOSE
        jsr FileEngine
@end:   rts                     ; to GEOS's MainLoop

; IsGeoUltra: C set when GeoUltra runs ("GU" at $C0E0).
IsGeoUltra:
        clc
        lda guSignature
        cmp #'G'
        bne @no
        lda guSignature+1
        cmp #'U'
        bne @no
        sec
@no:    rts

; FileEngine: A = function, the other registers as the function needs.
; The extension table's entry is reached by a jump: it returns to our
; caller with X = 0 or an error (and A as the function gives it).
FileEngine:
        pha
        clc
        lda guExtTable
        adc #EXT_FILEENGINE
        sta vector
        lda guExtTable+1
        adc #0
        sta vector+1
        pla
        jmp (vector)

; Print: the string at A/X on the next line.
Print:  sta r0L
        stx r0H
        lda #8
        sta r11L
        lda #0
        sta r11H
        lda line
        sta r1H
        clc
        adc #10
        sta line
        jmp PutString

Quit:   jmp EnterDeskTop

NoGU:   .byte "This is not GeoUltra.", 0
Version:
        .byte "GeoUltra x.x, drive E holds:", 0
PathE:  .byte "/e", 0

line:   .byte 0
handle: .byte 0
vector: .word 0
Info:   .res 16
Name:   .res 61
