open_project ./vivado_proj/synth_proj.xpr
open_run synth_1

create_clock -name virt_clk -period 10
set_input_delay -clock virt_clk 0 [all_inputs]
set_output_delay -clock virt_clk 0 [all_outputs]

report_timing -delay_type max -path_type full -max_paths 5 -file real_timing_paths.txt
report_timing_summary -file real_timing_summary.txt -max_paths 5

puts "TIMING_CHECK_DONE_OK"
