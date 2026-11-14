; File engine: the clocks from an NTP server (docs/FILE_ENGINE.md
; "Functions"; engine.s has the module list): module 76 FE_NTP (the
; exchange with the server through the Ultimate's network target), module
; 77 SETTINGS.INI read and module 79 its [time] section, module 78 the
; time made a date and the clocks set (through FE_SETTIME, module 75).
;
; Based on GeoUTime (GeoUTools, Xander Mol: src/geoutime.c get_ntp_time,
; src/time_common.c unix_to_datetime; GPL v3), which took the NTP
; exchange from ntp2ultimate by MaxPlap (github.com/MaxPlap/ntp2ultimate).
; Adapted: assembler; the request, the reads (four, a second apart) and
; the date arithmetic as there; the offset and server from SETTINGS.INI;
; GEOS's clock and the CIA's time of day set too.

        .include "geos.inc"
        .include "hw.inc"
        .include "kcalls.inc"
        .include "engine.inc"

        .import OvlCall, SysRAMOp

U_NET           = 3             ; the network target
N_UDP           = $08           ; its commands: UDP connect, close, read,
N_CLOSE         = $09           ; write
N_READ          = $10
N_WRITE         = $11
NTP_PORT        = 123
NTP_LEN         = 48            ; a request, a reply
NTP_FIRST       = $1B           ; the request's first byte: version 3, client
NTP_SECONDS     = 2 + 32        ; the reply's seconds in the read's data (its
                                ; length first; GeoUTime's uii_data[34])
TRIES           = 4
TEXT            = diskBlkBuf    ; SETTINGS.INI, a part at a time (modules
TEXT_MAX        = $1FF          ; 77, 79; fileHeader after diskBlkBuf)
        .assert fileHeader = diskBlkBuf + $100, error, "TEXT: two pages"
; SETTINGS.INI read in parts (modules 77, 79; free until module 78):
tail            = nDays         ; the unfinished line kept at TEXT (word)
cut             = nRest         ; where it starts in the part (word) and
cutCh           = nRest + 2     ; its first character (0 marks the end)
parts           = nYear         ; parts read so far

NTP_ROUNDS      = 2             ; the exchange tried this often
        .segment "OVL76"
        .scope Mod76

        jmp OvNtp               ; entry 0

        .include "feult.inc"

Settings:
        jsr OvlCall             ; (module 77: SETTINGS.INI's [time])
        .byte 77, 0
Clocks: jsr OvlCall             ; (module 78: the date, the clocks; a stub)
        .byte 78, 0

; FE_NTP: r0 = a server's name (zero-ended), or 0: SETTINGS.INI's [time]
; ntp=. Its time, with [time] offset= (seconds from UTC, signed; else
; 0), to GEOS's clock, the CIA's time of day and the Ultimate's clock.
; X = 0, or FILE_NOT_FOUND (no server: none given, none set), or the
; Ultimate's error (no network, no answer: FE_ULTIMATE). Tried twice:
; one lost reply happens (gu64.py, 2026-11-11).
OvNtp:  jsr Settings
        txa
        bne @end
        lda argR0+1             ; a server given: that one
        beq @which
        sta r0H
        lda argR0
        sta r0L
        ldy #0
@copy:  lda (r0),y
        sta nHost,y
        beq @which
        iny
        cpy #FE_LONG_MAX
        bne @copy
        lda #0
        sta nHost,y
@which: ldx #FILE_NOT_FOUND
        lda nHost
        beq @end
        lda #NTP_ROUNDS         ; the whole exchange, once more after a
@round: pha                     ; failed one (a lost reply; the count on the
        jsr Connect             ; stack: module variables are reloaded after
        bne @noSock             ; each nested engine call)
        jsr Ask
        bne @close
        jsr Answer
@close: stx feM                 ; (the first error counts)
        lda #N_CLOSE
        jsr Net
        lda nSock
        jsr UPut
        jsr UNoData
        jsr UExec
        ldx feM
@noSock:
        pla
        cpx #0
        beq @ok
        sec
        sbc #1
        bne @round
        rts
@ok:    jmp Clocks
@end:   rts

; Connect: a UDP socket to nHost, port NTP_PORT: nSock. Z set when it
; worked, else X = the error.
Connect:
        lda #N_UDP
        jsr Net
        lda #<NTP_PORT
        jsr UPut
        lda #>NTP_PORT
        jsr UPut
        ldx #0
@host:  lda nHost,x
        jsr UPut
        inx
        cmp #0
        bne @host
        jsr Reply
        jsr UExec
        lda diskBlkBuf
        sta nSock
        txa
        rts

; Ask: the request: NTP_FIRST, then zeros (NTP_LEN bytes). Z set when it
; worked, else X = the error.
Ask:    lda #N_WRITE
        jsr Net
        lda nSock
        jsr UPut
        lda #NTP_FIRST
        jsr UPut
        ldx #NTP_LEN - 1
        lda #0
@zero:  jsr UPut
        dex
        bne @zero
        jsr UNoData
        jsr UExec
        txa
        rts

; Answer: the reply read, TRIES times a second apart until it is there;
; its seconds (big-endian) to nTime (little-endian). X = 0 or the
; error.
Answer: lda #TRIES
        sta nTry
@try:   jsr Second
        lda #N_READ
        jsr Net
        lda nSock
        jsr UPut
        lda #NTP_LEN + 2
        jsr UPut
        lda #0
        jsr UPut
        jsr Reply
        jsr UExec
        txa
        bne @again
        lda r0L                 ; the whole reply?
        cmp #<(diskBlkBuf + NTP_SECONDS + 4)
        bcs @got
        ldx #FE_ULTIMATE
@again: dec nTry
        bne @try
        rts
@got:   ldx #3
        ldy #0
@byte:  lda diskBlkBuf + NTP_SECONDS,y
        sta nTime,x
        iny
        dex
        bpl @byte
        ldx #0
        rts
        .assert <diskBlkBuf = 0, error, "Answer: the reply's end from r0L"

; Second: about a second: 50 frames counted on the raster (not the time
; of day, which a latch could hold still).
Second: lda CPU_PORT
        pha
        lda #RAM_IO
        sta CPU_PORT
        ldx #50
@line:  lda $D012
        cmp #250
        bne @line
@past:  lda $D012
        cmp #250
        beq @past
        dex
        bne @line
        pla
        sta CPU_PORT
        rts

; Net: uCmd = the network target's command A.
Net:    jsr UBegin
        lda #U_NET
        sta uCmd
        rts

; Reply: the reply's data to diskBlkBuf (a page at most).
Reply:  lda #<diskBlkBuf
        sta r0L
        sta uEnd
        lda #>diskBlkBuf
        sta r0H
        sta uEnd+1
        inc uEnd+1
        rts

        .endscope

        .segment "OVL77"
        .scope Mod77

        jmp OvSettings          ; entry 0

        .include "fereu.inc"
        .include "feult.inc"
        .include "fehome.inc"

Parse:  jsr OvlCall             ; (module 79: its [time] lines; a stub)
        .byte 79, 0
Keep:   jsr OvlCall             ; (module 79: the lines before cut, the
        .byte 79, 6             ; rest to TEXT's start)

; OvSettings: from SETTINGS.INI in the home folder, [time] section:
; ntp=server to nHost (else empty), offset=seconds (signed, decimal) to
; nOff (else 0), summer=eu to nDst. Read in parts of up to TEXT_MAX
; bytes: each part's whole lines go to module 79, the unfinished last
; line moves to TEXT's start and the next part follows it (a line longer
; than TEXT_MAX ends the reading). X = 0 (also without the file), or the error.
OvSettings:
        lda #0
        sta nHost
        sta nOff
        sta nOff+1
        sta nOff+2
        sta nTry                ; (module 79: inside [time])
        sta nDst
        sta tail
        sta tail+1
        sta parts
        jsr Home
        txa
        bne @end
        lda #U_OPEN
        jsr UBegin
        lda #UO_READ
        jsr UPut
        ldx #0
@name:  lda IniName,x
        beq :+
        jsr UPut
        inx
        bne @name
:       jsr UNoData
        jsr UExec
        cpx #FILE_NOT_FOUND
        beq @none
        txa
        bne @end
@part:  jsr Part
        stx feM
        lda #U_CLOSE            ; (after the last part, or an error)
        jsr UBegin
        jsr UNoData
        jsr UExec
        ldx feM
        rts
@none:  ldx #0
@end:   rts

; Part: the parts, until one comes back short. X = 0 or the error (one
; after the first part: the end, as for a short one).
Part:   lda #U_READ             ; TEXT_MAX - tail bytes after the tail
        jsr UBegin
        lda #<TEXT_MAX
        sec
        sbc tail
        jsr UPut
        lda #>TEXT_MAX
        sbc tail+1
        jsr UPut
        lda #<TEXT
        clc
        adc tail
        sta r0L
        lda #>TEXT
        adc tail+1
        sta r0H
        lda #<(TEXT + TEXT_MAX)
        sta uEnd
        lda #>(TEXT + TEXT_MAX)
        sta uEnd+1
        jsr UExec
        txa
        beq @read
        ldy parts               ; (a later part: the end of the file)
        beq @end
        ldx #0
@read:  inc parts
        ldy #0                  ; the text's end
        tya
        sta (r0),y
        lda r0L                 ; short (or a later part's error): the end
        cmp #<(TEXT + TEXT_MAX)
        bne @last
        lda r0H
        cmp #>(TEXT + TEXT_MAX)
        bne @last
        jsr Whole               ; full: its whole lines, the rest kept
        bcc Part
@last:  jmp Parse               ; (X = 0 from it)
@end:   rts

; Whole (a full part at TEXT, r0 its end): its whole lines to module 79,
; the unfinished last one moved to TEXT's start (tail its length). C set
; when there is no LF in it (a line longer than TEXT_MAX: module 79
; takes the part, and the reading ends there).
Whole:  lda r0L                 ; the last line's start (after the last LF)
        sta r5L
        lda r0H
        sta r5H
@back:  lda r5H
        cmp #>TEXT
        bne :+
        lda r5L
        cmp #<TEXT
        beq @none
:       lda r5L
        bne :+
        dec r5H
:       dec r5L
        lda (r5),y
        cmp #10
        bne @back
        inc r5L                 ; past it
        bne :+
        inc r5H
:       lda r5L
        sta cut
        lda r5H
        sta cut+1
        lda (r5),y
        sta cutCh
        tya                     ; the whole lines end there
        sta (r5),y
        jsr Keep                ; (module 79; the flags not kept on the
        clc                     ; way back)
        rts
@none:  sec
        rts

IniName:        .byte "SETTINGS.INI", 0

        .endscope

        .segment "OVL78"
        .scope Mod78

        jmp OvClocks            ; entry 0

SetTime:
        jsr OvlCall             ; (module 75: FE_SETTIME, from GEOS's clock;
        .byte 75, 6             ; a stub: back to the function's caller)
Summer: jsr OvlCall             ; (module 79: the EU's summer time?)
        .byte 79, 3

UNIX_FROM_NTP   = 2208988800    ; seconds 1900-1970
month           = year + 1      ; GEOS's clock (geos.inc: year)
day             = year + 2
hour            = year + 3
minutes         = year + 4
seconds         = year + 5
DAY             = 86400

; OvClocks (from module 76): nTime (NTP seconds) + nOff as a date and
; time in GEOS's clock (year 80-99: 19xx, else 20xx), then the CIA's
; time of day and the Ultimate's clock from it (FE_SETTIME). With
; nDst (summer=eu) an hour more in the EU's summer time. X = 0 or the
; error.
OvClocks:
        sec                     ; Unix time: - UNIX_FROM_NTP
        ldx #0
@unix:  lda nTime,x
        sbc Unix,x
        sta nTime,x
        inx
        txa
        eor #4
        bne @unix
        lda nDst                ; summer time decided on the UTC date
        beq @local
        jsr Dst
@local: clc                     ; + the offset (three bytes, its sign
        ldx #0                  ; then to the fourth)
@off:   lda nTime,x
        adc nOff,x
        sta nTime,x
        inx
        txa                     ; (eor: the carry kept, unlike cpx)
        eor #3
        bne @off
        lda nOff+2
        and #$80
        beq :+
        lda #$FF
:       adc nTime+3
        sta nTime+3
        jsr Days                ; nDays, nRest
        jsr Time                ; hour, minutes, seconds
        jsr Years               ; year, month, day
        jmp SetTime

; Dst: in the EU's summer time (Summer), nOff an hour more; nTime as
; it was (the UTC date is worked out from a copy).
Dst:    ldx #3
@keep:  lda nTime,x
        sta nSave,x
        dex
        bpl @keep
        jsr Days
        lda nDays               ; the weekday: (days + 4) mod 7 (1970-01-01
        clc                     ; a Thursday; 0: Sunday) to nTry
        adc #4
        sta r6L
        lda nDays+1
        adc #0
        ldx #16
        ldy #0                  ; (Y: the remainder)
@div:   asl r6L
        rol a
        pha
        tya
        rol a
        cmp #7
        bcc :+
        sbc #7
:       tay
        pla
        dex
        bne @div
        sty nTry
        jsr Time
        jsr Years
        jsr Summer              ; (module 79: C set in summer time)
        bcc @back
        lda nOff                ; + 3600
        clc
        adc #<3600
        sta nOff
        lda nOff+1
        adc #>3600
        sta nOff+1
        bcc @back
        inc nOff+2
@back:  ldx #3
@ret:   lda nSave,x
        sta nTime,x
        dex
        bpl @ret
        rts

; Days: nTime / DAY to nDays, the rest to nRest (shift and subtract).
Days:   lda #0
        sta nRest
        sta nRest+1
        sta nRest+2
        ldx #32
@bit:   asl nTime               ; (the quotient's bits come in at the bottom)
        rol nTime+1
        rol nTime+2
        rol nTime+3
        rol nRest
        rol nRest+1
        rol nRest+2
        lda nRest
        sec
        sbc #<DAY
        tay
        lda nRest+1
        sbc #>DAY
        pha
        lda nRest+2
        sbc #^DAY
        bcc @less
        sta nRest+2
        pla
        sta nRest+1
        sty nRest
        inc nTime
        bne @next
@less:  pla
@next:  dex
        bne @bit
        lda nTime
        sta nDays
        lda nTime+1
        sta nDays+1
        rts

; Time: nRest's hours, minutes, seconds to GEOS's clock.
Time:   ldx #0                  ; hours: 3600 at a time
@hour:  lda nRest
        sec
        sbc #<3600
        tay
        lda nRest+1
        sbc #>3600
        pha
        lda nRest+2
        sbc #0
        bcc @mins
        sta nRest+2
        pla
        sta nRest+1
        sty nRest
        inx
        bne @hour
@mins:  pla
        stx hour
        ldx #0                  ; minutes: 60 at a time (under 3600 now)
        lda nRest
@min:   sec
        sbc #60
        tay
        lda nRest+1
        sbc #0
        bcc @secs
        sta nRest+1
        sty nRest
        tya
        inx
        bne @min
@secs:  stx minutes
        lda nRest
        sta seconds
        rts

; Years: nDays from 1970-01-01 to GEOS's year (two digits), month, day.
; Leap years every fourth (right for 1901-2099, as GeoUTime).
Years:  lda #<1970
        sta nYear
        lda #>1970
        sta nYear+1
@year:  ldx #<365
        lda nYear
        and #3
        bne :+
        inx                     ; (366)
:       stx feMN                ; the year's days (365 or 366: low byte
        lda nDays               ; and 1)
        sec
        sbc feMN
        tay
        lda nDays+1
        sbc #>365
        bcc @month
        sta nDays+1
        sty nDays
        inc nYear
        bne @year
        inc nYear+1
        bne @year
@month: lda nYear               ; GEOS's year: the last two digits
        sec
        sbc #<1900
        cmp #100
        bcc :+
        sbc #100
:       sta year
        ldx #0                  ; months
@mon:   ldy Months,x            ; (February in a leap year: 29; was a
        cpx #1                  ; .byte $2C skip over a 3-byte lda, which
        bne :+                  ; ran into its operand: sweep 2026-11-12)
        lda nYear
        and #3
        bne :+
        iny
:       sty feMN
        lda nDays
        sec
        sbc feMN
        tay
        lda nDays+1
        sbc #0
        bcc @day
        sta nDays+1
        sty nDays
        inx
        bne @mon
@day:   inx
        stx month
        ldx nDays
        inx
        stx day
        rts

Unix:   .dword UNIX_FROM_NTP
Months: .byte 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31

        .endscope

        .segment "OVL79"
        .scope Mod79

        jmp Parse               ; entry 0
        jmp Summer              ; entry 3 (module 78, Dst)
        jmp Keep                ; entry 6 (module 77, Whole)

month           = year + 1      ; GEOS's clock (geos.inc: year)
day             = year + 2
hour            = year + 3

; Summer: C set when the UTC date and hour (GEOS's clock, nTry its
; weekday) lie in the EU's summer time: from the last Sunday of March
; to the last Sunday of October, each at 01:00 UTC (EU directive
; 2000/84/EC's rule, the user's choice of 2026-11-12).
Summer: lda month
        cmp #3
        bcc @no
        beq @march
        cmp #10
        bcc @yes                ; (April to September)
        bne @no
        jsr LastSun             ; October: before its last Sunday 01:00
        cmp day
        bcc @no
        bne @yes
        lda hour
        beq @yes
@no:    clc
        rts
@march: jsr LastSun             ; March: from its last Sunday 01:00
        cmp day
        bcc @yes
        bne @no
        lda hour
        beq @no
@yes:   sec
        rts

; LastSun: A = the day of the last Sunday of a 31-day month (31 less
; the 31st's weekday: (the weekday + 31 - day) mod 7).
LastSun:
        lda #31
        sec
        sbc day
        clc
        adc nTry
@mod:   cmp #7
        bcc :+
        sbc #7
        bcs @mod
:       sta r6L
        lda #31
        sec
        sbc r6L
        rts


; Parse (from module 77, a part of SETTINGS.INI at TEXT, zero-ended,
; whole lines): the lines of [time]: "ntp=", "offset=" and "summer="
; (eu: nDst 1; keys in any case). nTry (inside [time]) carries over from
; the part before; module 77 clears it and nDst first. X = 0.
Parse:  lda #<TEXT
        sta r5L
        lda #>TEXT
        sta r5H
@line:  ldy #0
        lda (r5),y
        beq @end
        cmp #'['
        bne @key
        ldx #TimeKey - Keys
        jsr Match
        lda #0
        bcc :+
        lda #1
:       sta nTry
        jmp @next
@key:   lda nTry
        beq @next
        ldx #NtpKey - Keys
        jsr Match
        bcc :+
        jsr Host
        jmp @next
:       ldx #OffKey - Keys
        jsr Match
        bcc :+
        jsr Offset
        jmp @next
:       ldx #SumKey - Keys      ; "summer=eu": the EU's summer time
        jsr Match
        bcc @next
        lda (r5),y
        ora #$20
        cmp #'e'
        bne @next
        inc nDst
@next:  ldy #0                  ; past the line's end
@skip:  lda (r5),y
        beq @end
        iny
        bne :+
        inc r5H                 ; (a line over 255 characters)
:       cmp #10
        bne @skip
        tya
        clc
        adc r5L
        sta r5L
        bcc @line
        inc r5H
        bne @line
@end:   ldx #0
        rts

; Match: C set when the line at r5 starts with key X (Keys + X, zero-
; ended; letters in any case); Y then past it.
Match:  ldy #0
@ch:    lda Keys,x
        beq @yes
        lda (r5),y
        cmp #'A'
        bcc :+
        cmp #'Z' + 1
        bcs :+
        ora #$20
:       cmp Keys,x
        bne @no
        inx
        iny
        bne @ch
@no:    clc
        rts
@yes:   sec
        rts

; Host: the rest of the line (from Y) to nHost, FE_LONG_MAX at most.
Host:   ldx #0
@ch:    lda (r5),y
        cmp #' ' + 1            ; (CR, LF, the end, spaces: done)
        bcc @end
        sta nHost,x
        iny
        inx
        cpx #FE_LONG_MAX
        bne @ch
@end:   lda #0
        sta nHost,x
        rts

; Offset: a signed decimal number (from Y) to nOff (three bytes).
Offset: lda (r5),y
        sta feMN                ; ("-": negative, at the end)
        cmp #'-'
        beq @sign
        cmp #'+'
        bne @digit
@sign:  iny
@digit: lda (r5),y
        sec
        sbc #'0'
        cmp #10
        bcs @done
        pha                     ; nOff = nOff * 10 + digit
        ldx #2
@copy:  lda nOff,x              ; (nOff * 2 to nTime, * 8 in nOff)
        sta nTime,x
        dex
        bpl @copy
        asl nTime
        rol nTime+1
        rol nTime+2
        ldx #3
@x8:    asl nOff
        rol nOff+1
        rol nOff+2
        dex
        bne @x8
        clc
        ldx #0
@add:   lda nOff,x
        adc nTime,x
        sta nOff,x
        inx
        txa
        eor #3
        bne @add
        pla
        clc
        adc nOff
        sta nOff
        bcc :+
        inc nOff+1
        bne :+
        inc nOff+2
:       iny
        bne @digit
@done:  lda feMN
        cmp #'-'
        bne @end
        ldx #0                  ; negative: 0 - nOff
        sec
@neg:   lda #0
        sbc nOff,x
        sta nOff,x
        inx
        txa
        eor #3
        bne @neg
@end:   rts

; Keep (from module 77: a full part at TEXT up to r0, zero-ended at cut,
; whose character was cutCh): its whole lines parsed, then the line at
; cut (unfinished) moved to TEXT's start, tail its length.
Keep:   jsr Parse
        lda cut                 ; the line's start back, then to TEXT
        sta r5L
        lda cut+1
        sta r5H
        lda #<TEXT
        sta r6L
        lda #>TEXT
        sta r6H
        ldy #0
        lda cutCh
        sta (r5),y
@move:  lda r5L
        cmp r0L
        bne :+
        lda r5H
        cmp r0H
        beq @moved
:       lda (r5),y
        sta (r6),y
        inc r5L
        bne :+
        inc r5H
:       inc r6L
        bne @move
        inc r6H
        bne @move
@moved: lda r6L                 ; tail = its length
        sec
        sbc #<TEXT
        sta tail
        lda r6H
        sbc #>TEXT
        sta tail+1
        rts

Keys:
TimeKey:        .byte "[time]", 0
NtpKey:         .byte "ntp=", 0
OffKey:         .byte "offset=", 0
SumKey:         .byte "summer=", 0

        .endscope
