;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;; TRANSMITTER SIDE (固定) ;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; ===== DATA MEMORY DISTRIBUTION =====
;  ADDRESS       FUNCTION
; 000H~007H     registers
; 008H~01FH     stack
; 020H~07FH     *見VARIABLES USED
; 080H~089H     存過去音訊資料(10筆)
; 08AH~0FFH     
; ====================================

; ====== SOME MACROS =======
ADCTL       EQU 0C5H
ADCH        EQU 0C6H
ADCL        EQU 0BEH
P1M0        EQU 091H
P1M1        EQU 092H
AUXR        EQU 08EH
; ==========================

; ===== PIN DEFINITION =====
PIN_LED_R   EQU P1.2
PIN_LED_G   EQU P1.1
PIN_LED_B   EQU P1.0
PIN_LED_OUT EQU P0
PIN_ADC     EQU P1.7
PIN_SWH_MD  EQU P1.3    ; 聲波顯示模式選擇指撥開關
PIN_LCM_D   EQU P2
PIN_LCM_RS  EQU P3.7
PIN_LCM_RW  EQU P3.6
PIN_LCM_EN  EQU P3.5
; ==========================

; ===== VARIABLES USED =====
MIC_R       EQU R3      ; 紀錄上次MIC的值
SOUND_MAGNI EQU 02FH
OPTR        EQU R0      ; 聲音顯示模式2用到，用於access舊聲音資料
NPTR        EQU R1      ; 聲音顯示模式2用到，指向最新聲音資料的位置
TEMP        EQU 02EH
SWH_MD_R    EQU 02DH.7  ; 紀錄上次 PIN_SWH_MD
SWH_MD_C    EQU 02DH.6  ; Capture PIN_SWH_MD
LCM_CTR     EQU R2      ; DRIVE_LCM的呼叫次數
; ==========================

ORG 0000H
AJMP SETTING

; ORG 0023H
; AJMP SERIAL_INT

ORG 0050H
SETTING:
    ; --------- SERIAL設定 ----------
    MOV TMOD,#00100000B ; set timer 1 as mode 2 (8-bit auto reload)
    MOV TL1,#0FAH   ; timer1作為baud rate generator，
    MOV TH1,#0FAH	; 且 baud rate = 12000
    ORL PCON,#80H   ; SMOD = 1 (timer1頻率除以二)
    SETB TR1        ; timer 1 run

    ; SETB ES		; enable串列傳輸中斷
    ; CLR TI      ; 清空串列傳輸中斷旗標
    ; CLR RI      ; 清空串列傳輸中斷旗標
    ; SETB EA
    ; SETB PS     ; 串列傳輸中斷優先

    CLR  SM2    ; 不使用一對多模式
    SETB SM1    ; 串列傳輸 mode 1
    CLR  SM0    ; 串列傳輸 mode 1

    ; SETB TI     ; 第一次進入中斷

    ; ---------- ADC設定 ------------
    ORL P1M0,#10000000B     ; set P1.7 as input only
    ANL P1M1,#01111111B

    MOV ADCTL,#11100111B    ; ADCON SPEED1 SPEED0 ADCI  ADCS CHS2 CHS1 CHS0
    ; ebable ADC
    ; set to full speed (cycle = 270 clock cycles)
    ; select P1.7 as analog input

    ANL AUXR,#10111111B     ; MSB 8-bit place at ADCH[7:0]

    ORL ADCTL,#00001000B    ; start ADC

    ; ---------- LCM設定 ------------
    ACALL DELAY
    MOV A,#00111011B    ; DL=1(資料8bit), N=1(兩行顯示), F=0(5*7點矩陣字型)
    ACALL COMMAND

    MOV A,#00001100B    ; D=1(DD RAM顯示),C=0(CURSOR不顯示),B=0(CURSOR不閃爍)
    ACALL COMMAND

    MOV A,#1            ; 清除DD RAM
    ACALL COMMAND

    MOV A,#10000000B    ; 將AC指定給DD RAM用，且AC設為0
    ACALL COMMAND
    ACALL DELAY
    MOV DPTR,#LCM_FONT_MODE
    CLR A
    MOVC A,@A+DPTR
    LCM_LOOP_MODE:
    ACALL SDATA
    INC DPTR
    CLR A
    MOVC A,@A+DPTR
    CJNE A,#0,LCM_LOOP_MODE

    MOV A,#11000100B    ; AC指向第二行第5個字
    ACALL COMMAND
    ACALL DELAY
    MOV DPTR,#LCM_FONT_dB
    CLR A
    MOVC A,@A+DPTR
    LCM_LOOP_dB:
    ACALL SDATA
    INC DPTR
    CLR A
    MOVC A,@A+DPTR
    CJNE A,#0,LCM_LOOP_dB

    MOV LCM_CTR,#2
    MOV C,PIN_SWH_MD
    CPL C               ; 使LCM初次進到DRIVE_LCM會顯示MODE的部分
    MOV SWH_MD_R,C

    ; ---------- 其他設定 -----------
    MOV NPTR,#080H

