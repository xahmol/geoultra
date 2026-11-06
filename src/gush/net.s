; gush: network commands (docs/GUSH.md, "Step 3", sub-step 9; overlay 4,
; ovl.s) through the Ultimate's network target, FE_UCI (enginenet.s).
; ifconfig: the interface's address, netmask, gateway and MAC address.
; wget [-O name] http://host[:port]/path: the file over HTTP/1.0 into the
; current folder, named after the path's last part (index.html for none)
; or -O's name. The Ultimate resolves the host's name itself; it has no
; ping and no name lookup of its own (no ICMP, no DNS command), so gush
; has neither. Command formats from the UCI library (ultimate-uci-
; oscar64, ultimate_network_lib.c, own code of the same author). Own code.

        .include "geos.inc"
        .include "gush.inc"

        .import FileEngine, argc, argLo, argHi, ArgR0, Print, Say, Fail
        .import Decimal, num, ConPut, ConNewLine, FailPath, failed
        .export Ov_CmdIfconfig := CmdIfconfig
        .export Ov_CmdWget := CmdWget

U_NET           = 3             ; the network target and its commands
N_NETADDR       = $04
N_IPADDR        = $05
N_TCP           = $07
N_CLOSE         = $09
N_READ          = $10
N_WRITE         = $11
WRITE_MAX       = 125           ; a write's data (128 with its 3 bytes)
READ_MAX        = 512           ; a read's data (2 bytes of length first)
NO_DATA_YET     = $FF           ; a read's length $FFFF: nothing yet
WAIT_FRAMES     = 250           ; reads without data before giving up
                                ; (a frame apart: about 5 s, 4 times)
WAIT_ROUNDS     = 4
CPU_PORT        = $01
RAM_IO          = $35
NAME_MAX        = 64
REQ_MAX         = 400
LINE_MAX_HTTP   = 52            ; a header line kept (the status shown)

        .segment "ZEROPAGE"

up:             .res 2          ; the URL, a text being sent

        .segment "OV4"                 ; (overlay 4, ovl.s)

; ifconfig: the network interface's addresses.
CmdIfconfig:
        lda argc
        cmp #1
        beq :+
        jmp Words
:       lda #N_IPADDR           ; address, netmask, gateway (4 bytes each)
        jsr Cmd3
        lda #12
        jsr Ask
        bcc :+
        rts
:       ldx #0
@ip:    stx at
        lda IpNames,x
        ldy IpNames+3,x
        jsr Print
        ldx at
        txa
        asl a
        asl a
        jsr Dotted
        jsr ConNewLine
        ldx at
        inx
        cpx #3
        bcc @ip
        lda #N_NETADDR          ; the MAC address (6 bytes)
        jsr Cmd3
        lda #6
        jsr Ask
        bcc :+
        rts
:       lda #<MacText
        ldy #>MacText
        jsr Print
        ldx #0
@mac:   stx at
        lda reply,x
        jsr Hex
        ldx at
        inx
        cpx #6
        beq @nl
        lda #':'
        jsr ConPut
        ldx at
        inx
        bne @mac
@nl:    jmp ConNewLine

IpNames:
        .byte <IpText, <MaskText, <GwText
        .byte >IpText, >MaskText, >GwText
IpText:         .byte "address  ", 0
MaskText:       .byte "netmask  ", 0
GwText:         .byte "gateway  ", 0
MacText:        .byte "mac      ", 0

; Dotted: reply's 4 bytes from A as "a.b.c.d".
Dotted: sta from
        ldx #0
@b:     stx part
        ldy from
        lda reply,y
        sta num
        lda #0
        sta num+1
        sta num+2
        sta num+3
        jsr Decimal             ; (A 0: as wide as it is)
        inc from
        ldx part
        inx
        cpx #4
        beq @end
        stx part
        lda #'.'
        jsr ConPut
        ldx part
        bne @b
@end:   rts

