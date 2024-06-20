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
PIN_SWH_MD  EQU P1.3    ; 聲波顯示模式選擇開關
PIN_SWH_SP  EQU P1.4    ; 串列傳輸更新速率選擇
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
SWH_SP_R    EQU 02DH.4  ; 紀錄上次 PIN_SWH_SP
SWH_SP_C    EQU 02DH.3  ; Capture PIN_SWH_SP
LCM_CTR     EQU R2      ; DRIVE_LCM的呼叫次數
LED_CTR     EQU R4      ; DRIVE_LED的呼叫次數
SERIAL_CTR  EQU R5      ; SEND_SERIAL的呼叫次數
TEMP_BIT    EQU 02DH.5
; ==========================

ORG 0000H
AJMP SETTING

ORG 00BH    ; T0中斷向量
AJMP T0_INT

; ================ MAIN FUNCTION =================
ORG 0050H
SETTING:
    ; --------- SERIAL設定 ----------
    MOV TMOD,#00100001B ; set timer 1 as mode 2 (8-bit auto reload)
    MOV TL1,#0FAH   ; timer1作為baud rate generator，
    MOV TH1,#0FAH	; 且 baud rate = 12000
    ORL PCON,#80H   ; SMOD = 1 (timer1頻率除以二)
    SETB TR1        ; timer 1 run

    CLR  SM2    ; 不使用一對多模式
    SETB SM1    ; 串列傳輸 mode 1
    CLR  SM0    ; 串列傳輸 mode 1

    SETB TI     ; 觸發第一次進入中斷

    ; ----------- T0設定 ------------
    ; TMOD = #00100001B => set timer 0 as mode 1 (16-bit)
    MOV TH0,#243    ; 進入T0_INT的週期
    MOV TL0,#0
    CLR TF0
    SETB ET0
    SETB EA
    SETB TR0    ; T0 run

    ; ---------- ADC設定 ------------
    ORL P1M0,#10000000B     ; set P1.7 as input only
    ANL P1M1,#01111111B     ; set P1.7 as input only

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

    MOV A,#10000000B    ; AC指向第一行第1個字
    ACALL COMMAND
    ACALL DELAY
    MOV DPTR,#LCM_FONT_MIC  ; 在LCM上顯示"MIC:"
    CLR A
    MOVC A,@A+DPTR
    LCM_LOOP_MODE:          ; 以迴圈配合TABLE的方式來顯示
    ACALL SDATA
    INC DPTR
    CLR A
    MOVC A,@A+DPTR
    CJNE A,#0,LCM_LOOP_MODE ; 讀到TABLE中的0為止

    MOV A,#11000000B    ; AC指向第二行第1個字
    ACALL COMMAND
    ACALL DELAY
    MOV DPTR,#LCM_FONT_SSP  ; 在LCM上顯示"SSP:" (SERIAL SPEED)
    CLR A
    MOVC A,@A+DPTR
    LCM_LOOP_SSP:
    ACALL SDATA
    INC DPTR
    CLR A
    MOVC A,@A+DPTR
    CJNE A,#0,LCM_LOOP_SSP

    MOV A,#11001001B    ; AC指向第二行第10個字
    ACALL COMMAND
    ACALL DELAY
    MOV DPTR,#LCM_FONT_dB   ; 在LCM上顯示"[   dB]"
    CLR A
    MOVC A,@A+DPTR
    LCM_LOOP_dB:
    ACALL SDATA
    INC DPTR
    CLR A
    MOVC A,@A+DPTR
    CJNE A,#0,LCM_LOOP_dB

    MOV LCM_CTR,#2      ; 第二次再將分貝數顯示到LCM上

    MOV C,PIN_SWH_MD
    CPL C               ; 使LCM初次進到DRIVE_LCM會顯示MODE的部分
    MOV SWH_MD_R,C

    MOV C,PIN_SWH_SP
    CPL C               ; 使LCM初次進到DRIVE_LCM會顯示SSP的部分
    MOV SWH_SP_R,C

    ; ---------- 其他設定 -----------
    MOV NPTR,#080H      ; 新資料指標指向聲音Array的第一筆
    MOV LED_CTR,#0      ; 第一次進到DRIVE_LED先顯示紅色部分
    MOV SERIAL_CTR,#4   ; 第四次進到SEND_SERIAL才會將資料送出

