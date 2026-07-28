create_project synth_proj ./vivado_proj -part xc7z020clg484-1 -force

add_files -norecurse {FPGA_Prova1_fixedpoint.v SoC_Bus_Creator.v MATLAB_Function.v}
update_compile_order -fileset sources_1

synth_design -top FPGA_Prova1_fixedpoint

report_utilization -file utilization_report.txt
report_timing_summary -file timing_report.txt -max_paths 5

puts "SYNTHESIS_DONE_OK"
