; The calls of tests/print/ep1.py (VICE): GU Epson FX-80 loaded from
; drive B and a page of BANDS bands printed (directly, or with SPOOLED
; through the spooler, which plays it from MainLoop afterwards):
; InitForPrint, StartPrint, PrintBuffer per band (the rows from DATA,
; 640 bytes each; colours from COLR, 80 bytes each, when COLSTEP is 80,
; else r2 = 0), StopPrint; with ASCII 1 instead SetNLQ, StartASCII,
; PrintASCII of the string at TEXT, StopPrint. Results: X of StartPrint
; at $02F1, of StopPrint at $02F2, of GetFile at $02EF, $02F0 = $AA when done. Own code.
; Assembled with -D SetDevice=.. -D OpenDisk=.. -D GetFile=.. -D BANDS=..
; -D COLSTEP=.. -D ASCII=0|1 -D SPOOLED=0|1 -D MainLoop=..

r0L     = $02
r0H     = $03
r1L     = $04
r1H     = $05
r2L     = $06
r2H     = $07
r6L     = $0E
r6H     = $0F
NAME    = $4E00
WORK    = $4000
DATA    = $5000
COLR    = $6A00
TEXT    = $4E80
ptr     = $02F4
cptr    = $02F6
count   = $02F3

        .org $0340
        sei
        lda #$30
        sta $01
        lda #9
        jsr SetDevice
        jsr OpenDisk
        lda #<NAME
        sta r6L
        lda #>NAME
        sta r6H
        lda #0
        sta r0L
        jsr GetFile
        stx $02EF
        jsr $7900               ; InitForPrint
.if ASCII
        jsr Work
        jsr $7915               ; SetNLQ
        jsr Work
        jsr $7912               ; StartASCII
        stx $02F1
        lda #<TEXT
        sta r0L
        lda #>TEXT
        sta r0H
        jsr Work
        jsr $790F               ; PrintASCII
        jmp Stop
.endif
        jsr Work
        jsr $7903               ; StartPrint
        stx $02F1
        lda #<DATA
        sta ptr
        lda #>DATA
        sta ptr+1
        lda #<(COLR * (COLSTEP / 80))
        sta cptr
        lda #>(COLR * (COLSTEP / 80))
        sta cptr+1
        lda #BANDS
        sta count
@band:  lda ptr
        sta r0L
        lda ptr+1
        sta r0H
        lda cptr
        sta r2L
        lda cptr+1
        sta r2H
        jsr Work
        jsr $7906               ; PrintBuffer
        clc
        lda ptr
        adc #<640
        sta ptr
        lda ptr+1
        adc #>640
        sta ptr+1
        clc
        lda cptr
        adc #COLSTEP
        sta cptr
        lda cptr+1
        adc #0
        sta cptr+1
        dec count
        bne @band
Stop:   lda #<DATA
        sta r0L
        lda #>DATA
        sta r0H
        jsr Work
        jsr $7909               ; StopPrint
        stx $02F2
        lda #$AA
        sta $02F0
.if SPOOLED
        cli                     ; on in MainLoop: the spooler plays the job
        jmp MainLoop
.endif
@stop:  jmp @stop

Work:   lda #<WORK
        sta r1L
        lda #>WORK
        sta r1H
        rts