LOOP:
    ACALL GET_SOUND_MAGNI
    ACALL DRIVE_LED
    ACALL DRIVE_LCM
    MOV SBUF,SOUND_MAGNI
    ; ACALL DELAY
    AJMP LOOP

; ===== SOME FUNCTIONS =====
GET_SOUND_MAGNI:    ; 讀取麥克風類比數值，並對時間微分，取得聲音強度
    MOV A,ADCH
    MOV B,ADCL
    MOV C,B.1
    RLC A
    MOV C,B.0
    RLC A       ; 取ADC[7:0] (低八位)
    MOV TEMP,A

    CLR C
    SUBB A,MIC_R
    MOV SOUND_MAGNI,A
    JB SOUND_MAGNI.7,NEG_SOUND
    SJMP RECORD_MIC
    NEG_SOUND:
    CPL A
    INC A
    MOV SOUND_MAGNI,A
    RECORD_MIC:
    MOV A,TEMP
    MOV MIC_R,A         ; 紀錄上次MIC的值

    MODE_PICK:
    JB PIN_SWH_MD,MODE2
    AJMP ADC_RST        ; 聲音顯示模式1：SOUND_MAGNI為及時的聲音強度

    MODE2:              ; 聲音顯示模式2：SOUND_MAGNI為前10次聲音強度最大值
    MOV @NPTR,SOUND_MAGNI   ; 將當前聲音強度放入資料庫中
    CJNE NPTR,#089H,INC_NPTR
    MOV NPTR,#080H
    SJMP FIND_MAX
    INC_NPTR:
    INC NPTR

    FIND_MAX:
    MOV TEMP,#0         ; TEMP用於紀錄最大值
    MOV OPTR,#080H
    SEARCH_LOOP:
        MOV A,TEMP
        CLR CY
        SUBB A,@OPTR
        JB CY,NEW_MAX   ; 若@OPTR大於TEMP，則代表@OPTR是新的最大值
        SJMP NXT_SRCH_LOOP
        NEW_MAX:
        MOV TEMP,@OPTR
        NXT_SRCH_LOOP:
    INC OPTR
    CJNE OPTR,#08AH,SEARCH_LOOP
    MOV SOUND_MAGNI,TEMP    ; 將前10筆資料最大值作為輸出

    ADC_RST:
    ANL ADCTL,#11101111B    ; Clear ADCI
    ORL ADCTL,#00001000B    ; Set ADCS

    RET

DRIVE_LED:
    ; CLR PIN_LED_R
    ; SETB PIN_LED_B
    ; SETB PIN_LED_G
    ; MOV PIN_LED_OUT, SOUND_MAGNI
    MOV B,#16
    MOV A,SOUND_MAGNI
    DIV AB
    MOV TEMP,A
    ; MOV A,B
    ; CJNE A,#0,MAG_OV
    ; SJMP DRIVE_RGB
    ; MAG_OV:
    ; MOV TEMP,#7

    DRIVE_RGB:
    CLR PIN_LED_R
    SETB PIN_LED_G
    SETB PIN_LED_B
    MOV DPTR,#MAGNI_LED_R
    MOV A,TEMP
    MOVC A,@A+DPTR
    MOV PIN_LED_OUT,A
    ACALL DELAY

    SETB PIN_LED_R
    CLR PIN_LED_G
    SETB PIN_LED_B
    MOV DPTR,#MAGNI_LED_G
    MOV A,TEMP
    MOVC A,@A+DPTR
    MOV PIN_LED_OUT,A
    ACALL DELAY

    SETB PIN_LED_R
    SETB PIN_LED_G
    CLR PIN_LED_B
    MOV DPTR,#MAGNI_LED_B
    MOV A,TEMP
    MOVC A,@A+DPTR
    MOV PIN_LED_OUT,A
    ACALL DELAY

    RET

