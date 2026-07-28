open_project ./vivado_proj/synth_proj.xpr
open_run synth_1

report_timing -delay_type max -path_type full -unconstrained -max_paths 5 -file unconstrained_timing.txt
report_timing -delay_type max -path_type full -unconstrained -max_paths 1 -to [get_ports matA_fixed_out_0] -file worst_path_matA0.txt

puts "TIMING_CHECK_DONE_OK"
