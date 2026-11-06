; Drive E shown on the current drive's slot for a moment: stubs to module
; 81 (sysenter.s), for the modules that need it (15, 55, the file
; engine's). Enter: E shown (curDirHead its root header); Leave: the
; slot and curDirHead back, X kept; Usable: C clear when E can be shown.

Enter:  jsr OvlCall
        .byte 81, 0
Leave:  jsr OvlCall
        .byte 81, 3
Usable: jsr OvlCall
        .byte 81, 6
