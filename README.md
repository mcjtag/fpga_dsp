# fpga_dsp
DSP algorithms and utilities on FPGA

## Digital Filters (filt)

* Median Filter (filt_median)

### Median Filter
##### Parameters
* `DATA_WIDTH` - width of input data
* `ORDER`      - filter order (usually odd number)
* `FORMAT`     - number format (0 - unsigned, 1 - signed)
##### Ports
* `aclk`          - clock
* `aresetn`       - synchronous reset (active-LOW)
* `s_axis_tdata`  - input data (width = DATA_WIDTH)
* `s_axis_tvalid` - input data valid
* `s_axis_tready` - output ready for input data
* `m_axis_tdata`  - output data (width = DATA_WIDTH)
* `m_axis_tvalid` - output data valid
* `m_axis_tready` - input ready for output data