; Hex: A as two hex digits.
Hex:    pha
        lsr a
        lsr a
        lsr a
        lsr a
        jsr @d
        pla
        and #$0F
@d:     cmp #10
        bcc :+
        adc #'A' - '0' - 10 - 1 ; (C set)
:       adc #'0'
        jmp ConPut

; Cmd3: cmd = the network target's command A with byte 0 (interface 0,
; or socket 0 replaced later): cmdLen 3.
Cmd3:   sta cmd+1
        lda #U_NET
        sta cmd
        lda #0
        sta cmd+2
        lda #3
        sta cmdLen
        rts

; Ask: cmd sent, up to A bytes of reply wanted (0-255) into reply. C set
; on an error (said, about the command); else r3 = the reply's length.
Ask:    sta r3L
        lda #0
        sta r3H
Ask16:  jsr Send
        txa
        bne @fail
        clc
        rts
@fail:  ldy #$FF
        jsr Fail
        sec
        rts

; Send: cmd sent through FE_UCI, the reply (r3 bytes at most) to reply.
; X = 0 or the error.
Send:   lda #<cmd
        sta r0L
        lda #>cmd
        sta r0H
        lda cmdLen
        sta r1L
        lda #<reply
        sta r2L
        lda #>reply
        sta r2H
        lda #FE_UCI
        jmp FileEngine

Words:  ldx #ERR_WORDS
        ldy #$FF
        jmp Fail

; --- wget ---------------------------------------------------------------

; wget [-O name] URL.
CmdWget:
        lda #0
        sta named
        sta fileOpen
        ldx #1
        lda argc
        cmp #2
        beq @url
        cmp #4
        bne Words
        jsr ArgR0               ; "-O" name
        ldy #0
        lda (r0),y
        cmp #'-'
        bne Words
        iny
        lda (r0),y
        cmp #'O'
        bne Words
        iny
        lda (r0),y
        bne Words
        ldx #2
        jsr ArgR0
        jsr NameFrom
        inc named
        ldx #3
@url:   stx urlWord
        jsr ArgR0
        lda r0L
        sta up
        lda r0H
        sta up+1
        jsr Url
        bcc :+
        ldx #ERR_URL
        ldy urlWord
        jmp Fail
:       jsr Connect
        bcs @end
        jsr Request
        bcs @close
        jsr Receive
@close: php
        lda #N_CLOSE            ; the socket closed; its answer ignored
        jsr Cmd3                ; (a socket the server closed may answer
        lda sock                ; with an error: the download is done)
        sta cmd+2
        lda #0
        sta r3L
        sta r3H
        jsr Send
        plp
@end:   rts

; Url: up = "http://host[:port][/path]": host (zero-ended), port, path
; (a pointer, "/" when none) and, unless named, name = the path's last
; part (index.html for none; up to a "?"). C set when it is none.
Url:    ldy #6
@http:  lda (up),y
        cmp Http,y
        bne @no
        dey
        bpl @http
        lda #<80
        sta port
        lda #>80
        sta port+1
        ldy #7
        ldx #0
@host:  lda (up),y
        beq @hostEnd
        cmp #'/'
        beq @hostEnd
        cmp #':'
        beq @hostEnd
        sta host,x
        iny
        inx
        cpx #NAME_MAX
        bcc @host
@no:    sec
        rts
@hostEnd:
        cpx #0
        beq @no
        lda #0
        sta host,x
        lda (up),y
        cmp #':'
        bne @path
        lda #0                  ; :port, decimal
        sta port
        sta port+1
@digit: iny
        lda (up),y
        sec
        sbc #'0'
        cmp #10
        bcs @path
        pha
        lda port                ; port * 10 + digit
        ldx port+1
        asl port
        rol port+1
        asl port
        rol port+1
        clc
        adc port
        sta port
        txa
        adc port+1
        sta port+1
        asl port
        rol port+1
        pla
        clc
        adc port
        sta port
        bcc @digit
        inc port+1
        bne @digit
