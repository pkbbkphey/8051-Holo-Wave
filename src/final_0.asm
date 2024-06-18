;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;; TRANSMITTER SIDE (固定) ;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

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
; ==========================

; ===== VARIABLES USED =====
MIC_R       EQU R0  ; 紀錄上次MIC的值
SOUND_MAGNI EQU 2FH
TEMP        EQU R1
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

LOOP:
    ACALL GET_SOUND_MAGNI
    ACALL DRIVE_LED
    MOV SBUF,SOUND_MAGNI
    ; ACALL DELAY
    AJMP LOOP

; ===== SOME FUNCTIONS =====
GET_SOUND_MAGNI:
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
    SJMP FINISH1
    NEG_SOUND:
    CPL A
    INC A
    MOV SOUND_MAGNI,A
    FINISH1:
    MOV A,TEMP
    MOV MIC_R,A         ; 紀錄上次MIC的值

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