DRIVE_LCM:
    MOV C,PIN_SWH_MD     ; Capture PIN_SWH_MD
    MOV SWH_MD_C,C
    JB SWH_MD_C,SWH_MD_IS1      ; 檢查SWH_MD_C與SWH_MD_R使否相同
    SWH_MD_IS0:
    JNB SWH_MD_R,FINISH_LCM_MD
    SJMP SWH_MD_CHANGE
    SWH_MD_IS1:
    JB SWH_MD_R,FINISH_LCM_MD
    SWH_MD_CHANGE:

    MOV A,#10000100B  ; AC指向第一行第5個字
    ACALL COMMAND
    JB SWH_MD_C,DISP_M2
    DISP_M1:
    MOV DPTR,#LCM_FONT_MODE1
    CLR A
    MOVC A,@A+DPTR
    LCM_LOOP_MODE1:
    ACALL SDATA
    INC DPTR
    CLR A
    MOVC A,@A+DPTR
    CJNE A,#0,LCM_LOOP_MODE1
    SJMP FINISH_LCM_MD
    DISP_M2:
    MOV DPTR,#LCM_FONT_MODE2
    CLR A
    MOVC A,@A+DPTR
    LCM_LOOP_MODE2:
    ACALL SDATA
    INC DPTR
    CLR A
    MOVC A,@A+DPTR
    CJNE A,#0,LCM_LOOP_MODE2

    FINISH_LCM_MD:
    MOV C,SWH_MD_C
    MOV SWH_MD_R,C

    DISP_dB:
    DJNZ LCM_CTR,FINISH_LCM_dB
    MOV A,#11000000B    ; AC指向第二行第1個字
    ACALL COMMAND
    MOV A,SOUND_MAGNI
    MOV B,#3
    DIV AB      ; Mapping to dB
    ADD A,#40   ; Mapping to dB
    ADD A,B     ; Mapping to dB
    MOV B,#100
    DIV AB
    ADD A,#48
    ACALL SDATA
    MOV A,B
    MOV B,#10
    DIV AB
    ADD A,#48
    ACALL SDATA
    MOV A,B
    ADD A,#48
    ACALL SDATA

    FINISH_LCM_dB:

    RET

COMMAND:  ; 把A傳到LCM Instruction Register
    MOV PIN_LCM_D,A
    CLR PIN_LCM_RW      ; RW=0(Write)
    CLR PIN_LCM_RS      ; RS=0(Instruction Reg.)
    SETB PIN_LCM_EN     ; E=1(Enable)
    ACALL DELAY
    CLR PIN_LCM_EN      ; E=0(Disable)
    ACALL DELAY
    RET
SDATA:  ; 把A傳到LCM Data Register
    MOV PIN_LCM_D,A
    CLR PIN_LCM_RW      ; RW=0(Write)
    SETB PIN_LCM_RS     ; RS=1(Data Reg.)
    SETB PIN_LCM_EN     ; E=1(Enable)
    ACALL DELAY
    CLR PIN_LCM_EN      ; E=0(Disable)
    ACALL DELAY
    RET

DELAY:
	MOV R5,#0FFH
DELAY1:
	MOV R6,#0AH    ; 01FH
DELAY2:
	MOV R7,#01H
DELAY3:
	DJNZ R7,DELAY3
	DJNZ R6,DELAY2
	DJNZ R5,DELAY1
	RET

; ===== INTERRUPT FUNCTIONS =====
; SERIAL_INT:
    ; SETB P3.7
    ; CLR TI
    ; MOV SBUF,SOUND_MAGNI
    ; RETI

; ===== TABLES =====
MAGNI_LED_R:
    DB 11111110B, 11111100B, 11111100B, 11111100B
    DB 11111100B, 11111100B, 10111100B, 00111100B
MAGNI_LED_G:
    DB 11111111B, 11111111B, 11111011B, 11110011B
    DB 11110011B, 11010011B, 10010011B, 00010011B
MAGNI_LED_B:
    DB 11111111B, 11111111B, 11111111B, 11111111B
    DB 11101111B, 11001111B, 10001111B, 00001111B

LCM_FONT_MODE:
    DB "MODE",0
LCM_FONT_dB:
    DB "dB",0
LCM_FONT_MODE1:
    DB "1:sensitive ",0
LCM_FONT_MODE2:
    DB "2:steady    ",0