LOOP:                   ; 主迴圈
    ACALL DRIVE_LCM     ; 將指撥開關狀態、聲音分貝數更新在LCM上
    ACALL SEND_SERIAL   ; 將聲音資料以串列傳輸送出
    ACALL DELAY
    AJMP LOOP

; ================ SOME FUNCTIONS ================
GET_SOUND_MAGNI:    ; 讀取麥克風類比訊號，並對時間微分，再取絕對值，即聲音強度
    MOV A,ADCH  ; 讀取麥克風的類比訊號，ADCH[7:0]為高八位，
    MOV B,ADCL  ; ADCL[1:0]為低二位 (8051內建ADC為10-bit)
    MOV C,B.1
    RLC A
    MOV C,B.0
    RLC A       ; 取ADC[7:0] (低八位) 作為訊號源
    MOV TEMP,A

    CLR C
    SUBB A,MIC_R    ; 將這次的訊號值減去上次的訊號值
    MOV SOUND_MAGNI,A
    JB SOUND_MAGNI.7,NEG_SOUND  ; 若為負，則變號
    SJMP RECORD_MIC
    NEG_SOUND:
    CPL A           ; 2'complement轉正數
    INC A
    MOV SOUND_MAGNI,A
    RECORD_MIC:     ; 紀錄上次MIC的值
    MOV A,TEMP
    MOV MIC_R,A

    MODE_PICK:
    JB PIN_SWH_MD,MODE2 ; 使用者可透過指撥開關選擇是否進行聲音強度後處理
    AJMP ADC_RST        ; 聲音顯示模式1：SOUND_MAGNI為及時的聲音強度

    MODE2:              ; 聲音顯示模式2：SOUND_MAGNI為前10次聲音強度最大值
    MOV @NPTR,SOUND_MAGNI   ; 將當前聲音強度放入資料庫中
    CJNE NPTR,#089H,INC_NPTR    ; 改變NPTR的值，使它在#80H~#89H之間循環
    MOV NPTR,#080H
    SJMP FIND_MAX
    INC_NPTR:
    INC NPTR

    FIND_MAX:           ; 找出資料記憶體中80H~89H位置的資料最大值
    MOV TEMP,#0         ; TEMP用於紀錄最大值
    MOV OPTR,#080H
    SEARCH_LOOP:
        MOV A,TEMP
        CLR CY
        SUBB A,@OPTR    ; 相減弱為負，則CY=1，反之CY=0
        JB CY,NEW_MAX   ; 若@OPTR大於TEMP，則代表@OPTR是新的最大值
        SJMP NXT_SRCH_LOOP
        NEW_MAX:
        MOV TEMP,@OPTR
        NXT_SRCH_LOOP:
    INC OPTR
    CJNE OPTR,#08AH,SEARCH_LOOP
    MOV SOUND_MAGNI,TEMP    ; 將前10筆資料最大值作為輸出

    ADC_RST:                ; 觸發ADC採樣，以利下一次計算聲音強度
    ANL ADCTL,#11101111B    ; Clear ADCI
    ORL ADCTL,#00001000B    ; Set ADCS

    RET

