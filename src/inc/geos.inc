; GEOS 64 2.0 interface: zero page, system variables and constants that
; applications are compiled against. Addresses from HG2G2022 and
; inc/geossym.inc of the reassembled kernal (mist64/geos, Maciej
; Witkowiak); see docs/ARCHITECTURE.md, "Attribution".

; Pseudo-registers r0-r15
r0      = $02
r0L     = $02
r0H     = $03
r1      = $04
r1L     = $04
r1H     = $05
r2      = $06
r2L     = $06
r2H     = $07
r3      = $08
r3L     = $08
r3H     = $09
r4      = $0A
r4L     = $0A
r4H     = $0B
r5      = $0C
r5L     = $0C
r5H     = $0D
r6      = $0E
r6L     = $0E
r6H     = $0F
r7      = $10
r7L     = $10
r7H     = $11
r8      = $12
r8L     = $12
r8H     = $13
r9      = $14
r9L     = $14
r9H     = $15
r10     = $16
r10L    = $16
r10H    = $17
r11     = $18
r11L    = $18
r11H    = $19
r12     = $1A
r12L    = $1A
r12H    = $1B
r13     = $1C
r13L    = $1C
r13H    = $1D
r14     = $1E
r14L    = $1E
r14H    = $1F
r15     = $20
r15L    = $20
r15H    = $21

; Kernal zero page variables
curPattern      = $22   ; word: pointer to the 8-byte fill pattern
string          = $24   ; word
baselineOffset  = $26
curSetWidth     = $27   ; word
curHeight       = $29
curIndexTable   = $2A   ; word
cardDataPntr    = $2C   ; word
currentMode     = $2E
dispBufferOn    = $2F
mouseOn         = $30
msePicPtr       = $31   ; word
windowTop       = $33
windowBottom    = $34
leftMargin      = $35   ; word
rightMargin     = $37   ; word
pressFlag       = $39
mouseXPos       = $3A   ; word
mouseYPos       = $3C

; System variables
appMain         = $849B
intTopVector    = $849D
intBotVector    = $849F
mouseVector     = $84A1
keyVector       = $84A3
inputVector     = $84A5
mouseFaultVec   = $84A7
otherPressVec   = $84A9
StringFaultVec  = $84AB
RecoverVector   = $84B1
selectionFlash  = $84B3
alphaFlag       = $84B4
iconSelFlag     = $84B5
faultData       = $84B6
menuNumber      = $84B7
mouseTop        = $84B8
mouseBottom     = $84B9
mouseLeft       = $84BA   ; word
mouseRight      = $84BC   ; word
maxMouseSpeed   = $8501
minMouseSpeed   = $8502
mouseAccel      = $8503
keyData         = $8504
mouseData       = $8505
inputData       = $8506
mouseSpeed      = $8507
screencolors    = $851E

; Memory areas
OS_VARS         = $8000
SCREEN_BASE     = $A000
BACK_SCR_BASE   = $6000
SPRITE_PICS     = $8A00
COLOR_MATRIX    = $8C00
MOUSE_BASE      = $FE80
InitMouse       = MOUSE_BASE
SlowMouse       = MOUSE_BASE + 3
UpdateMouse     = MOUSE_BASE + 6

; Constants
ST_WR_FORE      = $80     ; dispBufferOn
ST_WR_BACK      = $40
KEYPRESS_BIT    = $80     ; pressFlag
INPUT_BIT       = $40
MOUSE_BIT       = $20
MOUSEON_BIT     = $80     ; mouseOn
MENUON_BIT      = $40
ICONSON_BIT     = $20
SC_PIX_WIDTH    = 320
SC_PIX_HEIGHT   = 200

; Processes
MAX_PROCESSES   = 20

; Key codes (keyData)
KEY_F1          = 1
KEY_F2          = 2
KEY_F3          = 3
KEY_F4          = 4
KEY_F5          = 5
KEY_F6          = 6
KEY_LEFT        = 8
CR              = 13
KEY_F7          = 14
KEY_F8          = 15
KEY_UP          = 16
KEY_DOWN        = 17
KEY_HOME        = 18
KEY_CLEAR       = 19
KEY_LARROW      = 20
KEY_UPARROW     = 21
KEY_STOP        = 22
KEY_RUN         = 23
KEY_INSERT      = 28
KEY_DELETE      = 29
KEY_RIGHT       = 30
SHORTCUT        = $80

; currentMode (text styles)
SET_UNDERLINE   = $80
SET_BOLD        = $40
SET_REVERSE     = $20
SET_ITALIC      = $10
SET_OUTLINE     = $08
SET_SUPERSCRIPT = $04
SET_SUBSCRIPT   = $02
SET_PLAINTEXT   = $00

; Text escape codes (PutChar / PutString)
BACKSPACE       = 8
FORWARDSPACE    = 9
LF              = 10
HOME            = 11
UPLINE          = 12
ULINEON         = 14
ULINEOFF        = 15
ESC_GRAPHICS    = 16
ESC_RULER       = 17
REVON           = 18
REVOFF          = 19
GOTOX           = 20
GOTOY           = 21
GOTOXY          = 22
NEWCARDSET      = 23
BOLDON          = 24
ITALICON        = 25
OUTLINEON       = 26
PLAINTEXT       = 27

; PutDecimal format
SET_LEFTJUST    = $80
SET_SUPRESS     = $40

; Menus
HORIZONTAL      = $00
VERTICAL        = $80
CONSTRAINED     = $40
UN_CONSTRAINED  = $00
MENU_ACTION     = $00
DYN_SUB_MENU    = $40
SUB_MENU        = $80
MAX_M_NESTING   = 4
MAX_M_ITEMS     = 15
M_HEIGHT        = 14
SELECTION_DELAY = 10
TRUE            = $FF
FALSE           = $00

; Icons
IconDescVec     = $3F     ; word: active icon table (kernal internal)
dblClickCount   = $8515
MAX_ICONS       = 31
CLICK_COUNT     = 30
ST_NOTHING      = $00     ; iconSelFlag
ST_FLASH        = $80
ST_INVERT       = $40
OFF_NM_ICNS     = 0
OFF_IC_XMOUSE   = 1
OFF_IC_YMOUSE   = 3
OFF_I_PIC       = 0       ; icon entry, 8 bytes, from offset 4
OFF_I_X         = 2
OFF_I_Y         = 3
OFF_I_WIDTH     = 4
OFF_I_HEIGHT    = 5
OFF_I_EVENT     = 6
OFF_I_NEXT      = 8

; Dialog boxes
DBoxDesc        = $43     ; word: active dialog definition (kernal internal)
sysDBData       = $851D
dlgBoxRamBuf    = $851F
TOT_SRAM_SAVED  = 417
DEF_DB_POS      = $80
SET_DB_POS      = $00
DEF_DB_TOP      = 32
DEF_DB_BOT      = 127
DEF_DB_LEFT     = 64
DEF_DB_RIGHT    = 255
OK              = 1       ; system icons
CANCEL          = 2
YES             = 3
NO              = 4
OPEN            = 5
DISK            = 6
DBTXTSTR        = 11      ; commands
DBVARSTR        = 12
DBGETSTRING     = 13
DBSYSOPV        = 14
DBGRPHSTR       = 15
DBGETFILES      = 16
DBOPVEC         = 17
DBUSRICON       = 18
DB_USR_ROUT     = 19
SYSDBI_WIDTH    = 6
SYSDBI_HEIGHT   = 16

; REU
ramExpSize      = $88C3
sysRAMFlg       = $88C4
