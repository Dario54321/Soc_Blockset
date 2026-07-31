/*
 * File Name:         D:\SocBuilderBuild\prova2_vivado_prj\ipcore\soc_wrapp_ip_v1_0\include\soc_wrapp_ip_addr.h
 * Description:       C Header File
 * Created:           2026-07-31 12:35:01
*/

#ifndef SOC_WRAPP_IP_H_
#define SOC_WRAPP_IP_H_

#define  IPCore_Reset_soc_wrapp_ip        0x0  //write 0x1 to bit 0 to reset IP core
#define  IPCore_Enable_soc_wrapp_ip       0x4  //enabled (by default) when bit 0 is 0x1
#define  IPCore_Timestamp_soc_wrapp_ip    0x8  //contains unique IP timestamp (yymmddHHMM): 2607311234
#define  start_cmd_Data_soc_wrapp_ip      0x100  //data register for Inport start_cmd
#define  timeout_thr_Data_soc_wrapp_ip    0x104  //data register for Inport timeout_thr
#define  x1_Data_soc_wrapp_ip             0x108  //data register for Inport x1
#define  x2_Data_soc_wrapp_ip             0x10C  //data register for Inport x2
#define  x0_Data_soc_wrapp_ip             0x110  //data register for Inport x0
#define  x3_Data_soc_wrapp_ip             0x114  //data register for Inport x3
#define  x4_Data_soc_wrapp_ip             0x118  //data register for Inport x4
#define  x5_Data_soc_wrapp_ip             0x11C  //data register for Inport x5
#define  done_Data_soc_wrapp_ip           0x120  //data register for Outport done
#define  busy_Data_soc_wrapp_ip           0x124  //data register for Outport busy
#define  timeout_flag_Data_soc_wrapp_ip   0x128  //data register for Outport timeout_flag
#define  cycles_Data_soc_wrapp_ip         0x12C  //data register for Outport cycles
#define  u0_Data_soc_wrapp_ip             0x130  //data register for Outport u0

#endif /* SOC_WRAPP_IP_H_ */