@path:  sty pathAt
        lda (up),y
        beq :+
        cmp #'/'
        bne @no
:       lda named
        bne @done
        ldx #0                  ; the name: after the path's last "/"
@last:  lda (up),y
        beq @nameEnd
        cmp #'?'
        beq @nameEnd
        iny
        cmp #'/'
        bne :+
        ldx #0
        beq @last
:       cpx #NAME_MAX - 1
        bcs @last
        sta name,x
        inx
        bne @last
@nameEnd:
        cpx #0
        bne :+
        ldx #IndexEnd - Index - 1
@ix:    lda Index,x
        sta name,x
        dex
        bpl @ix
        ldx #IndexEnd - Index
:       lda #0
        sta name,x
@done:  clc
        rts

Http:   .byte "http://"
Index:  .byte "index.html"
IndexEnd:

; NameFrom: name = the text at r0 (NAME_MAX - 1 at most).
NameFrom:
        ldy #$FF
@ch:    iny
        cpy #NAME_MAX - 1
        bcs @end
        lda (r0),y
        sta name,y
        bne @ch
        rts
@end:   lda #0
        sta name,y
        rts

; Connect: a TCP socket to host, port: sock. C set on an error (said).
Connect:
        lda #N_TCP
        jsr Cmd3
        lda port
        sta cmd+2
        lda port+1
        sta cmd+3
        ldx #0
        ldy #4
@h:     lda host,x
        sta cmd,y
        iny
        inx
        cmp #0
        bne @h
        sty cmdLen
        lda #1
        jsr Ask
        bcs @end
        lda reply
        sta sock
        clc
@end:   rts

; Request: "GET path HTTP/1.0", Host, User-Agent, Connection: close and an
; empty line, sent in pieces of WRITE_MAX. C set on an error (said).
Request:
        lda #0
        sta reqLen
        sta reqLen+1
        sta tooLong
        lda #<Get
        ldy #>Get
        jsr Text
        lda pathAt              ; the path, or "/"
        clc
        adc up
        sta r0L
        lda up+1
        adc #0
        sta r0H
        ldy #0
        lda (r0),y
        bne :+
        lda #<Slash
        ldy #>Slash
        jmp @path
:       lda r0L
        ldy r0H
@path:  jsr Text
        lda #<Proto
        ldy #>Proto
        jsr Text
        lda #<host
        ldy #>host
        jsr Text
        lda #<Rest
        ldy #>Rest
        jsr Text
        bcs @long
        lda #0                  ; then the pieces
        sta sent
        sta sent+1
@piece: lda #N_WRITE
        jsr Cmd3
        lda sock
        sta cmd+2
        ldy #3
@b:     lda sent                ; (all sent?)
        cmp reqLen
        bne :+
        lda sent+1
        cmp reqLen+1
        beq @send
:       lda sent
        clc
        adc #<req
        sta r0L
        lda sent+1
        adc #>req
        sta r0H
        sty at
        ldy #0
        lda (r0),y
        ldy at
        sta cmd,y
        iny
        inc sent
        bne :+
        inc sent+1
:       cpy #3 + WRITE_MAX
        bcc @b
@send:  cpy #3
        beq @done
        sty cmdLen
        lda #0
        jsr Ask
        bcc @piece
        rts
@done:  clc
        rts
@long:  ldx #ERR_URL
        ldy urlWord
        jsr Fail
        sec
        rts

Get:    .byte "GET ", 0
Slash:  .byte "/", 0
Proto:  .byte " HTTP/1.0", CR, LF, "Host: ", 0
Rest:   .byte CR, LF, "User-Agent: gush (GeoUltra)", CR, LF
        .byte "Connection: close", CR, LF, CR, LF, 0

; Text: the zero-ended text at A/Y added to req. C set when anything
; did not fit (tooLong, kept for the calls after: checked once at the
; end).
Text:   sta r0L
        sty r0H
        ldy #0
