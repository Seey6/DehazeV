MODULE=dehaze_top
IMG_WIDTH=800
IMG_HEIGHT=600

.PHONY: sim
sim: waveform.vcd

.PHONY: verilat
verilat: .stamp.verilat

.stamp.verilat: rtl/*.v sim/sim_main.cpp
	verilator -cc --exe --build -j 4 -Wall --trace \
		-LDFLAGS "-lopencv_core -lopencv_imgproc -lopencv_imgcodecs" \
		-CFLAGS "$(shell pkg-config --cflags opencv4)" \
		-GWIDTH=$(IMG_WIDTH) -GHEIGHT=$(IMG_HEIGHT) \
		-Irtl \
		sim/sim_main.cpp rtl/$(MODULE).v \
		--top-module $(MODULE) \
		-o $(MODULE)
	touch .stamp.verilat

waveform.vcd: .stamp.verilat
	obj_dir/$(MODULE)

# Test min_filter_3x3 module
.PHONY: test_min3x3
test_min3x3: .stamp.min3x3
	obj_dir/min_filter_3x3
	@echo "Waveform saved to waveform.vcd"
	@echo "View with: gtkwave waveform.vcd"

.stamp.min3x3: rtl/min_filter_3x3.v sim/sim_min_filter_3x3.cpp rtl/line_buffer.v
	verilator -cc --exe --build -j 4 -Wall --trace \
		sim/sim_min_filter_3x3.cpp rtl/min_filter_3x3.v rtl/line_buffer.v \
		--top-module min_filter_3x3 \
		-o min_filter_3x3
	touch .stamp.min3x3

# Test ale module
.PHONY: test_ale
test_ale: .stamp.ale
	obj_dir/ale
	@echo "ALE Test Completed"
	@echo "Waveform saved to ale.vcd"

.stamp.ale: rtl/ale.v rtl/min_filter_3x3.v sim/sim_ale.cpp
	verilator -cc --exe --build -j 4 -Wall --trace \
		-LDFLAGS "-lopencv_core -lopencv_imgproc -lopencv_imgcodecs" \
		-CFLAGS "$(shell pkg-config --cflags opencv4)" \
		sim/sim_ale.cpp rtl/ale.v rtl/min_filter_3x3.v \
		--top-module ale \
		-o ale
	touch .stamp.ale

# Test calc_sat module
.PHONY: test_calc_sat
test_calc_sat: .stamp.calc_sat
	obj_dir/calc_sat
	@echo "Calc_Sat Test Completed"

.stamp.calc_sat: rtl/calc_sat.v sim/sim_calc_sat.cpp
	verilator -cc --exe --build -j 4 -Wall --trace \
		sim/sim_calc_sat.cpp rtl/calc_sat.v rtl/lut_inv_A.v rtl/lut_khn.v \
		--top-module calc_sat \
		-o calc_sat
	touch .stamp.calc_sat

# Test calc_t module
.PHONY: test_calc_t
test_calc_t: .stamp.calc_t
	obj_dir/calc_t
	@echo "Calc_T Test Completed"

.stamp.calc_t: rtl/calc_t.v sim/sim_calc_t.cpp
	verilator -cc --exe --build -j 4 -Wall --trace \
		sim/sim_calc_t.cpp rtl/calc_t.v rtl/lut_inv12.v \
		--top-module calc_t \
		-o calc_t
	touch .stamp.calc_t

.PHONY: clean
clean:
	rm -rf obj_dir .stamp.* waveform.vcd output.png output.ppm
