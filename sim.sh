#!/bin/bash
# Simulate one project with Icarus Verilog and write a waveform.
#
# Usage: ./sim.sh <path> [--waves] [--lint]
#   <path>   any file or folder inside a project (a folder that has sim/)
#   --waves  open the waveform in Surfer after the run
#   --lint   only check the code with Verilator, no simulation
#
# The project folder is the nearest parent that contains sim/.
# All .sv/.v files inside it are compiled; the top module is taken
# from sim/tb_*.sv (override with TOP=name ./sim.sh ...).
# Output goes to <project>/sim_build/ (wave.fst, sim.log).

set -o pipefail

WAVES=0
LINT=0
TARGET=""
for arg in "$@"; do
    case "$arg" in
        --waves) WAVES=1 ;;
        --lint)  LINT=1 ;;
        *)       TARGET="$arg" ;;
    esac
done

if [ -z "$TARGET" ]; then
    echo "Usage: $0 <path inside a project> [--waves] [--lint]"
    exit 2
fi

# Find the project folder: walk up until a folder with sim/ is found.
DIR=$(cd "$( [ -d "$TARGET" ] && echo "$TARGET" || dirname "$TARGET")" && pwd)
while [ "$DIR" != "/" ] && [ ! -d "$DIR/sim" ]; do
    DIR=$(dirname "$DIR")
done
if [ ! -d "$DIR/sim" ]; then
    echo "No project with a sim/ folder found above: $TARGET"
    exit 1
fi
PROJ="$DIR"
BUILD="$PROJ/sim_build"

# Sources: every .sv/.v in the project except build output.
FILES=$(find "$PROJ" -type f \( -name "*.sv" -o -name "*.v" \) -not -path "$BUILD/*" | sort)

# Top module: first module declared in sim/tb_*.sv (or sim/*.sv).
if [ -z "$TOP" ]; then
    TB_FILE=$(ls "$PROJ"/sim/tb_*.sv "$PROJ"/sim/*.sv 2>/dev/null | head -1)
    TOP=$(sed -nE 's/^[[:space:]]*module[[:space:]]+([A-Za-z_][A-Za-z0-9_]*).*/\1/p' "$TB_FILE" | head -1)
fi
if [ -z "$TOP" ]; then
    echo "Could not find the testbench top module in $PROJ/sim"
    exit 1
fi

echo "Project: $PROJ"
echo "Top:     $TOP"

if [ $LINT -eq 1 ]; then
    verilator --lint-only --timing -Wno-fatal --top-module "$TOP" $FILES
    exit $?
fi

mkdir -p "$BUILD"

# Extra top module that turns on waveform dumping, so testbenches stay untouched.
cat > "$BUILD/dump.sv" <<EOF
module sim_dump;
  initial begin
    \$dumpfile("wave.fst");
    \$dumpvars(0, $TOP);
  end
endmodule
EOF

iverilog -g2012 -o "$BUILD/sim.vvp" -s "$TOP" -s sim_dump $FILES "$BUILD/dump.sv" || {
    echo "Compilation FAILED"
    exit 1
}

# -n: \$stop ends the run instead of opening the interactive prompt.
# -fst: write the dump as FST (much smaller than VCD).
( cd "$BUILD" && vvp -n sim.vvp -fst ) 2>&1 | tee "$BUILD/sim.log"
STATUS=$?

echo ""
echo "Waveform: $BUILD/wave.fst"

if [ $WAVES -eq 1 ]; then
    nohup surfer "$BUILD/wave.fst" >/dev/null 2>&1 &
    disown
fi

if [ $STATUS -ne 0 ] || grep -iqE "fail|error" "$BUILD/sim.log"; then
    echo "Simulation FAILED"
    exit 1
fi
echo "Simulation PASSED"
