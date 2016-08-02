\
\ rtc.f v1.0
\ stm32l152rb
\ Ilya Abdrahimov
\ REQUIRE st32l152.f
\ REQUIRE interrupts.f
\ Words:
\ rtc-init - rtc initialization
\ rtc-set-time  - set time ( hh mm ss -- )
\ rtc-set-date  - set date ( yy wd mm dd -- )
\ rtc-get-time  - get time ( -- hh mm ss )
\ rtc-get-date  - get date ( -- yy wd mm dd )
\ rtc-alarm-init - rtc initialization ( addra addrb -- ) \ addra&addrb - Address your words alarm handlers
\ rtc-alarma-set - initialization alarm A ( hh mm -- ) \ hh - hour, mm - minutes
\ rtc-alarmb-set - initialization alarm B ( hh mm -- ) \ hh - hour, mm - minutes
\ rtc-alarma-disable - disable Alarm A
\ rtc-alarmb-disable - disable Alarm B
\ rtc-alarma-gt - Get Alarm A time  ( -- hh mm )
\ rtc-alarmb-gt - Get Alarm B time  ( -- hh mm )

$10000000 constant RCC_APB1ENR_PWREN  \ Power interface clock enable
$100 constant PWR_CR_DBP \ Disable Backup Domain write protection
$400000 constant RCC_CSR_RTCEN \ RTC clock enable
$0 constant RCC_CSR_RTCSEL_NOCLOCK \ No clock
$10000 constant  RCC_CSR_RTCSEL_LSE  \ LSE oscillator clock used as RTC clock 
$20000 constant  RCC_CSR_RTCSEL_LSI  \ LSI oscillator clock used as RTC clock 
$30000 constant  RCC_CSR_RTCSEL_HSE  \ HSE oscillator clock divided by 2, 4, 8 or 16 by RTCPRE used as RTC clock 

: dec>bcd
#10 /mod 4 lshift or
;

: bcd>dec 
dup $f and swap 4 rshift 10 * +
;
\ RTC initialization
: rtc-init ( -- )
\  $20 RTC_ISR bit@ 0= \  Calendar has been initialized ?
\	IF	
		RCC_APB1ENR @ RCC_APB1ENR_PWREN or RCC_APB1ENR ! \ Power interface clock enable
		PWR_CR_DBP PWR_CR bis! \ Disable Backup Domain write protection
		\ $800000 rcc_csr bis!
		\ $800000 rcc_csr bic!
		\ $1 RCC_CSR bis!	\ LSI on
		\ begin $2 RCC_CSR bit@ until \ wait LSI ready
		1 8 lshift RCC_CSR bis!	\ LSE on
		begin $200 RCC_CSR bit@ until \ wait LSE ready
		RCC_CSR @ RCC_CSR_RTCSEL_LSE or RCC_CSR !	\ 10: LSI oscillator clock used as RTC/LCD clock
		RCC_CSR_RTCEN RCC_CSR bis! \ RTC clock enable
		$ca RTC_WPR c! $53 RTC_WPR c!
\	THEN
;

: rtc-cal-set-on
$80 RTC_ISR bis! 
begin $40 rtc_isr bit@ until \ Calendar registers update is allowed.
$7f00ff RTC_PRER !	\ From LSI, LSE - $ff
$7f00ff RTC_PRER !
;

: rtc-cal-set-off
$80 RTC_ISR bic! 
;

\ Set 12/24 time notation
: rtc-12/24 ( n -- ) \ 1 - am/pm, 0 -24h
$20 RTC_ISR bit@  \ Calendar has been initialized ?
if
	rtc-cal-set-on
	if #400000 RTC_TR bis! else #400000 RTC_TR bic! then
	rtc-cal-set-off 
else 
	drop
then
;

: rtc-set-time ( h m s -- )
$20 RTC_ISR bit@  \ Calendar has been initialized ?
if
	rtc-cal-set-on
	dec>bcd swap
	dec>bcd 8 lshift or swap
	dec>bcd 16 lshift or
	RTC_TR !
	rtc-cal-set-off
else	
	drop 2drop \ clear stack
	
then
;