DRIVE_LED:      ; 使用非delay的方式驅動RGB LED
    MOV B,#16
    MOV A,SOUND_MAGNI
    DIV AB
    MOV TEMP,A

    INC LED_CTR ; LED_CTR若為1則驅動紅色LED，2則驅動綠色，3則驅動藍色

    LED_R:      ; 紅色LED部分
    CJNE LED_CTR,#1,LED_G
    CLR PIN_LED_R   ; Enable紅色LED
    SETB PIN_LED_G
    SETB PIN_LED_B
    MOV DPTR,#MAGNI_LED_R
    MOV A,TEMP
    MOVC A,@A+DPTR  ; 以聲音強度作為Index，取LED圖樣table
    MOV PIN_LED_OUT,A
    SJMP FINISH_LED
    LED_G:      ; 綠色LED部分
    CJNE LED_CTR,#2,LED_B
    SETB PIN_LED_R
    CLR PIN_LED_G
    SETB PIN_LED_B
    MOV DPTR,#MAGNI_LED_G
    MOV A,TEMP
    MOVC A,@A+DPTR
    MOV PIN_LED_OUT,A
    SJMP FINISH_LED
    LED_B:      ; 藍色LED部分
    SETB PIN_LED_R
    SETB PIN_LED_G
    CLR PIN_LED_B
    MOV DPTR,#MAGNI_LED_B
    MOV A,TEMP
    MOVC A,@A+DPTR
    MOV PIN_LED_OUT,A

    MOV LED_CTR,#0  ; 若LED_CTR已經加到3，則歸零
    
    FINISH_LED:

    RET

DRIVE_LCM:      ; 驅動LCM顯示指撥開關狀態、聲音分貝數，並在資料沒有變動時跳過更新程序
    DISP_MD:            ; 顯示"MIC:"後面的選項
    MOV C,PIN_SWH_MD    ; Capture PIN_SWH_MD
    MOV SWH_MD_C,C
    JB SWH_MD_C,SWH_MD_IS1      ; 檢查SWH_MD_C(Captured)與SWH_MD_R(Recorded)使否相同
    SWH_MD_IS0:
    JNB SWH_MD_R,FINISH_LCM_MD
    SJMP SWH_MD_CHANGE
    SWH_MD_IS1:
    JB SWH_MD_R,FINISH_LCM_MD
    SWH_MD_CHANGE:      ; 若檢查發現指撥開關狀態改變(Captured與Recorded不同)，則更新螢幕上的資訊

    MOV A,#10000100B    ; AC指向第一行第5個字
    ACALL COMMAND
    JB SWH_MD_C,DISP_M2
    DISP_M1:                ; 顯示"sensitive " (代表及時模式)
    MOV DPTR,#LCM_FONT_MIC1
    CLR A
    MOVC A,@A+DPTR
    LCM_LOOP_MODE1:
    ACALL SDATA
    INC DPTR
    CLR A
    MOVC A,@A+DPTR
    CJNE A,#0,LCM_LOOP_MODE1
    SJMP FINISH_LCM_MD
    DISP_M2:                ; 顯示"steady    " (代表經過取最大值程序的穩定模式)
    MOV DPTR,#LCM_FONT_MIC2
    CLR A
    MOVC A,@A+DPTR
    LCM_LOOP_MODE2:
    ACALL SDATA
    INC DPTR
    CLR A
    MOVC A,@A+DPTR
    CJNE A,#0,LCM_LOOP_MODE2

    FINISH_LCM_MD:
    MOV C,SWH_MD_C          ; 紀錄上次指撥開關的狀態
    MOV SWH_MD_R,C

    DISP_SSP:               ; 顯示"SSP"後面的選項
    MOV C,PIN_SWH_SP        ; Capture PIN_SWH_SP
    MOV SWH_SP_C,C
    JB SWH_SP_C,SWH_SP_IS1      ; 檢查SWH_SP_C與SWH_SP_R使否相同
    SWH_SP_IS0:
    JNB SWH_SP_R,FINISH_LCM_SP
    SJMP SWH_SP_CHANGE
    SWH_SP_IS1:
    JB SWH_SP_R,FINISH_LCM_SP
    SWH_SP_CHANGE:          ; 若檢查發現指撥開關狀態改變，則更新螢幕上的資訊

    MOV A,#11000100B  ; AC指向第二行第5個字
    ACALL COMMAND
    JB SWH_SP_C,DISP_SP_FAST
    DISP_SP_SLOW:
    MOV DPTR,#LCM_FONT_SSP_S
    CLR A
    MOVC A,@A+DPTR
    LCM_LOOP_SP_SLOW:
    ACALL SDATA
    INC DPTR
    CLR A
    MOVC A,@A+DPTR
    CJNE A,#0,LCM_LOOP_SP_SLOW
    SJMP FINISH_LCM_SP
    DISP_SP_FAST:
    MOV DPTR,#LCM_FONT_SSP_F
    CLR A
    MOVC A,@A+DPTR
    LCM_LOOP_SP_FAST:
    ACALL SDATA
    INC DPTR
    CLR A
    MOVC A,@A+DPTR
    CJNE A,#0,LCM_LOOP_SP_FAST

    FINISH_LCM_SP:
    MOV C,SWH_SP_C          ; 紀錄上次指撥開關的狀態
    MOV SWH_SP_R,C

    DISP_dB:            ; 顯示"[   dB]"中的分貝數值
    DJNZ LCM_CTR,FINISH_LCM_dB
    MOV A,#11001010B    ; AC指向第二行第11個字
    ACALL COMMAND
    MOV A,SOUND_MAGNI
    MOV B,#3
    DIV AB      ; Mapping to dB
    ADD A,#40   ; Mapping to dB
    ADD A,B     ; Mapping to dB
    MOV B,#100
    DIV AB      ; 取出分貝數的百位數
    ADD A,#48   ; 轉為ASCII CODE
    ACALL SDATA
    MOV A,B
    MOV B,#10
    DIV AB      ; 取出分貝數的十位數
    ADD A,#48   ; 轉為ASCII CODE
    ACALL SDATA
    MOV A,B     ; 取出分貝數的個位數
    ADD A,#48   ; 轉為ASCII CODE
    ACALL SDATA

    FINISH_LCM_dB:

    RET

