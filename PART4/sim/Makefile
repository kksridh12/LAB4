VCS ?= $(VCS_HOME)/bin/vcs
VERDI ?= $(VERDI_HOME)/bin/verdi

SV_SRCS := \
  odd_even_assert_if.sv \
  odd_even_part4_tb.sv \
  ../../odd_even.sv \
  ../../fifo.sv \
  ../../fifomem.sv \
  ../../rptr_empty.sv \
  ../../sync_r2w.sv \
  ../../sync_w2r.sv \
  ../../wptr_full.sv

.PHONY: compile_verdi sim_case4 sim_case5 sim_bug waves_case4 waves_case5 waves_bug clean

compile_verdi:
	$(VCS) -full64 -sverilog -assert enable -top odd_even_part4_tb $(SV_SRCS) -debug_access+all -kdb -lca -o simv 2>&1 | tee compile_verdi.log

sim_case4:
	./simv +TEST=case4 2>&1 | tee sim_case4.log

sim_case5:
	./simv +TEST=case5 2>&1 | tee sim_case5.log

sim_bug:
	./simv +TEST=case4 +INJECT_BUG 2>&1 | tee sim_bug.log

waves_case4:
	$(VERDI) -dbdir ./simv.daidir -ssf test1_case4.fsdb -nologo

waves_case5:
	$(VERDI) -dbdir ./simv.daidir -ssf test2_case5.fsdb -nologo

waves_bug:
	$(VERDI) -dbdir ./simv.daidir -ssf test1_case4.fsdb -nologo

clean:
	rm -rf simv simv.daidir csrc *.log *.fsdb *.key *.vpd ucli.key DVEFiles