@ch:    lda (r0),y
        beq @end
        pha
        lda reqLen+1            ; (REQ_MAX: 16 bits)
        cmp #>REQ_MAX
        bcc @room
        lda reqLen
        cmp #<REQ_MAX
        bcc @room
        pla
        lda #1
        sta tooLong
        bne @end
@room:  lda reqLen
        clc
        adc #<req
        sta r1L
        lda reqLen+1
        adc #>req
        sta r1H
        pla
        sty at
        ldy #0
        sta (r1),y
        ldy at
        inc reqLen
        bne :+
        inc reqLen+1
:       iny
        bne @ch
@end:   lda tooLong
        cmp #1
        rts

; Receive: the answer read: the status line checked (200), the headers
; skipped, the body into the file `name`. C set on an error (said).
Receive:
        lda #0
        sta state               ; 0: status line, 1: headers, 2: body
        sta lineLen
        sta handle
        sta total
        sta total+1
        sta total+2
        sta total+3
@read:  jsr ReadSock
        bcs @fail
        lda r3L                 ; nothing more: the end
        ora r3H
        beq @end
        jsr Chunk
        bcc @read
@fail:  jsr CloseFile
        sec
        rts
@end:   lda state
        cmp #2
        beq :+
        ldx #ERR_HTTP           ; (ended in the headers)
        ldy urlWord
        jsr Fail
        jmp @fail
:       jsr CloseFile
        lda #<name              ; "NAME: N bytes"
        ldy #>name
        jsr Print
        lda #<Got
        ldy #>Got
        jsr Print
        ldx #3
@t:     lda total,x
        sta num,x
        dex
        bpl @t
        lda #0
        jsr Decimal
        lda #<Bytes
        ldy #>Bytes
        jsr Say
        clc
        rts

Got:    .byte ": ", 0
Bytes:  .byte " bytes", 0

; ReadSock: up to READ_MAX bytes from the socket: data at reply+2, r3 =
; its length (0: closed). Waits while the Ultimate has nothing yet, up
; to WAIT_ROUNDS * WAIT_FRAMES frames. C set on an error or the wait's
; end (said).
ReadSock:
        lda #WAIT_ROUNDS
        sta rounds
@round: lda #WAIT_FRAMES
        sta frames
@try:   lda #N_READ
        jsr Cmd3
        lda sock
        sta cmd+2
        lda #<READ_MAX
        sta cmd+3
        lda #>READ_MAX
        sta cmd+4
        lda #5
        sta cmdLen
        lda #<(READ_MAX + 2)
        sta r3L
        lda #>(READ_MAX + 2)
        sta r3H
        jsr Ask16
        bcs @end
        lda reply+1             ; $FFFF: nothing yet
        and reply
        cmp #NO_DATA_YET
        bne @got
        jsr Frame
        dec frames
        bne @try
        dec rounds
        bne @round
        ldx #ERR_TIMEOUT
        ldy urlWord
        jsr Fail
        sec
        rts
@got:   lda reply
        sta r3L
        lda reply+1
        sta r3H
        clc
@end:   rts

; Frame: one frame waited (the raster passing line 250). Interrupts
; stay on (a frame without them would cost GEOS's clock a tick; its
; interrupt sets the CPU port itself).
Frame:  lda CPU_PORT
        pha
        lda #RAM_IO
        sta CPU_PORT
@line:  lda $D012
        cmp #250
        bne @line
@past:  lda $D012
        cmp #250
        beq @past
        pla
        sta CPU_PORT
        rts

; Chunk: r3 bytes at reply+2: header lines up to the empty one, then the
; body to the file. C set on an error (said).
Chunk:  lda #0
        sta at
        sta at+1
@ch:    lda at                  ; (all of them?)
        cmp r3L
        bne :+
        lda at+1
        cmp r3H
        bne :+
        clc
        rts
:       lda state
        cmp #2
        beq @body
        lda at                  ; a header byte
        clc
        adc #<(reply + 2)
        sta r0L
        lda at+1
        adc #>(reply + 2)
        sta r0H
        ldy #0
        lda (r0),y
        jsr HeaderByte
        bcs @err
        inc at
        bne @ch
        inc at+1
        bne @ch