: rtc-set-date ( yy wd mm dd -- )
$20 RTC_ISR bit@  \ Calendar has been initialized ?
if
	rtc-cal-set-on
	dec>bcd swap dec>bcd 8 lshift or
	swap 13 lshift or
	swap dec>bcd 16 lshift or  RTC_DR !
	rtc-cal-set-off
else
	2drop 2drop \ clear stack
then 
;

: rtc-get-time ( -- h m s )
rtc_tr @ dup >r 16 rshift bcd>dec r@ 8 rshift $ff and bcd>dec r> $ff and bcd>dec 
;

: rtc-get-date ( -- yy wd mm dd )
rtc_dr @ dup >r 16 rshift bcd>dec r@ 8 rshift dup $e0 and 5 rshift swap $1f and bcd>dec r> $ff and bcd>dec 
;



\ rtc-alarm
\ SAMPLE:
\ ' youalarmAhandler ' youalarmBhandler rtc-alarm-init
\ 4 26 set-alarma
\

0 variable alarma-addr	\ Alarm A interrupt handler
0 variable alarmb-addr	\ Alarm B interrupt handler

: irq-alarm
RTC_ISR @ $300 and
	case
		$100 of alarma-addr @  $100 RTC_ISR bic! endof
		$200 of alarmb-addr @  $200 RTC_ISR bic! endof
	endcase
?dup if execute then
1 17 lshift exti_pr bis! 
;


: rtc-alarm-time ( hh mm -- n )
0
1 31 lshift or	\ date/day don't care Alarm comparison
swap dec>bcd 8 lshift or \ mm
swap dec>bcd 16 lshift or \ hh
;

: alarma-mask
1 21 lshift	\ Alarm A output enabled
1 12 lshift or	\ Alarm A interrupt enbled
1 8 lshift or	\ Alarm A enabled
;

: alarmb-mask
1 22 lshift	\ Alarm B output enabled
1 13 lshift or	\ Alarm B interrupt enbled
1 9 lshift or	\ Alarm B enabled
;

: rtc-alarma-disable ( -- ) alarma-mask RTC_CR bic! ;

: rtc-alarmb-disable ( -- ) alarmb-mask RTC_CR bic! ;

: rtc-alarma-set ( hh mm -- ) 
rtc-cal-set-on
rtc-alarmb-disable
1 8 lshift RTC_ISR bic!
$100 rtc_isr bic! \
rtc-alarm-time RTC_ALRMAR !
1 22 lshift  RTC_CR bic! \ Alarm B output disabled
alarma-mask
RTC_CR bis!
rtc-cal-set-off
;

: rtc-alarmb-set ( hh mm -- ) 
rtc-cal-set-on
rtc-alarma-disable
1 9 lshift RTC_ISR bic!
$200 rtc_isr bic! \
rtc-alarm-time RTC_ALRMBR !
1 21 lshift  RTC_CR bic! \ Alarm A output disabled
alarmb-mask
RTC_CR bis!
rtc-cal-set-off
;

\ Get Alarm A time 
: rtc-alarma-gt ( -- hh mm )
RTC_ALRMAR @ dup 16 rshift $ff and bcd>dec
swap 8 rshift $ff and bcd>dec
;
\ Get Alarm B time 
: rtc-alarmb-gt ( -- hh mm )
RTC_ALRMBR @ dup 16 rshift $ff and bcd>dec
swap 8 rshift $ff and bcd>dec
;

: rtc-alarm-init ( addra addrb -- )
alarmb-addr ! alarma-addr ! 
['] irq-alarm irq-rtc_alarm !
RCC_APB2ENR_SYSCFGEN RCC_APB2ENR bis!
RTC_Alarm_IRQn nvic-enable
1 17 lshift exti_rtsr bis!
1 17 lshift exti_imr bis! 
;

\ sample
\ : t rtc-get-time cr rot . ." :" swap . ." :" . ;
\ : d rtc-get-date cr . ." / " . drop ." /" . ;
\ : re cr ." isr:" rtc_isr @ hex. space ." cr:" rtc_cr @ hex. ;

\ : mya cr ." Alarm A:" t cr ;
\ : myb cr ." Alarm B:" t cr ;

rtc-init



\ ' mya ' myb rtc-alarm-init
\ 12 34 56 rtc-set-time
\ 12 36 rtc-alarma-set
