# shortcuts so nobody has to remember the commands
#   make sim    -> run all testbenches
#   make synth  -> yosys / nextpnr synthesis
#   make clean  -> delete build files

.PHONY: all sim synth clean

all: sim synth

sim:
	./scripts/run_sim.sh

synth:
	./scripts/run_synth.sh

clean:
	rm -rf sim/build synth/build