@body:  lda at                  ; the rest: to the file
        clc
        adc #<(reply + 2)
        sta r1L
        lda at+1
        adc #>(reply + 2)
        sta r1H
        lda r3L
        sec
        sbc at
        sta r2L
        lda r3H
        sbc at+1
        sta r2H
        lda r2L                 ; total += r2
        clc
        adc total
        sta total
        lda r2H
        adc total+1
        sta total+1
        bcc :+
        inc total+2
        bne :+
        inc total+3
:       ldy handle
        lda #FE_WRITE
        jsr FileEngine
        txa
        beq :+
        ldy #$FF
        jsr Fail
@err:   sec
        rts
:       clc
        rts

; HeaderByte: A, a byte of the status line or the headers. A line ends
; at LF (a CR before it dropped). The status line must say 200 (else it
; is shown); an empty line ends the headers and opens the file. C set on
; an error (said).
HeaderByte:
        cmp #CR
        beq @ok
        cmp #LF
        beq @eol
        ldx lineLen
        cpx #LINE_MAX_HTTP
        bcs :+
        sta line,x
:       inc lineLen
        bne @ok
        dec lineLen             ; (255 at most: "not empty" is all it says)
@ok:    clc
        rts
@eol:   lda state
        bne @header
        inc state               ; the status line: "HTTP/1.x 200 ..."
        lda lineLen             ; (shorter: no status)
        cmp #12
        bcc @bad
        lda line + 9
        cmp #'2'
        bne @bad
        lda line + 10
        cmp #'0'
        bne @bad
        lda line + 11
        cmp #'0'
        bne @bad
        lda #0
        sta lineLen
        clc
        rts
@header:
        lda lineLen             ; an empty line: the body comes
        bne @next
        inc state
        jmp OpenFile
@next:  lda #0
        sta lineLen
        clc
        rts
@bad:   ldx lineLen             ; the status shown: "gush: wget: HTTP/..."
        cpx #LINE_MAX_HTTP
        bcc :+
        ldx #LINE_MAX_HTTP - 1
:       lda #0
        sta line,x
        lda #<WgetColon
        ldy #>WgetColon
        jsr Print
        lda #<line
        ldy #>line
        jsr Say
        lda #1                  ; (the line's status: failed, as Fail
        sta failed              ; would)
        sec
        rts

WgetColon:      .byte "gush: wget: ", 0

; OpenFile: the file `name` opened for writing: handle. C set on an
; error (said).
OpenFile:
        lda #<name
        sta r0L
        lda #>name
        sta r0H
        lda #FO_WRITE
        sta r2L
        lda #FE_OPEN
        jsr FileEngine
        sta handle
        txa
        bne :+
        inc fileOpen
        clc
        rts
:       lda #<name
        ldy #>name
        jmp FailPathC

; CloseFile: the file closed, when open.
CloseFile:
        lda fileOpen
        beq :+
        ldy handle
        lda #FE_CLOSE
        jsr FileEngine
        lda #0
        sta fileOpen
:       rts

FailPathC:
        jsr FailPath
        sec
        rts

        .segment "OV4"

named:          .byte 0
urlWord:        .byte 0
pathAt:         .byte 0
port:           .word 0
sock:           .byte 0
handle:         .byte 0
fileOpen:       .byte 0
state:          .byte 0
lineLen:        .byte 0
at:             .word 0
from:           .byte 0
part:           .byte 0
rounds:         .byte 0
frames:         .byte 0
cmdLen:         .byte 0
tooLong:        .byte 0
reqLen:         .word 0
sent:           .word 0
total:          .res 4
host:           .res NAME_MAX
name:           .res NAME_MAX
line:           .res LINE_MAX_HTTP
cmd:            .res 128
req:            .res REQ_MAX
reply:          .res READ_MAX + 2
