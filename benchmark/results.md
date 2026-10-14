| Command | Mean Wall Time [ms] | Change | Factor |
|:---|---:|---:|:---|
| `./zig-out/bin/agy_title` | 2.0 ± 0.5 |  |  |
| `bash benchmark/title.sh` | 14.1 ± 1.4 | +617.0% | (7.2x slower) |
| `python3 benchmark/title.py` | 28.8 ± 1.5 | +1363.6% | (14.6x slower) |
| `node benchmark/title.js` | 62.3 ± 23.1 | +3066.0% | (31.7x slower) |