SEND_SERIAL:    ; 將聲音強度資料以串列傳輸送出
    JB PIN_SWH_SP,SERIAL_FAST   ; 使用者可透過指撥開關決定傳輸的頻率
    SERIAL_SLOW:    ; 慢速傳輸模式
    DJNZ SERIAL_CTR,FINISH_SERIAL
    MOV SBUF,SOUND_MAGNI
    MOV SERIAL_CTR,#4
    SJMP FINISH_SERIAL
    SERIAL_FAST:    ; 快速傳輸模式
    JNB TI,FINISH_SERIAL    ; 若上次的資料尚未傳輸完畢，則跳過這次的傳輸
    CLR TI
    MOV SBUF,SOUND_MAGNI

    FINISH_SERIAL:

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
	MOV R6,#0FFH
DELAY1:
	MOV R7,#013H    ; 0AH
DELAY2:
	DJNZ R7,DELAY2
	DJNZ R6,DELAY1
	RET

; ============== INTERRUPT FUNCTIONS =============

T0_INT:
    PUSH 0E0H   ; 將主程式會用到的變數以stack暫存
    PUSH B
    PUSH DPL
    PUSH DPH
    MOV TEMP_BIT,C

    ACALL GET_SOUND_MAGNI   ; 取得聲音強度資料
    ACALL DRIVE_LED         ; 將聲音強度以RGB LED視覺化

    MOV TH0,#243    ; 決定多久以後再進入T0_INT
    MOV TL0,#0

    MOV C,TEMP_BIT
    POP DPH
    POP DPL
    POP B
    POP 0E0H
    RETI

; ==================== TABLES ====================
; RGB LED的圖樣
MAGNI_LED_R:
    DB 11111110B, 11111100B, 11111100B, 11111100B
    DB 11111100B, 11111100B, 10111100B, 00111100B
MAGNI_LED_G:
    DB 11111111B, 11111111B, 11111011B, 11110011B
    DB 11110011B, 11010011B, 10010011B, 00010011B
MAGNI_LED_B:
    DB 11111111B, 11111111B, 11111111B, 11111111B
    DB 11101111B, 11001111B, 10001111B, 00001111B

; 要顯示再LCM上的字串：
LCM_FONT_MIC:
    DB "MIC:",0
LCM_FONT_SSP:
    DB "SSP:",0
LCM_FONT_dB:
    DB "[   dB]",0
LCM_FONT_MIC1:
    DB "sensitive",0
LCM_FONT_MIC2:
    DB "steady   ",0
LCM_FONT_SSP_S:
    DB "slow",0
LCM_FONT_SSP_F:
    DB "fast",0