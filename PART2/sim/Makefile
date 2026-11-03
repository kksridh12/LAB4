
VCS ?= $(VCS_HOME)/bin/vcs
VERDI ?= $(VERDI_HOME)/bin/verdi
SV_SRCS := \
	../fifo_tb.sv \
	../fifo.sv \
	../fifomem.sv \
	../rptr_empty.sv \
	../sync_r2w.sv \
	../sync_w2r.sv \
	../wptr_full.sv


all: compile_and_sim

# This compiles with VCS and runs simulation
compile_and_sim:
	$(VCS) -R -full64 -sverilog $(SV_SRCS) -kdb -lca -debug_access+all |& tee compile_and_sim.log

# This compiles with VCS
compile:
	$(VCS) -full64 -sverilog $(SV_SRCS) -debug_access+all |& tee compile.log

# This compiles with VCS and also generates the database for Verdi
compile_verdi:
	$(VCS) -full64 -sverilog $(SV_SRCS) -debug_access+all -kdb -lca |& tee compile_verdi.log

# This compiles UVM as well, but we are not using it for now
compile_uvm:
	$(VCS) -full64 -sverilog $(SV_SRCS) -debug_access+all -ntb_opts uvm |& tee compile_uvm.log

# This runs simulation
sim:
	./simv

# This launches Verdi
verdi:
	$(VERDI) -dbdir ./simv.daidir -nologo

# This launches Verdi with waves loaded
waves_verdi:
	$(VERDI) -dbdir ./simv.daidir -ssf novas.fsdb -nologo

clean:
	rm -rf *.log *.h csrc DVEFiles simv.daidir simv ucli.key vcdplus.vpd *.syn *.pvl *.mr *.svf command.log *.txt novas.conf novas.rc verdi_config_file verdiLog novas.fsdb novas.log nuevas_dump.log

