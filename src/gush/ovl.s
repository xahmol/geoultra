; gush: overlays (docs/GUSH.md, "Memory"). gush is a VLIR file: record 0
; the resident core at $0400-$4FFF (console, editor, parser, executor,
; variables, scripts, redirection, starting programs); records 1-OVL_N
; overlays linked at TRANS ($5000-$5FFF, gush.cfg), the area external
; commands (step 3.8) use too. OvlInit, the first thing at gush's start
; (dirEntryBuf still holds gush's own entry, GetFile left it), reads each
; overlay record once into the application's REU bank OVL_BANK, 4 KB
; each, so a later cd or another drive never matters; the stubs at the
; end, through OvlGo, fetch the overlay a routine lives in when another
; one is there. Overlay code may call the core, and its own overlay's
; stubs; never another overlay's (its return would land in other code).
; An overlay's DATA comes back as built with each fetch: scratch only.
; Without the records (a failed read) overlay commands fail quietly, and
; the start says so. Own code.

        .include "geos.inc"
        .include "gush.inc"

        .import failed

StashRAM        = $C2C8         ; GEOS jump table
FetchRAM        = $C2CB
OVL_BANK        = 7             ; (1-6: history, cp -r, HIGH, scripts,
                                ; lines, pipes; the last free bank)
OVL_N           = 4             ; overlay records

        .segment "CODE"

        .include "ovlcore.inc"  ; (the loader, OvlGo, the Stub macro)

; OvlFail: a stub without the overlays: the line failed.
OvlFail:
        lda #1
        sta failed
        rts

; The stubs: a routine's name in the core, Ov_name in its overlay.
        Stub CmdCp, 1           ; overlay 1: files.s, tree.s, sys.s, hist.s
        Stub CmdMv, 1
        Stub CmdRm, 1
        Stub CmdMkdir, 1
        Stub CmdRmdir, 1
        Stub CmdCat, 1
        Stub CmdMore, 1
        Stub CmdDf, 1
        Stub CmdMount, 1
        Stub CmdUmount, 1
        Stub CmdMkimg, 1
        Stub CmdFree, 1
        Stub CmdReboot, 1
        Stub HistSave, 1
        Stub HistLoad, 1
        Stub CmdTurbo, 2        ; overlay 2: sysset.s, test.s
        Stub CmdDate, 2
        Stub CmdNtp, 2
        Stub CmdTest, 2
        Stub CmdBracket, 2
        Stub CmdRead, 2
        Stub CmdTrue, 2
        Stub CmdFalse, 2
        Stub Complete, 3        ; overlay 3: complete.s
        Stub CmdIfconfig, 4     ; overlay 4: net.s
        Stub CmdWget, 4

