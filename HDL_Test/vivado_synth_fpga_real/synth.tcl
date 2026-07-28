create_project synth_proj ./vivado_proj -part xc7z020clg484-1 -force

add_files -norecurse {FPGA.v SoC_Bus_Creator.v MATLAB_Function.v}
update_compile_order -fileset sources_1

synth_design -top FPGA -mode out_of_context

report_utilization -file utilization_synth.txt

opt_design
place_design
route_design

report_utilization -file utilization_impl.txt
report_timing_summary -file timing_impl.txt -max_paths 5

puts "SYNTH_AND_IMPL_DONE_OK"
