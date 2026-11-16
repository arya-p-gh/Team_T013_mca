# shortcuts so nobody has to remember the commands
#   make sim     -> run all testbenches
#   make synth   -> synthesis + summary table
#   make figures -> redraw the plots
#   make report  -> rebuild the PDF
PY ?= .venv/bin/python

.PHONY: all sim synth figures report clean

all: sim synth figures report

sim:
	./scripts/run_sim.sh

synth:
	./scripts/run_synth.sh

figures:
	$(PY) scripts/make_figures.py

report:
	cd report/diagrams && for f in block_diagram pe_micro fsm; do tectonic -X compile $$f.tex; done
	cd report && tectonic -X compile report.tex

clean:
	rm -rf sim/build synth/build
