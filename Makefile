# shortcuts so nobody has to remember the commands
#   make sim    -> full regression (Phase I + Phase II, about 20 s)
#   make quick  -> same but skips the stress and UART runs
#   make synth  -> yosys / nextpnr synthesis, results in synth/summary.md
#   make clean  -> delete build files

.PHONY: all sim quick synth clean

all: sim synth

sim:
	./scripts/run_sim.sh

quick:
	QUICK=1 ./scripts/run_sim.sh

synth:
	./scripts/run_synth.sh

clean:
	rm -rf sim/build synth/build
